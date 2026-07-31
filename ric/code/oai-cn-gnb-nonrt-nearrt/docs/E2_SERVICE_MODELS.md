# Explorando Service Models E2 no OAI

Guia prático para **E2SM-RC**, **E2SM-KPM** e **custom SMs** no gNB OAI monolítico (RFSIM).

## Mapa de capacidades

| SM | O-RAN / Custom | O que expõe | xApp | Funciona no lab (222/123)? |
|----|----------------|-------------|------|----------------------------|
| **E2SM-RC** v1.03 | O-RAN | RRC state, cópia de mensagens RRC, UE ID | `xapp_rc_moni` | **Sim** (aperiódico) |
| **E2SM-KPM** v2.03 | O-RAN | PRB, throughput, PDCP volume… | `xapp_kpm_moni` | OK (slice 222/123 via `test_e2_kpm.sh`) |
| **MAC** | Custom | KPIs MAC por UE | `xapp_cust_moni` | **Sim** |
| **RLC** | Custom | Stats por bearer | idem | **Sim** |
| **PDCP** | Custom | Stats por bearer | idem | **Sim** |
| **GTP** | Custom | Stats GTP-U NGU | idem | **Sim** (gNB-mono) |
| **SLICE / TC** | Custom | Slice / traffic control | emulador FlexRIC | **Não** no OAI RAN |

## E2SM-RC — o mais interessante para controle RAN

Implementação OAI (`openairinterface5g/openair2/E2AP/RAN_FUNCTION/O-RAN/ran_func_rc.c`):

### REPORT Service Style 1 — Message copy (aperiódico)

Eventos disparados quando o UE completa procedimentos RRC:

| Evento | Quando |
|--------|--------|
| **UE ID** | `RRC Setup Complete`, F1 UE Context Setup |
| **RRC Message copy** | `RRC Reconfiguration`, `Measurement Report`, `Security Mode Complete`, `RRC Setup Complete` |

O xApp `xapp_rc_moni` decodifica ASN.1 e imprime UE ID (AMF NGAP ID, RAN UE ID) e conteúdo RRC.

### REPORT Service Style 4 — UE Information (aperiódico)

| Parâmetro | Valores |
|-----------|---------|
| **RRC State Changed To** | `idle`, `inactive`, `connected` |

Disparado em transições RRC (ex.: attach → `RRC_CONNECTED`).

### CONTROL Service Style 1 — Radio Bearer Control

| Ação O-RAN | Comportamento OAI |
|------------|-------------------|
| QoS flow mapping | PoC: **criação de novo DRB** (OAI não multiplexa múltiplos QoS flows num DRB) |

Testar com `xapp_kpm_rc` (monitor KPM + envia RC Control). O controlo real no RAN é limitado — ver branch `qoe-e2` upstream para demo completa.

## Scripts de exploração

```bash
cd code/oai-cn-gnb

# Lab no ar
./scripts/up_e2_lab.sh

# Exploração rápida (custom + RC)
./scripts/explore_e2_sm.sh quick

# Aprofundar RC + PoC KPM/RC control
./scripts/explore_e2_sm.sh rc

# O-RAN KPM + RC agregado
./scripts/explore_e2_sm.sh oran

# Camadas L2/L3 detalhadas
./scripts/explore_e2_sm.sh layers

# Tudo
./scripts/explore_e2_sm.sh full
```

Testes individuais:

```bash
XAPP_DURATION=30 ./scripts/test_e2_sm.sh rc       # só RC
XAPP_DURATION=30 ./scripts/test_e2_sm.sh kpm_rc  # KPM + RC control PoC
XAPP_DURATION=30 ./scripts/test_e2_sm.sh gtp     # MAC/RLC/PDCP/GTP + DB sqlite
```

### Gerar eventos RC durante o teste

RC é **aperiódico** — INDICATIONs aparecem em attach/detach ou handover. Para ver eventos durante `xapp_rc_moni`:

```bash
# Terminal 1: xApp RC (30s)
XAPP_DURATION=30 ./scripts/test_e2_sm.sh rc

# Terminal 2 (nos primeiros 10s): reiniciar UE para forçar RRC Setup
./scripts/down_gnb_oai.sh   # para gNB+UE
./scripts/up_gnb_oai.sh     # sobe de novo → novo RRC attach
```

## O que procurar nos logs

```bash
# RC: state change, UE ID, mensagens RRC
grep -iE 'RRC connected|UE ID|RRCReconfiguration|INDICATION' logs/xapp_rc_moni.log

# Custom: métricas periódicas por UE
grep -iE 'MAC|RLC|PDCP|throughput|INDICATION' logs/xapp_cust_moni.log

# Agente E2 no gNB
grep -iE '\[E2 AGENT\].*RC|signal_rrc|signal_ue_id' logs/gnb_oai.log
```

Sucesso RC típico:

```
UE ID type = gNB, amf_ue_ngap_id = ...
RAN Parameter Value = RRC connected
RRC Message ... RRCSetupComplete
```

## E2SM-KPM — métricas O-RAN

Métricas 3GPP TS 28.552: `DRB.PdcpSduVolumeDL/UL`, `DRB.UEThpDl/Ul`, `RRU.PrbTotDl/Ul`, etc.

Os xApps `xapp_kpm_moni` / `xapp_kpm_rc` (FlexRIC `dev`) usam por defeito **SST=222, SD=123** (`KPM_SST` / `KPM_SD`).

```bash
./scripts/test_e2_kpm.sh
./scripts/explore_e2_sm.sh kpm
KPM_SST=222 KPM_SD=123 XAPP_DURATION=45 ./scripts/test_e2_kpm.sh
```

`KPM_TRAFFIC=1` (padrão) gera ping ao DN durante o teste para métricas de volume/throughput.

PoC closed-loop: `KPM_SST=222 KPM_SD=123 ./scripts/test_e2_sm.sh kpm_rc`

## Custom SMs — dados offline (ML/AI)

`xapp_gtp_mac_rlc_pdcp_moni` grava em `/tmp/xapp_db_*` (SQLite):

```bash
ls /tmp/xapp_db_*
# sqlitebrowser /tmp/xapp_db_<timestamp>
```

Structs de referência ( código OAI ):

- MAC: `mac_ue_stats_impl_t`
- RLC: `rlc_radio_bearer_stats_t`
- PDCP: `pdcp_radio_bearer_stats_t`
- GTP: `gtp_ngu_t_stats_t`

## xApps compilados localmente

Os xApps dedicados (RC, KPM, KPM+RC) vivem no submodule FlexRIC:

```
openairinterface5g/openair2/E2AP/flexric/build/examples/xApp/c/monitor/
  xapp_rc_moni
  xapp_kpm_moni
  xapp_gtp_mac_rlc_pdcp_moni
openairinterface5g/openair2/E2AP/flexric/build/examples/xApp/c/kpm_rc/
  xapp_kpm_rc
```

Compilar (automático em `explore_e2_sm.sh`):

```bash
cd openairinterface5g/openair2/E2AP/flexric/build
cmake .. -GNinja -DE2AP_VERSION=E2AP_V2 -DKPM_VERSION=KPM_V2_03
ninja xapp_rc_moni xapp_kpm_moni xapp_kpm_rc xapp_gtp_mac_rlc_pdcp_moni
```

## Próximos passos interessantes

| Objetivo | Caminho |
|----------|---------|
| RC Control real (novo DRB) | Branch upstream `qoe-e2` ou `xapp_kpm_rc` + tráfego |
| KPM com slice 222/123 | `./scripts/test_e2_kpm.sh` + `flexric-lib/` (submodule dev) |
| CU/DU split + E2 | gNB split + E2 agent em CU-CP/CU-UP/DU |
| O-RAN SC nearRT-RIC | Porta E2AP 36422, xDevSM framework |
| Wireshark E2AP | Capturar SCTP :36421 localhost |

## Referências

- [E2_FLEXRIC.md](E2_FLEXRIC.md) — operação do lab
- [OAI E2AP README](../openairinterface5g/openair2/E2AP/README.md)
- O-RAN E2SM-RC v01.03, E2SM-KPM v2.03
