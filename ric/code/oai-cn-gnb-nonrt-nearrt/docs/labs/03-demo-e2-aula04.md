# Roteiro — Demo guiada E2 (Aula 04, Bloco 3)

**Disciplina:** RAN Intelligent Controller (RIC)  
**Encontro:** Aula 04 · **21:00–22:00** (após intervalo)  
**Código:** `ric/code/oai-cn-gnb-e2/`  
**Pré-requisito:** build concluído (`build_e2.sh` + `build_flexric_tools.sh`)

Guias de apoio: [E2_FLEXRIC.md](../../../E2_FLEXRIC.md) · [E2_SERVICE_MODELS.md](../../../E2_SERVICE_MODELS.md)

---

## Objetivos da demo

Ao final deste bloco, cada grupo deve ter:

1. Visto **E2 SETUP** gNB ↔ nearRT-RIC nos logs.
2. Executado pelo menos um teste **E2SM** (custom ou KPM).
3. Registrado **uma evidência** (trecho de log ou screenshot) para o Projeto 2.
4. Entendido onde sua entrega se encaixa no **ciclo de vida** do xApp (Deploy + Monitor).

---

## Checklist pré-demo (docente)

- [ ] Docker ativo; `docker ps` mostra `oai-amf`, `oai-smf`, …
- [ ] `flexric-lib/libkpm_sm.so` existe (8 bibliotecas após `sync_flexric_lib.sh`)
- [ ] Binários: `nr-softmodem`, `nearRT-RIC`, `xapp_kpm_moni`
- [ ] Interface `demo-oai` com IP `192.168.70.129/24` no host
- [ ] Nenhum `nearRT-RIC` / `nr-softmodem` órfão (`down_e2_lab.sh` antes)

---

## Roteiro minuto a minuto (~60 min)

### 0–5 min — Contexto

- Retomar arquitetura no quadro: Core → gNB (E2 agent) → FlexRIC → xApp.
- Mostrar slide **fluxo E2 no ciclo de vida** (SETUP → subscribe → INDICATION).
- Abrir terminal em `ric/code/oai-cn-gnb-e2`.

### 5–15 min — Subir o laboratório

```bash
cd ric/code/oai-cn-gnb-e2
./scripts/up_e2_lab.sh
```

**Verificar em paralelo (projetor):**

```bash
# Core
docker ps --format '{{.Names}}' | grep oai-

# E2 no gNB
grep -i 'E2 SETUP RESPONSE' logs/gnb_oai.log | tail -1

# RIC ativo
pgrep -a nearRT-RIC

# UE com PDU session
grep 'PDU Session Establishment Accept' logs/ue_oai.log | tail -1
```

**Pergunta à turma:** em qual fase do ciclo de vida estamos? (*Deploy*)

### 15–25 min — Teste custom (conectividade E2)

```bash
./scripts/test_e2_sm.sh cust
```

**Esperado no log** (`logs/xapp_cust_moni.log`):

- `Connected E2 nodes = 1`
- RAN function IDs: 2 (KPM), 3 (RC), 142–148 (MAC…GTP)

**Pergunta:** por que testamos `cust` antes de KPM O-RAN?

### 25–40 min — Teste E2SM-KPM (slice 222/123)

```bash
XAPP_DURATION=30 ./scripts/test_e2_kpm.sh
```

**Esperado:**

- `Successfully subscribed to RAN_FUNC_ID 2`
- Linhas `DRB.UEThpDl`, `RRU.PrbTotUl`, …
- Mensagem final: `KPM INDICATIONs recebidas.`

**Se falhar:**

| Sintoma | Ação rápida |
|---------|-------------|
| xApp trava em `Resending Setup Request` | `ls flexric-lib/libkpm_sm.so`; `./scripts/sync_flexric_lib.sh` |
| RIC crash no log | Reiniciar: `down_e2_lab.sh` + `up_e2_lab.sh` |
| Subscrição OK, sem métricas | `KPM_TRAFFIC=1`; aguardar attach UE |

**Pergunta:** qual E2SM e qual slice estamos filtrando?

### 40–50 min — Teste E2SM-RC (opcional / se houver tempo)

```bash
XAPP_DURATION=45 ./scripts/test_e2_rc_attach.sh
```

**Esperado:** `Successfully subscribed` + INDICATION com `rrcSetupComplete` ou estado RRC.

**Nota didática:** xApp RC pode dar timeout após 1ª INDICATION — evidência já está no log.

### 50–58 min — Encerramento e Projeto 2

- Mostrar estrutura de `logs/` para entrega.
- Indicar roteiros:
  - [02-oai-cn-gnb-flexric-e2.md](02-oai-cn-gnb-flexric-e2.md)
  - [04-projeto2-plano-testes.md](04-projeto2-plano-testes.md)
- Cada grupo anota: E2SM escolhido, comando de teste, arquivo de log de evidência.

### 58–60 min — Parar (opcional)

```bash
./scripts/down_e2_lab.sh        # mantém Core
# ./scripts/down_e2_lab.sh --all  # para tudo
```

---

## Evidências mínimas para registrar hoje

| Evidência | Arquivo / comando |
|-----------|-------------------|
| E2 SETUP | `grep -i 'E2 SETUP' logs/gnb_oai.log` |
| RAN functions | saída de `test_e2_sm.sh cust` |
| KPM subscription + métricas | `logs/xapp_kpm_lab.log` |
| (Opcional) RC | `logs/xapp_rc_attach.log` |

---

## Verificação automatizada (reprodução em casa)

```bash
./scripts/verify_e2_lab.sh        # cust + KPM
./scripts/verify_e2_lab.sh full   # + RC attach
```

---

## Referências

- [02-oai-cn-gnb-flexric-e2.md](02-oai-cn-gnb-flexric-e2.md) — roteiro Aulas 04–06
- [../E2_FLEXRIC.md](../E2_FLEXRIC.md) — índice de documentação
- Slides: `slides/aula04-xapps_opensource.md` (demo + resultados do lab)
