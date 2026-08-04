# Fase 3 — loop fechado (emulação + atuação real)

Guia do ciclo completo:

```text
KPM E2 → SQLite/JSONL → MAD train/evaluate → policy A1
        → atuação (emulate | real) → KPM after → effect_report
```

SMO-lite (snapshot/eventos) corre em paralelo para correlação operacional.

## Dois modos de atuação

| Modo | O que faz | Evidência esperada |
|------|-----------|--------------------|
| `emulate` | `tc tbf` na interface `oaitun_ue*` | queda mensurável de `DRB.UEThpUl` sob carga UL |
| `real` | E2SM-RC **style 1 / action 2** (QoS flow mapping) | evento `real_control_sent` no audit; impacto KPM pode ser limitado (PoC OAI) |

**Proibido no gNB OAI deste lab:** E2SM-RC action 6 (PRB quota). O agente faz `assert` e pode abortar o `nr-softmodem`.

## Comandos

### Offline (sem stack)

```bash
./scripts/test_closed_loop_lab.sh
# ou
ACTUATION_MODE=emulate ./scripts/run_closed_loop_lab.sh --offline
```

### Live sobre Fase 2

Pré-requisito: `./scripts/up_oai_oran_lab.sh` e `./scripts/test_oran_ric.sh` OK, nrUE com `oaitun`, `iperf3` no host.

Fluxo live (fecha o loop A1→atuação):

```text
baseline calmo (KPM_TRAFFIC=0) → train MAD
  → stress auto (iperf UDP) + captura before → evaluate
  → [load-gate force-apply se MAD=observe sob carga]
  → A1 → atuar só se policy/apply → after → report → rollback
```

```bash
# Emulação controlada (recomendado para demonstrar efeito KPM)
ACTUATION_MODE=emulate ./scripts/run_closed_loop_lab.sh --live-fase2

# Atuação E2 real (action=2)
ACTUATION_MODE=real CLOSED_LOOP_ALLOW_REAL=1 \
  ./scripts/run_closed_loop_lab.sh --live-fase2

# Só gera intent CONTROL sem enviar
ACTUATION_MODE=real CLOSED_LOOP_REAL_DRY_RUN=1 \
  ./scripts/run_closed_loop_lab.sh --live-fase2
```

Opcional:
- `AI_POLICY_COMMIT=1` — envia a policy ao PMS (`:8081`)
- `CLOSED_LOOP_AUTO_STRESS=0` — não sobe iperf (tráfego externo)
- `CLOSED_LOOP_FORCE_LOAD=0` — não força apply sob carga se MAD=observe
- `CLOSED_LOOP_LOAD_UETHP_KBPS` / `CLOSED_LOOP_LOAD_PRB_PCT` — limiares do load-gate
- `CLOSED_LOOP_IPERF_PORT=5202` — porta do stress auto (padrão; não usa `:5201` do `test-vpp-throughput.sh`)

**Não rode em paralelo** `test-vpp-throughput.sh` e o closed loop com auto-stress antigo na mesma porta: um `pkill iperf3` no DN mata o servidor do outro (`iperf3: error - the server has terminated`). Com a porta `5202`, os dois podem coexistir.

## Artefatos por run

Diretório `logs/closed_loop_<run_id>/`:

| Arquivo | Conteúdo |
|---------|----------|
| `model.json` | baseline MAD |
| `decision.json` / `policy.json` | decisão + metadados `actuation` |
| `kpm_baseline.log` | janela calma (treino live) |
| `kpm_before.log` / `kpm_after.log` | janelas KPM pré/pós atuação |
| `kpm.sqlite` / `kpm.jsonl` | armazenamento |
| `actuator_events.jsonl` | audit apply/rollback/CONTROL |
| `effect_report.json` | deltas médios before→after |
| `iperf_stress.log` | stress UDP (se auto-stress) |
| `smo_snapshot/` | snapshot A1/E2/O1-sim |

## Componentes

| Artefato | Função |
|----------|--------|
| `config/ai-policy/closed_loop.json` | features + contrato de atuação |
| `scripts/ai_policy_pipeline.py` | train/evaluate/apply/force-apply (+ `actuation`) |
| `scripts/kpm_store.py` | ingest phases `before`/`after` |
| `scripts/capture_kpm_fase2.sh` | captura xApp OAI por N segundos |
| `scripts/closed_loop_actuator.py` | emulate/real/report/rollback |
| `vendor/.../policy_actuator_xapp.py` | envia CONTROL RC action=2 |
| `scripts/run_closed_loop_lab.sh` | orquestração ponta a ponta |
| `scripts/test_closed_loop_lab.sh` | validação automatizada |

## O que não afirmar

- O1/NETCONF real no gNB OAI monolítico
- PRB quota / slice scheduling via E2 neste binário
- LSTM/DNN do artigo SUTD (aqui: MAD auditável)
- Que `AI_POLICY_COMMIT=1` sozinho mova a rádio — só fecha o loop com o atuador

## Critérios de aceite

1. Unittests verdes (`tests/test_closed_loop.py`).
2. Offline: `effect_report.json` e `actuator_events.jsonl` gerados.
3. Emulate live: delta de `DRB.UEThpUl` coerente com rate-limit sob iperf/ping UL.
4. Real live: audit contém `real_control_intent` / `real_control_sent`; gNB não aborta.
