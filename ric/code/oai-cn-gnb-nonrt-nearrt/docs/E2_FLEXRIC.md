# Interface E2 e Service Models (FlexRIC)

Guia para operar a interface **E2** entre o gNB OAI e um **nearRT-RIC** (FlexRIC), e testar **Service Models** (SMs) O-RAN e customizados.

## Arquitetura

```
┌─────────────────────────────────────────────────────────────┐
│  Core OAI (AMF, SMF, UPF-VPP, ...)                          │
└──────────────────────────┬──────────────────────────────────┘
                           │ N2 / N3
┌──────────────────────────┴──────────────────────────────────┐
│  gNB OAI (nr-softmodem)                                       │
│    └── E2 Agent ──E2AP──► nearRT-RIC (FlexRIC) :36421         │
│                              └── xApps (KPM, RC, MAC, ...)    │
└──────────────────────────┬──────────────────────────────────┘
                           │ RFSIM
                      nrUE (nr-uesoftmodem)
```

## Service Models disponíveis

| SM | Tipo | Encoding | xApp recomendado | Notas |
|----|------|----------|------------------|-------|
| **E2SM-KPM** v2.03 | O-RAN | ASN.1 | `xapp_oran_moni` | Métricas 3GPP (PRB, throughput, PDCP volume…) |
| **E2SM-RC** v1.03 | O-RAN | ASN.1 | `xapp_oran_moni` | RRC state, message copy, QoS control (PoC) |
| **MAC** | Custom | Plain | `xapp_gtp_mac_rlc_pdcp_moni` | KPIs L2 MAC por UE |
| **RLC** | Custom | Plain | `xapp_gtp_mac_rlc_pdcp_moni` | KPIs RLC por bearer |
| **PDCP** | Custom | Plain | `xapp_gtp_mac_rlc_pdcp_moni` | KPIs PDCP por bearer |
| **GTP** | Custom | Plain | `xapp_gtp_mac_rlc_pdcp_moni` | Stats GTP-U NGU |

Versões padrão de compilação: **E2AP v2.03** + **E2SM-KPM v2.03** (devem coincidir entre gNB e FlexRIC).

Documentação upstream: `openairinterface5g/openair2/E2AP/README.md`

## Pré-requisitos

1. **FlexRIC** instalado no host (Service Models em `/usr/local/lib/flexric/`):

   ```bash
   # Se ainda não tiver FlexRIC:
   git clone https://gitlab.eurecom.fr/mosaic5g/flexric.git
   cd flexric && git checkout dev
   mkdir build && cd build
   cmake .. -GNinja -DE2AP_VERSION=E2AP_V2 -DKPM_VERSION=KPM_V2_03
   ninja && sudo ninja install
   ```

2. **Submodule FlexRIC** no OAI (para compilar o E2 agent):

   ```bash
   # Automático via ./scripts/build_e2.sh
   ```

3. **Core OAI** operacional (`./scripts/up_core.sh`).

## Build do gNB com E2 Agent

```bash
cd code/oai-cn-gnb
./scripts/build_e2.sh
```

Isso compila `nr-softmodem` e `nr-uesoftmodem` com `-DE2_AGENT=ON`. Log em `logs/build_e2.log` (~15–30 min na primeira vez).

## Configuração E2 no gNB

Em `openairinterface5g/scripts/gnb.conf`:

```bash
e2_agent = {
  near_ric_ip_addr = "127.0.0.1";
  sm_dir = "/usr/local/lib/flexric/";
};
```

- `near_ric_ip_addr`: IP do nearRT-RIC (localhost se FlexRIC corre no mesmo host).
- `sm_dir`: diretório com `libkpm_sm.so`, `librc_sm.so`, `libmac_sm.so`, etc.

Porta E2AP FlexRIC: **36421** (O-RAN SC usa 36422 — requer recompilação com `e2ap_server_port`).

## Fluxo operacional

### Opção A — laboratório completo (recomendado)

```bash
./scripts/up_e2_lab.sh          # Core + RIC + gNB + UE
./scripts/test_e2_sm.sh cust    # testar MAC/RLC/PDCP/GTP
./scripts/down_e2_lab.sh
```

### Opção B — passo a passo

```bash
./scripts/up_core.sh
./scripts/up_flexric.sh
./scripts/up_gnb_oai.sh
./scripts/test_e2_sm.sh cust
```

## Testar Service Models

```bash
# Custom SMs (funciona com slice 222/123 do laboratório)
XAPP_DURATION=30 ./scripts/test_e2_sm.sh cust

# O-RAN KPM + RC
./scripts/test_e2_sm.sh oran

# Todos os SMs
./scripts/test_e2_sm.sh all
```

### Verificar E2 setup

```bash
grep -iE 'E2|RIC|setup|indication' logs/gnb_oai.log
grep -iE 'E2|setup|indication' logs/nearRT-RIC.log
```

Indícios de sucesso:
- gNB: mensagens `E2 Setup` / conexão SCTP ao RIC
- xApp: `RIC INDICATION` com métricas periódicas

### KPM e slice S-NSSAI

Por defeito upstream, o xApp KPM subscreve **SST=1**. Este laboratório usa **SST=222, SD=123**.

Os xApps `xapp_kpm_moni` e `xapp_kpm_rc` (submodule FlexRIC `dev`) foram ajustados para o slice do lab:

```bash
# Padrão: SST=222 SD=123 (Core/AMF/gNB/UE)
./scripts/test_e2_kpm.sh

# Override
KPM_SST=222 KPM_SD=123 XAPP_DURATION=45 ./scripts/test_e2_kpm.sh

# Só SST (SD wildcard no agente)
KPM_SD=any ./scripts/test_e2_kpm.sh
```

Métricas O-RAN suportadas (3GPP TS 28.552): `DRB.PdcpSduVolumeDL/UL`, `DRB.UEThpDl/Ul`, `RRU.PrbTotDl/Ul`, etc.

Gere tráfego durante o teste (`KPM_TRAFFIC=1` por defeito) para métricas de throughput/volume não-zero.

**SMs:** o gNB e o nearRT-RIC devem usar as libs do submodule (`flexric-lib/`), não `/usr/local/lib/flexric/` — a versão instalada no sistema falha com AMF Region ID 128 do Core OAI. `./scripts/build_flexric_tools.sh` compila e sincroniza automaticamente.

**Nota:** `xapp_oran_moni` (instalado em `/usr/local`) ainda usa SST=1 — use `./scripts/test_e2_kpm.sh` para KPM neste lab.

## Scripts

| Script | Descrição |
|--------|-----------|
| `build_e2.sh` | Compila gNB/nrUE com E2 agent |
| `up_flexric.sh` | Inicia nearRT-RIC |
| `down_flexric.sh` | Para RIC e xApps |
| `up_e2_lab.sh` | Core + RIC + gNB + UE |
| `down_e2_lab.sh` | Para gNB e RIC (`--all` inclui Core) |
| `test_e2_kpm.sh` | KPM com slice lab (222/123) + tráfego |
| `explore_e2_sm.sh` | Suite de exploração (rc, oran, layers, full) |
| `test_e2_rc_attach.sh` | RC com attach sincronizado (captura INDICATIONs) |
| `build_flexric_tools.sh` | Compila nearRT-RIC + xApps dedicados (dev) |

## Troubleshooting

| Problema | Causa provável | Solução |
|----------|----------------|---------|
| Build falha "submodules not downloaded" | FlexRIC vazio | `./scripts/build_e2.sh` (clona automaticamente) |
| gNB não conecta ao RIC | RIC parado ou IP errado | `./scripts/up_flexric.sh`; verificar `near_ric_ip_addr` |
| xApp sem INDICATION (cust) | UE sem PDU session | Aguardar registro; verificar logs AMF/SMF |
| xApp sem INDICATION (KPM) | Filtro slice SST=1 | Usar `test_e2_sm.sh cust` ou alinhar slice |
| `libkpm_sm.so` not found | FlexRIC não instalado | `./scripts/build_flexric_tools.sh` |
| KPM crash / timeout | SMs de `/usr/local` desalinhados (AMF Region ID 128) | Usar `flexric-lib/` via `./scripts/sync_flexric_lib.sh` |
| xApp crash `e2ap_dec_e42_setup_response` | xApp de `/usr/local` ou `/opt/flexric` | `./scripts/test_e2_sm.sh` usa só xApps do submodule dev |

## Referências

- [OAI E2AP README](../openairinterface5g/openair2/E2AP/README.md)
- [FlexRIC](https://gitlab.eurecom.fr/mosaic5g/flexric)
- [O-RAN E2SM-KPM](https://orandownloadsweb.azurewebsites.net/specifications)
- Docker Compose upstream (sem Core): `openairinterface5g/ci-scripts/yaml_files/5g_rfsimulator_flexric/`
