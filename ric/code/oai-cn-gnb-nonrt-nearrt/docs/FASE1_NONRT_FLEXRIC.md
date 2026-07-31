# Fase 1 - nonRT RIC isolado + nearRT FlexRIC

Guia de interpretacao associado:
[INTERPRETACAO_FASE1_NONRT_FLEXRIC.md](INTERPRETACAO_FASE1_NONRT_FLEXRIC.md).

## Objetivo

A Fase 1 valida dois planos em paralelo, sem acoplamento A1 real entre eles:

- plano 5G/E2: Core OAI + gNB/nrUE OAI ou UERANSIM + nearRT FlexRIC + xApps;
- plano nonRT: O-RAN SC nonRT RIC com PMS, Gateway, Control Panel e A1
  simulators.

Esse cenario é ideal para acompanhar o comportamento do RAN por E2/KPM e, ao
mesmo tempo, validar fluxos de politica nonRT em ambiente controlado.

## Conceitos

| Conceito | Papel nesta fase |
|----------|------------------|
| nonRT RIC | Plano de politicas, servicos e rApps em escala de segundos/minutos |
| PMS | Policy Management Service; cria e consulta policies A1 |
| A1 Simulator | Simula nearRT RIC para que o PMS possa sincronizar RICs e policy types |
| nearRT FlexRIC | RIC leve para E2/xApps, sem A1 real |
| xApp | Aplicacao nearRT que assina E2SM-KPM, E2SM-RC ou SMs customizados |
| rApp | Aplicacao nonRT; nesta fase representa-se por chamadas PMS/policies, nao por loop fechado |

## Arquitetura

```text
                         Fase 1 - planos paralelos

  nonRT RIC Docker
  +-------------------------------------------------------------+
  | Control Panel :8181 -> Gateway :9090 -> PMS :8081          |
  |                                      |                      |
  |                                      v A1 HTTP              |
  |              a1-sim-OSC :30001 / STD / STD-v2 :30005       |
  +-------------------------------------------------------------+

  RAN + nearRT
  +-------------------------------------------------------------+
  | Core OAI + UPF-VPP <-NGAP/GTP-U-> gNB OAI/nrUE or UERANSIM |
  |                                  |                          |
  |                                  v E2AP SCTP :36421        |
  |                         FlexRIC nearRT-RIC + xApps         |
  +-------------------------------------------------------------+
```

Importante: o PMS fala com os simuladores A1, nao com o FlexRIC. Portanto a
Fase 1 prova saude e APIs nonRT, mas nao fecha um loop rApp -> A1 -> xApp real.

## Componentes e portas

| Componente | Porta | Validacao |
|------------|-------|-----------|
| PMS | `8081` | `curl http://127.0.0.1:8081/status` |
| Gateway | `9090` | `curl http://127.0.0.1:9090/actuator/health` |
| Control Panel | `8181` | navegador ou HTTP 200 |
| A1 Sim OSC | `30001` | `/counter/interface` |
| A1 Sim STD v2 | `30005` | `/counter/interface` |
| FlexRIC E2AP | `36421` | `grep 'E2 SETUP RESPONSE' logs/gnb_oai.log` |

## Comandos principais

Subir apenas nonRT:

```bash
./scripts/up_nonrt_ric.sh
./scripts/test_nonrt_ric.sh --seed
./scripts/explore_nonrt_ric.sh full
```

Subir lab completo da Fase 1:

```bash
./scripts/up_e2_lab.sh
./scripts/explore_e2_sm.sh quick
./scripts/test_e2_kpm.sh
```

Gerar carga de UE e observar xApps/nonRT:

```bash
UE_SOURCE=nrue STRESS_DURATION=60 PARALLEL_STREAMS=4 \
  ./scripts/stress_ue_observe_apps.sh
```

Parar:

```bash
./scripts/down_e2_lab.sh
```

## KPMs importantes

| KPM | Unidade | O que indica | Como afetar |
|-----|---------|--------------|-------------|
| `DRB.UEThpDl` | `kbps` | Throughput downlink visto na DRB | iperf DL, trafego DN -> UE |
| `DRB.UEThpUl` | `kbps` | Throughput uplink visto na DRB | iperf UE -> DN |
| `DRB.PdcpSduVolumeDL` | `Mb` | Volume PDCP DL acumulado na janela KPM | trafego sustentado |
| `DRB.PdcpSduVolumeUL` | `Mb` | Volume PDCP UL acumulado na janela KPM | trafego sustentado |
| `DRB.RlcSduDelayDl` | `us` | atraso RLC DL medio observado na janela | aumento de carga/congestao |
| `RRU.PrbTotDl` | `%` | uso de PRB DL | trafego DL |
| `RRU.PrbTotUl` | `%` | uso de PRB UL | trafego UL |

Observacao: o xApp imprime atraso como `μs`; nos resumos de terminal do script
de estresse usamos `us` para manter a saida ASCII.

Verificacao:

```bash
grep -E 'DRB\.|RRU\.|KPM ind_msg|Connected E2 nodes' logs/xapp_kpm_lab.log
```

## Evidencias esperadas

- `test_nonrt_ric.sh`: PMS, A1 simulators, Gateway e Control Panel `OK`.
- `explore_e2_sm.sh`: `Connected E2 nodes = 1` e `Successfully subscribed`.
- `test_e2_kpm.sh`: KPM indications com metricas `DRB.*` e `RRU.*`.
- `stress_ue_observe_apps.sh`: aumento de throughput/PRB durante `stress` e reducao em `recovery`.

## Limites conhecidos

- Sem A1 real para FlexRIC.
- rApps nao recebem KPM do FlexRIC nesta fase.
- O1/SMO fora de escopo.
- FlexRIC e O-RAN SC nearRT nao devem rodar juntos.

## Troubleshooting rapido

| Sintoma | Causa comum | Acao |
|---------|-------------|------|
| PMS offline | containers nonRT ainda subindo | aguardar JVM e rodar `docker compose logs policy-agent` |
| xApp sem E2 node | gNB sem E2 setup | verificar `nearRT-RIC`, `gnb_oai.log` e porta `36421` |
| KPM zerado | pouco trafego ou slice errado | usar `KPM_SST=222 KPM_SD=123 KPM_TRAFFIC=1` |
| gNB aborta com KPM | libs FlexRIC desalinhadas | rodar `./scripts/build_flexric_tools.sh` |
