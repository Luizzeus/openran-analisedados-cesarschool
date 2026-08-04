# Fases do lab O-RAN sobre OAI

Este documento e o indice operacional das tres fases do projeto
`oai-cn-gnb-nonrt-nearrt`. A ideia central e manter cenarios isolados: cada fase
tem comandos, portas, objetivos e limites claros, para que um experimento nao
quebre outro.

## Visao rapida

| Fase | Nome curto | Objetivo | nearRT | nonRT | SMO/OAM | Estado |
|------|------------|----------|--------|-------|---------|--------|
| 1 | nonRT + FlexRIC | Validar PMS/A1 simulados em paralelo ao E2 FlexRIC | FlexRIC `:36421` | PMS + A1 simulators | Nao | Implementada |
| 2 | O-RAN SC + A1 | Substituir FlexRIC por nearRT O-RAN SC e ligar A1 real | `oran-sc-ric` `:36422` | PMS -> A1 Mediator | Nao | Base implementada |
| 3 | SMO/OAM + IA | Gestao SMO-lite, rApp KPM→A1 e loop fechado (emulate/real) | Reusa Fase 2 | Reusa Fase 2; envio opt-in | SMO-lite local ou SMO OAM externo | Loop fechado implementado |

## Regras de isolamento

1. Fase 1 e Fase 2 nao devem rodar nearRT ao mesmo tempo.
2. Fase 3 local nao para nem altera Fase 1/Fase 2; o modo externo de SMO aborta
   se detectar stacks ativas, a menos que `SMO_ALLOW_SHARED_HOST=1` seja usado.
3. Builds da Fase 2 usam binario separado (`nr-softmodem-oran-sc`) para nao
   sobrescrever o build FlexRIC da Fase 1.
4. Logs e artefatos runtime ficam em `logs/` e seguem ignorados pelo git.

## Documentos por fase

| Documento | Conteudo |
|-----------|----------|
| [FASE1_NONRT_FLEXRIC.md](FASE1_NONRT_FLEXRIC.md) | Conceitos, arquitetura, comandos e validacao da Fase 1 |
| [FASE2_ORAN_SC_A1.md](FASE2_ORAN_SC_A1.md) | Conceitos, arquitetura, comandos e validacao da Fase 2 |
| [FASE3_SMO_OAM.md](FASE3_SMO_OAM.md) | Conceitos, arquitetura, comandos e execucao da Fase 3 |
| [FASE3_IA_A1.md](FASE3_IA_A1.md) | Treinamento, inferencia e aplicacao segura de policies A1 |
| [FASE3_CLOSED_LOOP.md](FASE3_CLOSED_LOOP.md) | Loop fechado: emulate (tc) e real (E2SM-RC action 2) |
| [CASO_USO_LOCAL_VIRTUALIZADO.md](CASO_USO_LOCAL_VIRTUALIZADO.md) | Qual rApp do artigo SUTD cabe no lab RFSIM |
| [EBPF_CRIU_DESIGN.md](EBPF_CRIU_DESIGN.md) | eBPF como trigger/observabilidade da migração CRIU |
| [SYNC_REPOS.md](SYNC_REPOS.md) | Qual clone e canónico e como sincronizar |
| [INTERPRETACAO_FASE1_NONRT_FLEXRIC.md](INTERPRETACAO_FASE1_NONRT_FLEXRIC.md) | Como interpretar resultados e pensar aplicacao real da Fase 1 |
| [INTERPRETACAO_FASE2_ORAN_SC_A1.md](INTERPRETACAO_FASE2_ORAN_SC_A1.md) | Como interpretar resultados e pensar aplicacao real da Fase 2 |
| [INTERPRETACAO_FASE3_SMO_OAM.md](INTERPRETACAO_FASE3_SMO_OAM.md) | Como interpretar resultados e pensar aplicacao real da Fase 3 |
| [VIABILIDADE_FASE3_SMO_INTERFACES.md](VIABILIDADE_FASE3_SMO_INTERFACES.md) | Viabilidade das interfaces abertas e caminho para rede real |
| [PLANO_INTEGRACAO_NONRT_RIC_SMO.md](PLANO_INTEGRACAO_NONRT_RIC_SMO.md) | Plano geral e decisoes de integracao |

## Fluxos recomendados

### Fase 1

```bash
./scripts/up_e2_lab.sh
./scripts/test_nonrt_ric.sh --seed
./scripts/explore_e2_sm.sh quick
./scripts/stress_ue_observe_apps.sh
```

### Fase 2

```bash
./scripts/down_e2_lab.sh
./scripts/build_e2_oran_sc.sh
./scripts/up_oai_oran_lab.sh
./scripts/test_oran_ric.sh --run-xapp
```

### Fase 3

```bash
./scripts/up_smo_lab.sh
./scripts/smo_lab_event.sh MAJOR sim_o_du_001 HighPrbUl "stress UL iniciado"
./scripts/test_smo_lab.sh

# Loop fechado (emulate offline; live exige Fase 2)
./scripts/test_closed_loop_lab.sh
ACTUATION_MODE=emulate ./scripts/run_closed_loop_lab.sh --live-fase2
```

Detalhes: [FASE3_CLOSED_LOOP.md](FASE3_CLOSED_LOOP.md).

### Experimento IA (UE-TP / load-anomaly) — offline ou live

Caso de uso recomendado para lab local virtualizado:
[CASO_USO_LOCAL_VIRTUALIZADO.md](CASO_USO_LOCAL_VIRTUALIZADO.md).

```bash
# Offline (usa logs já capturados): coleta→SQLite/JSONL→treino→policy dry-run
./scripts/run_ue_tp_experiment.sh

# Live (requer lab E2 no ar): nova captura + mesmo pipeline
./scripts/run_ue_tp_experiment.sh --live

# Opcional: enviar policy ao PMS (Fase 2)
AI_POLICY_COMMIT=1 ./scripts/run_ue_tp_experiment.sh
```

Sincronização com outros clones do mesmo lab:
[SYNC_REPOS.md](SYNC_REPOS.md).

Modo externo O-RAN SC OAM:

```bash
SMO_MODE=external SMO_OAM_DIR=/path/para/o-ran-sc-oam ./scripts/test_smo_lab.sh --preflight
SMO_MODE=external SMO_OAM_DIR=/path/para/o-ran-sc-oam ./scripts/up_smo_lab.sh
```

## Como voltar a um estado conhecido

Fase 1:

```bash
./scripts/down_e2_lab.sh
./scripts/up_e2_lab.sh
```

Fase 2:

```bash
./scripts/down_oai_oran_lab.sh
./scripts/up_oai_oran_lab.sh
```

Fase 3:

```bash
./scripts/down_smo_lab.sh
```
