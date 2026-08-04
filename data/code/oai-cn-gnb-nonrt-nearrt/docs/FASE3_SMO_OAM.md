# Fase 3 - SMO/OAM e topologia completa

Guia de interpretacao associado:
[INTERPRETACAO_FASE3_SMO_OAM.md](INTERPRETACAO_FASE3_SMO_OAM.md).

Analise de viabilidade:
[VIABILIDADE_FASE3_SMO_INTERFACES.md](VIABILIDADE_FASE3_SMO_INTERFACES.md).

## Objetivo

A Fase 3 inicia o plano de gestao O-RAN: SMO/OAM, O1 com simuladores,
inventario/topologia e, opcionalmente, integracao com nonRT/nearRT ja validados.
Ela nao substitui Fase 1 ou Fase 2; e uma camada adicional e isolada.

## Estado no projeto

| Item | Estado |
|------|--------|
| Documentacao de arquitetura | Implementada neste guia |
| Scripts `up/down/test_smo_lab.sh` | Implementados com modo local e externo |
| SMO-lite local | Implementado |
| Compose SMO completo embutido no repo | Nao incluído |
| O1 real para gNB OAI | Nao suportado pelo gNB monolitico |
| O1 via simuladores O-DU/O-RU | Caminho recomendado |
| Snapshot A1/E2/O1/O2/VES | Implementado |
| Treino de baseline KPM | Implementado (rApp experimental) |
| Inferencia e policy A1 em dry-run | Implementado |
| Aplicacao no PMS | Implementada, opt-in com `--commit` |
| Efeito A1 -> atuador (emulate / E2 RC action=2) | Implementado — ver [FASE3_CLOSED_LOOP.md](FASE3_CLOSED_LOOP.md) |

Existem dois modos:

| Modo | Uso | Custo |
|------|-----|-------|
| `SMO_MODE=local` | SMO-lite incluido no repo, snapshots e eventos simulados | leve |
| `SMO_MODE=external` | checkout externo O-RAN SC OAM/SMO via `SMO_OAM_DIR` | pesado |

O modo local e o padrao porque permite explorar as interfaces abertas sem baixar
dezenas de imagens ou colidir com a Fase 2.

## Conceitos

| Conceito | Papel |
|----------|-------|
| SMO | Service Management and Orchestration; plano de gestao superior |
| OAM | Operacao, administracao e manutencao |
| O1 | Interface de gestao entre SMO e RAN/nearRT, tipicamente NETCONF/HTTP |
| SDNC | Controller usado no OAM para configuracao/NETCONF |
| VES Collector | Recebe eventos/telemetria VES |
| Keycloak | Identidade/autenticacao para componentes SMO |
| Kafka/Zookeeper | Barramento/eventos e dependencias comuns |
| TEIV | Topology and Inventory; inventario/topologia |
| NTSIM/ntsim-ng | Simuladores O-RU/O-DU para O1 quando nao ha equipamento real |

## Arquitetura alvo

```text
                         Fase 3 - management plane

  SMO/OAM ou SMO-lite
  +-------------------------------------------------------------+
  | local: snapshots + eventos VES simulados + inventario        |
  | external: Keycloak/Kafka/SDNC/VES/TEIV O-RAN SC OAM          |
  +----------------------------+--------------------------------+
                               |
                               v O1 / VES / topology / O2 local
  Simuladores O1 / inventario
  +-------------------------------------------------------------+
  | ntsim-ng O-DU / O-RU / topology sources                     |
  +-------------------------------------------------------------+

  Planos ja existentes
  +-------------------------------------------------------------+
  | Fase 1: nonRT + FlexRIC, ou Fase 2: nonRT + O-RAN SC nearRT |
  | Core OAI + gNB/nrUE + xApps/KPM                             |
  +-------------------------------------------------------------+
```

## Interfaces abertas exploradas

| Interface | Implementacao no lab | Artefatos |
|-----------|----------------------|-----------|
| O1 | simulado por `config/smo/topology.lab.json` e eventos OAM | `topology.lab.json`, `oam_events.jsonl` |
| A1 | nonRT PMS e A1 Mediator da Fase 2 | `a1_pms_*.json`, `a1_mediator_*.txt/json` |
| E2 | RNIB Redis/e2mgr e xApps KPM da Fase 2 | `e2_node_id.txt`, `e2_rnib_keys.txt`, `e2mgr_e2t_list.json` |
| O2 | inventario Docker/host do lab | `o2_docker_inventory.txt` |
| VES | eventos simulados timestampados | `logs/smo_lab_events.jsonl` |

## Politica de isolamento

No modo local, `up_smo_lab.sh` nao sobe containers e nao bloqueia Fase 1/Fase
2. Esse e o modo recomendado para correlacionar Fase 3 com KPM/A1/E2 ja em
execucao.

No modo externo, `up_smo_lab.sh` aborta se detectar containers/processos de
Fase 1 ou Fase 2 ativos. Isso e conservador: SMO completo costuma usar portas
comuns como `8080`, `8181`, `8443`, `9092` e pode colidir com nonRT/nearRT.

Para permitir execucao compartilhada:

```bash
SMO_MODE=external SMO_ALLOW_SHARED_HOST=1 ./scripts/up_smo_lab.sh
```

Use isso apenas depois de revisar portas no compose externo.

## Modo local - SMO-lite

Subir:

```bash
./scripts/up_smo_lab.sh
```

Registrar um evento OAM/VES simulado:

```bash
./scripts/smo_lab_event.sh MAJOR sim_o_du_001 HighPrbUl "UL PRB acima do limiar"
```

Coletar snapshot das interfaces abertas:

```bash
./scripts/smo_lab_snapshot.sh
```

Testar:

```bash
./scripts/test_smo_lab.sh
```

Parar:

```bash
./scripts/down_smo_lab.sh
```

O snapshot cria uma pasta `logs/smo_lab_<timestamp>/` com:

| Arquivo | Conteudo |
|---------|----------|
| `summary.txt` | resumo operacional |
| `topology.lab.json` | topologia O1 simulada |
| `a1_pms_rics.json` | RICs vistos pelo nonRT PMS |
| `a1_mediator_health.txt` | health do A1 Mediator |
| `e2_node_id.txt` | E2 node ID do gNB registrado |
| `e2_rnib_keys.txt` | chaves RNIB Redis |
| `e2mgr_e2t_list.json` | associacao e2mgr/e2term |
| `o2_docker_inventory.txt` | inventario local de containers |
| `oam_events.jsonl` | eventos OAM/VES simulados |

## Modo externo - O-RAN SC OAM

Use quando houver recursos de maquina e um checkout O-RAN SC OAM/SMO.

1. Obtenha um checkout O-RAN SC OAM/SMO fora deste repositório.
2. Exporte o path:

```bash
export SMO_OAM_DIR=/path/para/o-ran-sc-oam
```

3. Revise os compose files esperados:

```bash
ls "$SMO_OAM_DIR"/infra/docker-compose.yaml
ls "$SMO_OAM_DIR"/smo/common/docker-compose.yaml
ls "$SMO_OAM_DIR"/smo/oam/docker-compose.yaml
```

4. Rode preflight:

```bash
./scripts/test_smo_lab.sh --preflight
```

## Comandos

Subir common + OAM:

```bash
SMO_MODE=external SMO_OAM_DIR=/path/para/o-ran-sc-oam ./scripts/up_smo_lab.sh
```

Subir tambem simuladores de rede/O1, se o checkout tiver `network/docker-compose.yaml`:

```bash
SMO_MODE=external SMO_WITH_NETWORK=1 SMO_OAM_DIR=/path/para/o-ran-sc-oam ./scripts/up_smo_lab.sh
```

Subir TEIV, se o checkout tiver `smo/teiv/docker-compose.yaml`:

```bash
SMO_MODE=external SMO_WITH_TEIV=1 SMO_OAM_DIR=/path/para/o-ran-sc-oam ./scripts/up_smo_lab.sh
```

Testar:

```bash
SMO_MODE=external SMO_OAM_DIR=/path/para/o-ran-sc-oam ./scripts/test_smo_lab.sh
```

Parar:

```bash
SMO_MODE=external SMO_OAM_DIR=/path/para/o-ran-sc-oam ./scripts/down_smo_lab.sh
```

## O que verificar

| Verificacao | Sinal esperado |
|-------------|----------------|
| containers common | Kafka/Zookeeper/Keycloak ativos |
| OAM | SDNC e VES collector ativos |
| O1 simulado | containers NTSIM/O-DU/O-RU ativos |
| VES | endpoint HTTP/HTTPS respondendo |
| topologia | TEIV ou inventario com entidades simuladas |
| isolamento | Fase 1/2 nao parada nem alterada automaticamente |

## Cenario de demonstracao recomendado

1. Suba a Fase 2 e valide E2/A1:

```bash
./scripts/up_oai_oran_lab.sh
./scripts/test_oran_ric.sh
```

2. Inicie SMO-lite:

```bash
./scripts/up_smo_lab.sh
```

3. Gere baseline KPM em um terminal:

```bash
KPM_TRAFFIC=1 ./scripts/run_xapp_oai_kpm_extended.sh
```

4. Registre um evento OAM simulado:

```bash
./scripts/smo_lab_event.sh MAJOR sim_o_du_001 HighPrbUl "stress UL iniciado"
```

5. Rode stress/throughput:

```bash
UE_SOURCE=nrue ./scripts/test-vpp-throughput.sh
```

6. Colete snapshot:

```bash
./scripts/smo_lab_snapshot.sh
```

7. Correlacione timestamps de `oam_events.jsonl`, KPM do xApp e inventario A1/E2.

## Relacao com KPM, rApps e xApps

Fase 3 nao substitui xApps/KPM. Ela observa/gerencia o dominio por OAM/O1,
enquanto:

- KPM/E2 continua sendo observado por xApps da Fase 1 ou Fase 2;
- policies A1 continuam vindo do nonRT;
- O1 traz inventario, configuracao e eventos de gestao;
- closed loop completo exige uma ponte de decisao: rApp/policy -> A1 -> xApp -> E2.

KPMs que continuam relevantes ao correlacionar eventos SMO/OAM com trafego UE:

| KPM | Unidade | Interpretacao na Fase 3 |
|-----|---------|--------------------------|
| `DRB.UEThpDl` / `DRB.UEThpUl` | `kbps` | throughput percebido pelo UE durante eventos ou mudancas de gestao |
| `DRB.PdcpSduVolumeDL` / `DRB.PdcpSduVolumeUL` | `Mb` | volume de dados por DRB na janela KPM |
| `DRB.RlcSduDelayDl` | `us` | atraso RLC que pode ser comparado com eventos O1/VES |
| `RRU.PrbTotDl` / `RRU.PrbTotUl` | `%` | ocupacao de recursos de radio durante carga ou degradacao |

## Limites atuais

- O gNB OAI monolitico usado neste lab nao expoe O1 NETCONF nativo.
- O1 deve ser demonstrado com simuladores O-DU/O-RU.
- O SMO full pode exigir 24-32 GB RAM e muitas imagens externas.
- O scaffold nao clona repositorios nem baixa imagens por conta propria.

## Proximos passos de implementacao

1. Escolher release O-RAN SC OAM/SMO e fixar commit para modo externo.
2. Adicionar simulador NTSIM real como camada opcional.
3. Incorporar `smo_lab_events.jsonl` como feature contextual do rApp.
4. Publicar um policy type A1 próprio além do type `1` de laboratório.
5. Evoluir o atuador real quando o gNB OAI suportar mais CONTROL actions sem assert
   (hoje: action 2; emulate cobre efeito KPM mensurável).

## Fluxo de IA e A1

O rApp experimental da fase 3 treina um baseline robusto com logs KPM, avalia
uma janela de operação e gera uma policy candidata. O envio ao PMS é opt-in:

```bash
./scripts/run_ai_policy_lab.sh                    # treino, inferencia e dry-run
AI_POLICY_COMMIT=1 ./scripts/run_ai_policy_lab.sh # envia ao PMS
```

Detalhes de arquitetura, contrato A1, segurança e validação:
[FASE3_IA_A1.md](FASE3_IA_A1.md).
