# Interpretacao - Fase 2 O-RAN SC + A1

Este guia explica como interpretar a Fase 2, em que o FlexRIC e substituído por
nearRT O-RAN SC e o nonRT passa a apontar para A1 Mediator real. Ele complementa
[FASE2_ORAN_SC_A1.md](FASE2_ORAN_SC_A1.md).

## Pergunta que a Fase 2 responde

A Fase 2 responde:

> Consigo registrar o gNB OAI em um nearRT O-RAN SC, rodar xApps e expor A1 real
> para o nonRT PMS?

Ela começa a responder:

> Como uma policy nonRT poderia chegar ao nearRT?

Mas ainda pode não fechar:

> A policy foi consumida por um xApp e transformada em controle E2 efetivo?

Esse último passo depende do xApp consumir A1/RMR e agir sobre E2.

## Evidências principais

| Evidência | Onde ver | Interpretação |
|-----------|----------|---------------|
| `ric_e2term` ativo | `docker ps` | terminação E2 O-RAN SC está de pé |
| `PORT = 36422` no gNB | `logs/gnb_oai_oran.log` | gNB usa build correto para O-RAN SC |
| chave RNIB `gnb_*` | Redis `ric_dbaas` | nearRT registrou o E2 node |
| `get_oran_e2_node_id.sh` retorna ID | script | xApps tem node alvo |
| A1 healthcheck responde | `curl :10000/a1-p/healthcheck` | A1 Mediator está operacional |
| PMS lista RIC em perfil oran | `/a1-policy/v2/rics` | nonRT enxerga nearRT/A1 endpoint configurado |
| xApp KPM recebe indication | log do xApp | caminho E2 subscription -> indication funciona |

## Como interpretar E2

Sinais fortes de E2 saudável:

```bash
grep -iE 'E2|RIC|setup|PORT = 36422' logs/gnb_oai_oran.log | tail -40
docker exec ric_dbaas redis-cli KEYS '{e2Manager},RAN:gnb_*'
./scripts/get_oran_e2_node_id.sh
```

Interpretação:

- `PORT = 36422`: você está no perfil O-RAN SC, não no FlexRIC;
- RNIB com `gnb_...`: E2 Manager aceitou o gNB;
- sem RNIB: verificar `ric_e2term`, `ric_e2mgr`, SCTP e timeout de reconnect.

## Como interpretar A1

Verificações:

```bash
curl -s http://127.0.0.1:10000/a1-p/healthcheck
curl -s http://127.0.0.1:10000/a1-p/policytypes/
curl -s http://127.0.0.1:8081/a1-policy/v2/rics
```

Leitura:

| Resultado | Interpretação |
|-----------|---------------|
| A1 health OK | A1 Mediator esta vivo |
| PMS lista RIC | nonRT consegue descobrir endpoint nearRT |
| policy types vazios | normal se nenhum xApp registrou tipo de policy |
| PMS OK, mas A1 vazio | caminho nonRT existe, mas ainda não há app/policy end-to-end |

## KPMs e leitura pratica

| KPM | Unidade | Se muda sob carga | Aplicação real |
|-----|---------|-------------------|----------------|
| `DRB.UEThpDl` | `kbps` | tráfego DL efetivo no UE | SLA de throughput e expêriencia |
| `DRB.UEThpUl` | `kbps` | tráfego UL efetivo no UE | uplink para vídeo/sensores |
| `DRB.PdcpSduVolumeDL` | `Mb` | volume DL na janela | consumo por slice/UE |
| `DRB.PdcpSduVolumeUL` | `Mb` | volume UL na janela | upload intenso e anomalias |
| `DRB.RlcSduDelayDl` | `us` | atraso de camada RLC | degradação de rádio/filas |
| `RRU.PrbTotDl` | `%` | ocupação DL de recursos | capacidade e congestionamento |
| `RRU.PrbTotUl` | `%` | ocupação UL de recursos | saturacao UL |

Observação para o OAI deste lab: `RRU.PrbTotDl/Ul` são definidos como
percentual, portanto o intervalo físico esperado é 0-100. Valores acima de 100
devem ser tratados como artefato do provedor KPM/contador do OAI, especialmente
no primeiro sample após uma nova subscription ou durante carga UL intensa. Para
closed loop, aplique sanity check ou limite o valor a 100 antes de tomar decisão.

## Padrões esperados

### E2 e xApp OK

- `test_oran_ric.sh` passa;
- `get_oran_e2_node_id.sh` retorna `gnb_...`;
- `run_xapp_oai_kpm.sh` mostra subscribe/indications;
- KPM aumenta quando há `KPM_TRAFFIC=1`.

Conclusão: nearRT O-RAN SC está pronto para xApps.

### xApp encerra e a RAN para

Se depois de `Ctrl+C` no xApp aparecerem estes sintomas:

- `Lost socket` em `logs/ue_oai_oran.log`;
- assertion `e2ap_dec_subscription_delete_request` em `logs/gnb_oai_oran.log`;
- `503 Service Unavailable` no xApp;
- `No E2 connection for ranName ...` em `docker logs ric_submgr`;

então o problema não é o tráfego KPM em si. O fluxo de saída enviou
`RIC Subscription Delete`, e esta combinação OAI + O-RAN SC do lab pode abortar
o `nr-softmodem-oran-sc` ao decodificar esse delete.

Interpretação prática: a subscription KPM funciona, mas o delete subscription é
instável neste binário. Para uso cotidiano do lab, o xApp OAI encerra sem enviar
unsubscribe por padrão. Isso preserva gNB/UE e evita a perda da interface
`oaitun_ue`.

Ação recomendada:

```bash
# uso normal, preserva a RAN no Ctrl+C
KPM_TRAFFIC=1 ./scripts/run_xapp_oai_kpm.sh

# somente para investigar o bug de delete subscription
XAPP_UNSUBSCRIBE_ON_EXIT=1 KPM_TRAFFIC=1 ./scripts/run_xapp_oai_kpm.sh
```

Se a sessão já caiu, recupere com:

```bash
./scripts/up_gnb_oai_oran.sh
./scripts/test_oran_ric.sh --run-xapp
```

Nos logs do xApp, use `receivedAt` como horário de observação do xApp. O
`kpmTimeDecoded` vem do cabeçalho E2SM-KPM `colletStartTime`; no OAI v2.03 deste
lab ele é decodificado a partir de 4 bytes Unix seconds em little-endian, com
fallback para big-endian em capturas de outros stacks.

### A1 OK, mas sem efeito no RAN

Esse padrão é comum:

- A1 Mediator responde;
- PMS consegue listar RIC;
- porém nenhuma mudança aparece nos KPMs.

Interpretação: ainda falta um xApp que consuma policy A1 e converta isso em
controle E2. A Fase 2 valida o caminho de infraestrutura; o closed loop depende
da aplicação.

### RNIB vazio

Possíveis causas:

- gNB não usa binário `nr-softmodem-oran-sc`;
- FlexRIC ainda está ativo;
- `ric_dbaas` com Redis incompatível;
- reconnect E2 ainda em timeout.

Ação:

```bash
./scripts/fix_oran_ric_rnib.sh
./scripts/down_gnb_oai.sh
sleep 65
./scripts/up_gnb_oai_oran.sh
```

## Como pensar em aplicação real

A Fase 2 é o primeiro desenho de uma stack O-RAN próxima de produção:

```text
rApp/nonRT -> policy A1 -> nearRT O-RAN SC -> xApp -> E2 -> gNB
```

Aplicações reais que fazem sentido:

- rApp de economia de energia publica policy de restrição/objetivo;
- xApp KPM observa `RRU.PrbTot*` e `DRB.UEThp*`;
- xApp RC aplica controle ou reconfiguração quando a policy permitir;
- PMS registra ciclo de vida da policy para auditoria.

O que medir antes/depois:

- KPM baseline versus após policy;
- latência até policy aparecer no nearRT;
- estabilidade do E2 node no RNIB;
- logs de xApp mostrando policy recebida e ação tomada.

## Critério de saída para avançar para Fase 3

Avance quando:

- Fase 2 sobe sem FlexRIC ativo;
- E2 node aparece no RNIB;
- xApp KPM recebe indications;
- A1 Mediator responde;
- PMS enxerga RIC em perfil `oran`;
- limitação de closed loop por xApp está documentada.
