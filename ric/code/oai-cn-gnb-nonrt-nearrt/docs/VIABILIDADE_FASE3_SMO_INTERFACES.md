# Viabilidade - Fase 3 SMO e interfaces abertas

Este documento avalia a viabilidade da Fase 3 no estado atual do lab e define a
solucao implementada para evoluir sem prejudicar as Fases 1 e 2.

## Conclusao executiva

A Fase 3 e viavel como uma camada de integracao SMO-lite local para correlacionar
OAM/O1 simulado, VES, A1, E2/KPM e inventario O2 local. Essa camada ja permite
demonstrar fluxo operacional e preparar closed loop.

Um SMO/OAM completo O-RAN SC tambem e viavel, mas deve ser tratado como modo
externo: exige checkout separado, muitas imagens, mais memoria e revisao de
portas. O gNB OAI monolitico do lab nao expoe O1 NETCONF nativo; por isso O1
realista no lab deve ser feito com simuladores O-DU/O-RU.

## Matriz de viabilidade

| Interface | Viabilidade agora | Como foi implementada | Limitacao principal |
|-----------|-------------------|-----------------------|---------------------|
| A1 | Alta | coleta do PMS nonRT e A1 Mediator da Fase 2 | closed loop exige rApp/xApp consumidor de policy |
| E2 | Alta | RNIB/e2mgr e KPM via nearRT-RIC O-RAN SC | depende da estabilidade do gNB OAI E2 Agent |
| O1 | Media | topologia e eventos simulados para O-DU/O-RU | gNB OAI monolitico nao tem O1 NETCONF nativo |
| O2 | Media | inventario Docker/host do lab | nao e O2 IMS real |
| VES | Media | eventos JSONL timestampados e correlacionaveis | collector VES real fica no modo externo |
| TEIV/topologia | Baixa a media | topologia local em JSON | TEIV real depende do SMO/OAM externo |

## Solucao criada

Foram definidos dois modos.

| Modo | Objetivo | Comando |
|------|----------|---------|
| local | SMO-lite leve, sem containers novos | `./scripts/up_smo_lab.sh` |
| external | O-RAN SC OAM/SMO completo em checkout externo | `SMO_MODE=external SMO_OAM_DIR=/path ./scripts/up_smo_lab.sh` |

O modo local adiciona:

- topologia SMO/OAM em `config/smo/topology.lab.json`;
- eventos OAM/VES simulados em `logs/smo_lab_events.jsonl`;
- snapshots A1/E2/O1/O2/VES em `logs/smo_lab_<timestamp>/`;
- teste reprodutivel com `./scripts/test_smo_lab.sh`;
- coexistencia segura com Fase 2 em execucao.

## Arquitetura operacional recomendada

```text
SMO-lite local
  |-- O1 simulado: topology.lab.json + eventos OAM/VES
  |-- A1: nonRT PMS -> A1 Mediator
  |-- E2: nearRT-RIC -> RNIB/e2mgr/xApps/KPM
  |-- O2: inventario Docker/host
  `-- Evidencias: snapshots por timestamp

Fase 2
  |-- nonRT-RIC
  |-- O-RAN SC nearRT-RIC
  |-- gNB OAI + nrUE
  `-- xApps KPM
```

## Como usar na pratica

1. Suba e valide a Fase 2.

```bash
./scripts/up_oai_oran_lab.sh
./scripts/test_oran_ric.sh
```

2. Inicie a Fase 3 local.

```bash
./scripts/up_smo_lab.sh
```

3. Abra um xApp KPM.

```bash
KPM_TRAFFIC=1 ./scripts/run_xapp_oai_kpm_extended.sh
```

4. Registre um evento OAM/VES simulado no inicio do teste.

```bash
./scripts/smo_lab_event.sh MAJOR sim_o_du_001 HighPrbUl "stress UL iniciado"
```

5. Execute trafego UE.

```bash
UE_SOURCE=nrue ./scripts/test-vpp-throughput.sh
```

6. Colete o snapshot.

```bash
./scripts/smo_lab_snapshot.sh
```

## O que a Fase 3 permite demonstrar

- correlacao temporal entre evento OAM e degradacao/melhoria KPM;
- visao de topologia/inventario para explicar onde esta o impacto;
- leitura de estado A1 e E2 junto do mesmo experimento;
- base para rApp que transforme evento + KPM em policy A1;
- base para xApp que leia policy e atue via E2.

## Caminho para rede real

Para aproximar de rede real, a ordem recomendada e:

1. Substituir eventos JSONL por VES Collector real no modo externo.
2. Substituir topologia JSON por TEIV/SDNC com simuladores NTSIM.
3. Integrar rApp ao PMS nonRT para criar policies A1.
4. Criar xApp policy-aware para consumir a policy e agir em E2.
5. Medir antes/depois em `DRB.UEThp*`, `DRB.RlcSduDelayDl` e `RRU.PrbTot*`.

Essa evolucao preserva a Fase 2 porque o modo local nao altera containers,
rotas, portas nem processos do RAN/RIC.
