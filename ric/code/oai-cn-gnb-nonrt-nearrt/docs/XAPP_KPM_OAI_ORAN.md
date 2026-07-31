# xApp KPM — gNB OAI + nearRT O-RAN SC (Fase 2)

Guia prático para **subscrever métricas KPM**, **correr o xApp** e **interpretar as INDICATIONs** no laboratório `oai-cn-gnb-nonrt-nearrt`.

> Contexto geral da Fase 2: [ORAN_RIC_FASE2.md](ORAN_RIC_FASE2.md)

---

## O que este fluxo faz

```text
xApp (simple_xapp_oai.py)
    │ REST  → ric_submgr (subscrição KPM Style 4)
    │ RMR   ← ric_e2term (RIC_INDICATION, porta 4562)
    ▼
gNB OAI (nr-softmodem-oran-sc, E2 :36422, E2SM-KPM v2.03)
    ▲ SCTP
ric_e2term (:36422 host → 10.0.2.10 na rede Docker)
```

O xApp pede ao **Subscription Manager** uma subscrição **E2SM-KPM Report Style 4** (Format 4) com filtro **S-NSSAI** compatível com o agente E2 da OAI. O gNB envia **RIC INDICATIONs** periódicas (~1 s) com métricas por UE.

---

## Pré-requisitos

| Item | Verificação |
|------|-------------|
| Core OAI | `./scripts/up_core.sh` (interface `demo-oai` com `192.168.70.129`) |
| nearRT O-RAN SC | `docker ps` mostra `ric_e2term`, `ric_submgr`, `python_xapp_runner` |
| gNB compilado | `build-oran-sc/nr-softmodem-oran-sc` existe (`./scripts/build_e2_oran_sc.sh`) |
| **Sem FlexRIC** | Não correr Fase 1 (`nearRT-RIC` :36421) em paralelo |

**Não usar** `simple_mon_xapp.py` com o gNB OAI — esse xApp usa KPM Style 1, que o agente OAI **não implementa** (o gNB aborta na subscrição).

---

## Sequência de arranque (recomendada)

```bash
cd code/oai-cn-gnb-nonrt-nearrt

# 1) Lab completo (Core + nearRT + nonRT perfil oran + gNB + UE)
./scripts/up_oai_oran_lab.sh

# OU passo a passo:
# ./scripts/up_core.sh
# ./scripts/up_oran_ric.sh
# ./scripts/up_gnb_oai_oran.sh

# 2) Validar E2 e RNIB (deve terminar em ~30 s)
./scripts/test_oran_ric.sh

# 3) Obter E2 Node ID (necessário para o xApp)
./scripts/get_oran_e2_node_id.sh
# Exemplo: gnb_208_095_00000e00
```

Confirmações mínimas antes do xApp:

```bash
# E2 SETUP no gNB
grep -iE 'E2 SETUP' logs/gnb_oai_oran.log | tail -3

# Associação no e2mgr
docker exec ric_e2mgr curl -s http://localhost:3800/v1/e2t/list
# Deve conter: "ranNames":["gnb_208_095_00000e00"]

# PDU session / túnel UE
grep -iE 'PDU Session|oaitun' logs/ue_oai_oran.log | tail -5
ip -4 addr show oaitun_ue1   # IP típico: 12.1.1.x
```

---

## Correr o xApp KPM (forma recomendada)

```bash
# Com tráfego UE automático (ping → Core, melhora UEThp)
KPM_TRAFFIC=1 ./scripts/run_xapp_oai_kpm.sh

# E2 Node ID explícito (se necessário)
./scripts/run_xapp_oai_kpm.sh gnb_208_095_00000e00
```

### Variáveis úteis

| Variável | Padrão | Descrição |
|----------|--------|-----------|
| `KPM_TRAFFIC` | `1` | `ping` contínuo UE→DN durante o xApp |
| `OAI_DN_IP` | `192.168.73.135` | Destino do ping (Data Network do Core) |
| `XAPP_HTTP_PORT` | `8093` | Porta HTTP do callback de subscrição |
| `XAPP_RMR_PORT` | `4562` | Porta RMR para `RIC_INDICATION` |
| `XAPP_METRICS` | `DRB.UEThpDl,DRB.UEThpUl` | Métricas KPM |

### Parar o xApp

- **Ctrl+C** no terminal onde o xApp corre.
- Se aparecer `Address already in use` ao reiniciar:

```bash
./scripts/stop_xapp_oai_kpm.sh
./scripts/run_xapp_oai_kpm.sh
```

O script `stop_xapp_oai_kpm.sh` mata processos xApp órfãos dentro do container `python_xapp_runner` (comum após `docker compose exec` sem TTY).

---

## Comando manual (equivalente)

```bash
./scripts/stop_xapp_oai_kpm.sh

docker compose -f vendor/oran-sc-ric/docker-compose.yml \
  -f config/oran-ric/docker-compose.override.yml \
  --env-file vendor/oran-sc-ric/.env --env-file config/oran-ric/.env \
  exec -e PYTHONUNBUFFERED=1 python_xapp_runner \
  python3 ./simple_xapp_oai.py \
  --e2_node_id=gnb_208_095_00000e00 \
  --http_server_port=8093 \
  --rmr_port=4562 \
  --metrics=DRB.UEThpDl,DRB.UEThpUl \
  --sst=222 --sd=123
```

Parâmetros OAI-specific:

- `--sst=222 --sd=123` — alinhado ao `gnb.conf` e AMF do Core.
- Style 4 + S-NSSAI — único matching suportado pelo agente E2 OAI.

---

## Tráfego UE (métricas > 0)

`DRB.UEThpDl` / `DRB.UEThpUl` medem **throughput RLC na DRB** em **kbps** (delta de bytes no `granulPeriod` de 1 s). Sem tráfego IP na PDU session, os valores ficam em **0**.

### IP da UE (dinâmico)

O IP **não é fixo** (`12.1.1.10`, `12.1.1.11`, …). Usa sempre a interface:

```bash
ip -4 addr show oaitun_ue1 | grep inet
```

### Gerar tráfego manualmente (outro terminal)

```bash
# Preferir interface (não hardcodar IP antigo)
ping -I oaitun_ue1 -i 0.2 192.168.73.135
```

Erro `Cannot assign requested address` → o IP usado em `-I` já não existe; usa `oaitun_ue1` ou consulta o IP atual.

---

## Como verificar a saída do xApp

### 1. Subscrição bem-sucedida

```text
Subscribe OAI KPM Style 4: node=gnb_208_095_00000e00, metrics=['DRB.UEThpDl', 'DRB.UEThpUl'], S-NSSAI=222/123
Successfully subscribed with Subscription ID:  3Ex...
Received Subscription ID to E2EventInstanceId mapping: 3Ex... -> 1
```

### 2. INDICATIONs periódicas (~1 s)

```text
RIC Indication from gnb_208_095_00000e00 (sub 1)
  collectStartTime: 2026-06-10 18:48:25 UTC
  UE_id: 10
    granulPeriod: 1000
    DRB.UEThpDl: 3.720 kbps
    DRB.UEThpUl: 3.720 kbps
```

| Campo | Significado |
|-------|-------------|
| `collectStartTime` | Início da janela de medição (UTC, E2SM-KPM v2.03 = 4 bytes Unix s) |
| `UE_id` | Identificador E2SM da UE (pode mudar após reattach) |
| `granulPeriod` | Intervalo de agregação em ms (1000 = 1 s) |
| `DRB.UEThpDl/Ul` | Throughput instantâneo na DRB, **kbps** |

O `collectStartTime` deve avançar ~1 s entre INDICATIONs consecutivas.

### 3. Teste automatizado curto (~15 s)

```bash
./scripts/test_oran_ric.sh --run-xapp
```

Usa `simple_xapp_oai.py` com timeout; útil para smoke test, não para monitorização contínua.

---

## Verificações no stack (sem o xApp)

### E2 e RNIB

```bash
./scripts/test_oran_ric.sh

docker exec ric_dbaas redis-cli INFO server | grep redis_version
# Esperado: 5.0.9 (ver fix RNIB em ORAN_RIC_FASE2.md)

docker exec ric_dbaas redis-cli KEYS '{e2Manager},RAN:gnb_*'
docker exec ric_e2mgr curl -s http://localhost:3800/v1/e2t/list
```

### Subscrições activas no submgr

```bash
docker exec python_xapp_runner curl -s http://10.0.2.13:8088/ric/v1/subscriptions
```

### Logs úteis

```bash
# gNB — subscrição KPM e condição S-NSSAI
grep -iE 'SUBSCRIPTION|NSSAI|KPM' logs/gnb_oai_oran.log | tail -20

# submgr — erros de E2 desconectado
docker logs ric_submgr 2>&1 | tail -15
```

---

## Problemas frequentes

| Sintoma | Causa provável | Acção |
|---------|----------------|-------|
| `Address already in use` | xApp anterior no container | `./scripts/stop_xapp_oai_kpm.sh` |
| `503` / `No E2 connection` | gNB parado ou E2 desassociado | `./scripts/up_gnb_oai_oran.sh` + `sleep 15` |
| gNB aborta na subscrição | xApp Style 1 (`simple_mon_xapp`) | Usar `simple_xapp_oai.py` |
| `vendorName` / decode error | Incompatibilidade header v2/v4 | Já corrigido em `e2sm_kpm_module.py` |
| UEThp sempre 0 | Sem tráfego IP na DRB | `KPM_TRAFFIC=1` ou `ping -I oaitun_ue1 ...` |
| `bind: Cannot assign requested address` | IP UE mudou | `ip -4 addr show oaitun_ue1` |
| `collectStartTime` anos errados | TimeStamp 4 B lido como 8 B | Corrigido (`parse_kpm_timestamp`) |
| `e2t list` vazio após fix RNIB | Precisa reiniciar gNB | `./scripts/fix_oran_ric_rnib.sh` + `up_gnb_oai_oran.sh` |

### Recuperação rápida

```bash
./scripts/stop_xapp_oai_kpm.sh
./scripts/down_gnb_oai.sh
./scripts/up_gnb_oai_oran.sh
sleep 15
./scripts/test_oran_ric.sh
KPM_TRAFFIC=1 ./scripts/run_xapp_oai_kpm.sh
```

---

## Ficheiros e scripts relevantes

| Path | Função |
|------|--------|
| `scripts/run_xapp_oai_kpm.sh` | Arranque do xApp + tráfego opcional |
| `scripts/stop_xapp_oai_kpm.sh` | Libertar portas HTTP/RMR |
| `scripts/get_oran_e2_node_id.sh` | E2 Node ID no RNIB |
| `scripts/test_oran_ric.sh` | Health check Fase 2 (`--run-xapp`) |
| `vendor/oran-sc-ric/xApps/python/simple_xapp_oai.py` | xApp KPM para OAI |
| `vendor/oran-sc-ric/xApps/python/lib/e2sm_kpm_module.py` | Decode KPM v2.03 + timestamp |
| `config/oran-ric/.env` | `ORAN_E2_ADDR`, `DBAAS_VER` |
| `logs/gnb_oai_oran.log` | E2 SETUP, subscrições KPM |
| `logs/ue_oai_oran.log` | PDU session, `oaitun_ue*` |

---

## Parar o laboratório

```bash
# Ctrl+C no xApp, depois:
./scripts/stop_xapp_oai_kpm.sh
./scripts/down_oai_oran_lab.sh
```

---

## Referências

- [ORAN_RIC_FASE2.md](ORAN_RIC_FASE2.md) — arquitectura nearRT, RNIB, A1
- [oran-sc-ric README](../vendor/oran-sc-ric/README.md) — xApps upstream (srsRAN)
- OAI KPM: `openairinterface5g/openair2/E2AP/RAN_FUNCTION/O-RAN/ran_func_kpm_subs.c`
