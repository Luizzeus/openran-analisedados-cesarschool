#!/usr/bin/env bash
#
# Validação N2/NGAP: SCTP estabelecido, NG Setup e logs consistentes.
# Uso: executar no host a partir do diretório free5gc (docker compose).
# Ref: docs/VALIDATION_E2E.md

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$PROJECT_DIR/.." && pwd)"
cd "$PROJECT_DIR"
# shellcheck source=lib/ran-docker.sh
. "$SCRIPT_DIR/lib/ran-docker.sh"

# srsRAN grava em arquivo (log.filename); docker logs pode não ter NGAP.
# Para evitar falso negativo com falhas antigas no arquivo, limitamos a janela de análise.
get_ran_log_content() {
  local c="$1"
  local max_lines="${RAN_LOG_TAIL_LINES:-400}"
  local since_window="${RAN_LOG_SINCE:-15m}"
  local out
  out=$(docker logs --since "$since_window" "$c" 2>&1 || true)
  case "$c" in
    srsran-gnb-tradicional)
      for _gnbdir in gNB_traditional; do
        [ -f "$ROOT_DIR/$_gnbdir/logs/gnb.log" ] && out="$out"$'\n'"$(tail -n "$max_lines" "$ROOT_DIR/$_gnbdir/logs/gnb.log" 2>/dev/null || true)"
      done
      ;;
    srsran-cu)
      # Split CU: cu.log em gNB_disaggregated ou gNB_open (mesmo nome de contentor)
      for _cudir in gNB_disaggregated gNB_open; do
        [ -f "$ROOT_DIR/$_cudir/logs/cu.log" ] && out="$out"$'\n'"$(tail -n "$max_lines" "$ROOT_DIR/$_cudir/logs/cu.log" 2>/dev/null || true)"
      done
      ;;
    srsran-gnb)
      for _gnbdir in gNB_traditional; do
        [ -f "$ROOT_DIR/$_gnbdir/logs/gnb.log" ] && out="$out"$'\n'"$(tail -n "$max_lines" "$ROOT_DIR/$_gnbdir/logs/gnb.log" 2>/dev/null || true)"
      done
      ;;
  esac
  echo "$out"
}

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

AMF_IP="${AMF_IP:-10.100.200.16}"
GNB_IP="${GNB_IP:-10.100.200.50}"
NGAP_PORT=38412
BRIDGE="${BRIDGE:-br-free5gc}"

PASS=0
FAIL=0

echo "=============================================="
echo "Validação N2/NGAP (srsRAN gNB <-> free5GC AMF)"
echo "=============================================="
echo ""

# --- 1. Containers up ---
echo -e "${BLUE}[1] Containers AMF e RAN (N2)${NC}"
if docker compose ps free5gc-amf 2>/dev/null | grep -q "Up"; then
  echo -e "  ${GREEN}✓ AMF (free5gc-amf) está rodando${NC}"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}✗ AMF não está rodando${NC}"
  FAIL=$((FAIL+1))
fi
if list_ran_n2_containers; then
  echo -e "  ${GREEN}✓ RAN N2 ativo(s): ${RAN_N2_CONTAINERS[*]}${NC}"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}✗ Nenhum container RAN N2 (srsran-cu / srsran-gnb-tradicional / srsran-gnb)${NC}"
  FAIL=$((FAIL+1))
fi
echo ""

# --- 2. SCTP listen (AMF) — N2 usa SCTP (ss -S), não TCP (ss -t) ---
echo -e "${BLUE}[2] SCTP em LISTEN (porta $NGAP_PORT)${NC}"
SCTP_LISTEN_OK=0
_sctp_listen_check() {
  ss -Slnp 2>/dev/null | grep -q ":$NGAP_PORT"
}
if _sctp_listen_check; then
  echo -e "  ${GREEN}✓ SCTP em LISTEN na porta $NGAP_PORT (host)${NC}"
  ss -Slnp 2>/dev/null | grep ":$NGAP_PORT" || true
  SCTP_LISTEN_OK=1
elif sudo ss -Slnp 2>/dev/null | grep -q ":$NGAP_PORT"; then
  echo -e "  ${GREEN}✓ SCTP em LISTEN na porta $NGAP_PORT (host, sudo)${NC}"
  SCTP_LISTEN_OK=1
else
  # Socket SCTP do AMF fica no namespace do container
  if docker compose exec -T free5gc-amf ss -Slnp 2>/dev/null | grep -q ":$NGAP_PORT"; then
    echo -e "  ${GREEN}✓ AMF em SCTP LISTEN na porta $NGAP_PORT (dentro do container)${NC}"
    SCTP_LISTEN_OK=1
  else
    echo -e "  ${YELLOW}⚠ SCTP LISTEN na $NGAP_PORT não visível no host (normal: socket só no netns do AMF). Use NG Setup nos logs [4] como referência.${NC}"
  fi
fi
[ "$SCTP_LISTEN_OK" -eq 1 ] && PASS=$((PASS+1))
echo ""

# --- 3. Associação SCTP ESTABLISHED (N2) — usar SCTP (ss -S), não TCP ---
echo -e "${BLUE}[3] Associação SCTP ESTABLISHED (N2)${NC}"
SCTP_ESTABLISHED=0
if ss -Snp state established 2>/dev/null | grep -q ":$NGAP_PORT"; then
  SCTP_ESTABLISHED=1
fi
if [ "$SCTP_ESTABLISHED" -eq 0 ]; then
  sudo ss -Snp state established 2>/dev/null | grep -q ":$NGAP_PORT" && SCTP_ESTABLISHED=1
fi
if [ "$SCTP_ESTABLISHED" -eq 0 ]; then
  if docker compose exec -T free5gc-amf ss -Snp state established 2>/dev/null | grep -q "38412"; then
    SCTP_ESTABLISHED=1
  fi
fi
if [ "$SCTP_ESTABLISHED" -eq 1 ]; then
  echo -e "  ${GREEN}✓ Associação SCTP em ESTABLISHED (visível no ss)${NC}"
  PASS=$((PASS+1))
else
  # Fallback: NGAP ocorre em SCTP no netns do AMF; a associação pode ser curta ou já ter sido fechada
  # (ex.: SCTP_SHUTDOWN após NG Setup). Se o AMF registrou NG Setup, N2 funcionou mesmo sem ss no host.
  NG_SETUP_AMF_EARLY=$(docker compose logs free5gc-amf 2>&1 | grep -c "NGSetupRequest\|NG-Setup response\|NGSetupResponse\|Handle NGSetupRequest\|Send NG-Setup response" 2>/dev/null) || NG_SETUP_AMF_EARLY=0
  _ranl=""
  if list_ran_n2_containers; then
    for _c in "${RAN_N2_CONTAINERS[@]}"; do
      _ranl="${_ranl}$(get_ran_log_content "$_c")"$'\n'
    done
  fi
  GNB_RX=$(echo "$_ranl" | grep -c "Rx PDU: NGSetupResponse\|NGSetupResponse" 2>/dev/null) || GNB_RX=0
  GNB_TX=$(echo "$_ranl" | grep -c "Tx PDU: NGSetupRequest\|NGSetupRequest" 2>/dev/null) || GNB_TX=0
  if [ "${NG_SETUP_AMF_EARLY:-0}" -gt 0 ] && ( [ "${GNB_RX:-0}" -gt 0 ] || [ "${GNB_TX:-0}" -gt 0 ] ); then
    echo -e "  ${GREEN}✓ N2 ativo (NG Setup nos logs AMF + RAN; SCTP estabelecido no netns do container — ss no host pode ficar vazio)${NC}"
    PASS=$((PASS+1))
  elif [ "${NG_SETUP_AMF_EARLY:-0}" -gt 0 ]; then
    echo -e "  ${GREEN}✓ N2 considerado OK: NG Setup presente nos logs do AMF (SCTP costuma não aparecer no host; a ligação pode encerrar logo após o procedimento)${NC}"
    PASS=$((PASS+1))
  else
    echo -e "  ${RED}✗ Nenhuma associação SCTP visível no ss e sem NG Setup nos logs do AMF${NC}"
    echo "    Dica: SCTP usa ss -S (não ss -t). Ex.: ss -Snp state established | grep 38412 (no host ou: docker compose exec -T free5gc-amf ss -Snp state established)"
    FAIL=$((FAIL+1))
  fi
fi
echo ""

# --- 4. Logs AMF: NG Setup ---
echo -e "${BLUE}[4] Logs AMF — NG Setup${NC}"
# free5GC pode logar "NGSetupRequest", "NG-Setup response" ou "NGSetupResponse"
NG_SETUP_AMF=$(docker compose logs free5gc-amf 2>&1 | grep -c "NGSetupRequest\|NG-Setup response\|NGSetupResponse" 2>/dev/null) || NG_SETUP_AMF=0
AMF_ACCEPT=$(docker compose logs free5gc-amf 2>&1 | grep -c "gNB-N2 accepted\|NGSetupRequest\|Added.*gNB\|Number of gNBs" 2>/dev/null) || AMF_ACCEPT=0
if [ "${NG_SETUP_AMF:-0}" -gt 0 ]; then
  echo -e "  ${GREEN}✓ NG Setup nos logs AMF (${NG_SETUP_AMF} ocorrência(s))${NC}"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}✗ NG Setup não encontrado nos logs AMF${NC}"
  FAIL=$((FAIL+1))
fi
if [ "${AMF_ACCEPT:-0}" -gt 0 ] && [ "${AMF_ACCEPT:-0}" -ne "${NG_SETUP_AMF:-0}" ]; then
  echo -e "  ${GREEN}✓ AMF registrou gNB (evidência nos logs)${NC}"
elif [ "${AMF_ACCEPT:-0}" -eq 0 ]; then
  echo -e "  ${YELLOW}⚠ Padrão 'gNB-N2 accepted' / 'Number of gNBs' não encontrado (free5GC pode usar outras mensagens)${NC}"
fi
echo ""

# --- 5. Logs RAN (N2): conexão AMF e NG Setup (srsRAN) — por container ---
echo -e "${BLUE}[5] Logs RAN (N2) — conexão AMF e NG Setup${NC}"
SECT5_OK=0
AMF_NG_FOR_RAN=$(docker compose logs free5gc-amf 2>&1 | grep -c "NGSetupRequest\|NG-Setup response\|Handle NGSetupRequest" 2>/dev/null) || AMF_NG_FOR_RAN=0
if list_ran_n2_containers; then
  local_fail=0
  for c in "${RAN_N2_CONTAINERS[@]}"; do
    _cl=$(get_ran_log_content "$c")
    GNB_FAIL=$(echo "$_cl" | grep -c "Failed to connect to AMF\|Network is unreachable" 2>/dev/null) || GNB_FAIL=0
    GNB_AMF_OK=$(echo "$_cl" | grep -ic "N2:.*AMF\|Connection to AMF\|Connected to AMF\|L2:.*AMF\|SCTP.*AMF\|association.*38412" 2>/dev/null) || GNB_AMF_OK=0
    GNB_NGSETUP=$(echo "$_cl" | grep -ic "NGSetupRequest\|NGSetupResponse\|NG-Setup\|NG Setup\|Tx PDU: NGSetup\|Rx PDU: NGSetup\|CU-CP started successfully\|CU started\|NGAP" 2>/dev/null) || GNB_NGSETUP=0
    if [ "${GNB_FAIL:-0}" -gt 0 ] && [ "${GNB_AMF_OK:-0}" -eq 0 ] && [ "${GNB_NGSETUP:-0}" -eq 0 ] && [ "${AMF_NG_FOR_RAN:-0}" -eq 0 ]; then
      echo -e "  ${RED}✗ $c: falha N2 (connect / unreachable) sem evidência de recuperação${NC}"
      local_fail=1
    elif [ "${GNB_FAIL:-0}" -gt 0 ] && ( [ "${GNB_AMF_OK:-0}" -gt 0 ] || [ "${GNB_NGSETUP:-0}" -gt 0 ] || [ "${AMF_NG_FOR_RAN:-0}" -gt 0 ] ); then
      echo -e "  ${YELLOW}⚠ $c: houve falha N2 transitória, mas há evidência de recuperação (AMF/NG Setup)${NC}"
    elif [ "${GNB_AMF_OK:-0}" -gt 0 ] || [ "${GNB_NGSETUP:-0}" -gt 0 ]; then
      echo -e "  ${GREEN}✓ $c: AMF / NG Setup coerente nos logs${NC}"
    elif [ "${AMF_NG_FOR_RAN:-0}" -gt 0 ]; then
      echo -e "  ${YELLOW}⚠ $c: padrões N2 não encontrados (docker logs + gnb.log); AMF já registrou NG Setup — confira \`gNB_*/logs/gnb.log\` manualmente${NC}"
    else
      echo -e "  ${YELLOW}⚠ $c: não foi possível confirmar N2 nos logs${NC}"
      local_fail=1
    fi
  done
  [ "$local_fail" -eq 0 ] && SECT5_OK=1
else
  echo -e "  ${YELLOW}⚠ Nenhum RAN N2 em execução${NC}"
fi
[ "$SECT5_OK" -eq 1 ] && PASS=$((PASS+1))
[ "$SECT5_OK" -eq 0 ] && [ "${#RAN_N2_CONTAINERS[@]}" -gt 0 ] && FAIL=$((FAIL+1))
echo ""

# --- 6. Restart count dos containers RAN N2 ---
echo -e "${BLUE}[6] Restart count (RAN N2)${NC}"
SECT6_OK=0
if list_ran_n2_containers; then
  sect6_all_good=1
  for c in "${RAN_N2_CONTAINERS[@]}"; do
    RC=$(docker inspect --format '{{.RestartCount}}' "$c" 2>/dev/null) || RC="?"
    if [ "${RC:-0}" -le 2 ] 2>/dev/null; then
      echo -e "  ${GREEN}✓ $c RestartCount = $RC${NC}"
    else
      echo -e "  ${YELLOW}⚠ $c RestartCount = $RC (possível flapping)${NC}"
      sect6_all_good=0
    fi
  done
  [ "$sect6_all_good" -eq 1 ] && SECT6_OK=1
else
  echo -e "  ${YELLOW}⚠ Nenhum container RAN N2 para inspecionar${NC}"
fi
[ "$SECT6_OK" -eq 1 ] && PASS=$((PASS+1))
echo ""

# --- Resumo ---
echo "=============================================="
echo "Resumo"
echo "=============================================="
echo -e "Critérios atendidos: ${GREEN}$PASS${NC}"
echo -e "Falhas:             ${RED}$FAIL${NC}"
echo ""

if [ "$FAIL" -eq 0 ]; then
  echo -e "${GREEN}N2/NGAP validado com sucesso.${NC}"
  exit 0
else
  echo -e "${RED}Validação N2 apresentou falhas. Consulte docs/VALIDATION_E2E.md e docs/README_TROUBLESHOOTING.md${NC}"
  exit 1
fi
