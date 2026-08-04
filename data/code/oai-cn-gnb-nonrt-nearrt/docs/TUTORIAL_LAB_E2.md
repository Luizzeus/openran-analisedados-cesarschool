# Tutorial — Laboratório OAI + Interface E2 (FlexRIC)

Guia passo a passo para reproduzir o laboratório **5G SA nativo** (Core Docker + gNB/nrUE RFSIM + nearRT-RIC + xApps) com testes de **Service Models E2** (custom, RC, KPM).

> **Escopo:** este lab corre no **host** (Docker só para o Core). **Não** utiliza Kind multicluster nem integração com SD-RAN/Aether.

---

## 1. Resultados obtidos (resumo)


| Procedimento                                    | Estado | Evidência                                              |
| ----------------------------------------------- | ------ | ------------------------------------------------------ |
| Core OAI (UPF-VPP, scenario 1)                  | ✅ OK   | Containers `oai-amf`, `oai-smf`, `oai-upf`, …          |
| Build gNB + nrUE com E2 agent                   | ✅ OK   | `nr-softmodem` com `--build-e2`, FlexRIC branch `dev`  |
| Build nearRT-RIC + xApps (submodule)            | ✅ OK   | `build_flexric_tools.sh`                               |
| Attach UE (IMSI 208950000000032, slice 222/123) | ✅ OK   | `RRCSetupComplete`, PDU session                        |
| E2 SETUP (gNB ↔ nearRT-RIC)                     | ✅ OK   | `[E2-AGENT]: E2 SETUP RESPONSE rx`                     |
| Custom SMs (MAC/RLC/PDCP/GTP, IDs 142–148)      | ✅ OK   | `xapp_cust_moni`, E2 node registrado                   |
| **E2SM-RC** v1.03                               | ✅ OK   | INDICATION com `RRCSetupComplete` decodificado (ASN.1) |
| **E2SM-KPM** v2.03 (slice 222/123)              | ✅ OK   | INDICATIONs periódicas com `DRB.UEThp`*, `RRU.PrbTot*` |
| PoC KPM+RC (`xapp_kpm_rc`)                      | ✅ OK   | Binário compilado; usar após KPM/RC isolados           |
| SLICE / TC (emuladores FlexRIC)                 | ✅ OK   | Não suportados no agente E2 do gNB OAI monolítico      |


**Versões alinhadas:** E2AP v2 (`E2AP_V2`) + E2SM-KPM v2.03 (`KPM_V2_03`), branch FlexRIC `dev`.

---



## 2. Arquitetura

```
┌─────────────────────────────────────────────────────────────────────┐
│  Core OAI (Docker) — oai-cn5g-fed/docker-compose                    │
│  AMF · SMF · NRF · UPF-VPP · UDM · UDR · AUSF · MySQL · DN          │
│  Rede: demo-oai (192.168.70.0/24)  ·  Slice lab: SST=222, SD=123    │
└───────────────────────────────┬─────────────────────────────────────┘
                                │ NGAP / GTP-U
┌───────────────────────────────▼─────────────────────────────────────┐
│  RAN nativo (host) — openairinterface5g                             │
│  nr-softmodem (gNB + E2 agent)  ←RFSIM→  nr-uesoftmodem             │
│  IP host na demo-oai: 192.168.70.129                                │
└───────────────────────────────┬─────────────────────────────────────┘
                                │ E2AP SCTP :36421
┌───────────────────────────────▼─────────────────────────────────────┐
│  nearRT-RIC + xApps (host) — FlexRIC submodule dev                  │
│  nearRT-RIC :36421  ·  iApp (E42) :36422                            │
│  xApps: xapp_kpm_moni, xapp_rc_moni, xapp_cust_moni, …              │
│  SMs: flexric-lib/ (submodule dev — **não** usar /usr/local)        │
└─────────────────────────────────────────────────────────────────────┘
```

---



## 3. Pré-requisitos

- Ubuntu 22.04+ com Docker, Python 3, sudo
- ~8 GB RAM livre, ~15 GB disco (Core + build OAI + FlexRIC)
- IPv4 forwarding: `sudo sysctl -w net.ipv4.ip_forward=1`
- Conta Docker Hub (pull imagens OAI)

Documentação complementar:

- [INSTALACAO_GNB_OAI.md](INSTALACAO_GNB_OAI.md) — dependências e build base do RAN
- [SLIDES_LAB_E2.md](SLIDES_LAB_E2.md) — apresentação dos resultados (formato Marp)
- [E2_FLEXRIC.md](E2_FLEXRIC.md) — operação E2/FlexRIC
- [E2_SERVICE_MODELS.md](E2_SERVICE_MODELS.md) — detalhes RC/KPM/custom SMs

---



## 4. Preparação (uma vez)



### 4.1 Clonar / entrar no projeto

```bash
cd code/oai-cn-gnb
```



### 4.2 Instalar dependências OAI

```bash
cd openairinterface5g/cmake_targets
./build_oai --ninja -I
cd ../..
```



### 4.3 Compilar gNB + nrUE **com agente E2**

```bash
./scripts/build_e2.sh
```

Saída esperada (final):

```
Build concluído. Binários em: openairinterface5g/cmake_targets/ran_build/build/
  nr-softmodem (com E2 agent)
  nr-uesoftmodem
```

Log completo: `logs/build_e2.log`

### 4.4 Compilar nearRT-RIC, Service Models e xApps

```bash
./scripts/build_flexric_tools.sh
```

Isto compila:

- `nearRT-RIC` (submodule FlexRIC)
- SMs: `libkpm_sm.so`, `librc_sm.so`, `libmac_sm.so`, …
- xApps: `xapp_kpm_moni`, `xapp_rc_moni`, `xapp_kpm_rc`, …

As libs são copiadas para `flexric-lib/` (path local do projeto).

> **Importante:** o Core OAI usa **AMF Region ID = 128**. A `libkpm_sm.so` instalada em `/usr/local/lib/flexric/` (versão antiga) **crashava** ao gerar INDICATIONs KPM. Use sempre `flexric-lib/` do submodule `dev`.

---



## 5. Subir o laboratório



### Opção A — Lab completo E2 (recomendado)

```bash
./scripts/up_e2_lab.sh
```

Sequência: Core → nearRT-RIC → gNB + nrUE (com `--e2_agent.sm_dir flexric-lib/`).

### Opção B — Passo a passo manual

```bash
# 1. Core 5G (UPF-VPP, scenario 1)
./scripts/up_core.sh

# 2. nearRT-RIC (submodule dev + flexric-lib/)
./scripts/up_flexric.sh

# 3. gNB + nrUE (RFSIM, slice 222/123)
./scripts/up_gnb_oai.sh
```



### Verificar Core

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep oai
```

Exemplo:

```
oai-amf     Up ...
oai-smf     Up ...
oai-upf     Up ...
```



### Verificar E2 no gNB

```bash
grep -E '\[E2 AGENT\]|\[E2-AGENT\]' logs/gnb_oai.log | tail -15
```

Log esperado (com `flexric-lib/`):

```
[E2 NODE]: Args 127.0.0.1 .../flexric-lib/
[E2 AGENT]: nearRT-RIC IP Address = 127.0.0.1, PORT = 36421, RAN type = ngran_gNB, nb_id = 3584
[E2 AGENT]: Opening plugin from path = .../flexric-lib/libkpm_sm.so
[E2-AGENT]: E2 SETUP-REQUEST tx
[E2-AGENT]: E2 SETUP RESPONSE rx
```



### Verificar attach UE

```bash
grep RRCSetupComplete logs/gnb_oai.log | tail -3
grep -i registered logs/ue_oai.log | tail -3
```

---



## 6. Testes E2 — Service Models



### 6.1 Custom SMs (MAC, RLC, PDCP, GTP)

Plain encoding; funciona independentemente do slice.

```bash
./scripts/test_e2_sm.sh cust
# ou exploração rápida:
./scripts/explore_e2_sm.sh quick
```

Log típico (`logs/xapp_cust_moni.log`):

```
Connected E2 nodes = 1
 Registered node 0 ran func id = 2    # KPM
 Registered node 0 ran func id = 3    # RC
 Registered node 0 ran func id = 142  # MAC
 Registered node 0 ran func id = 143  # RLC
 Registered node 0 ran func id = 144  # PDCP
 ...
```



### 6.2 E2SM-RC (RRC events)

Ordem crítica: **RIC → xApp RC → gNB → UE** (subscrição antes do attach).

```bash
./scripts/test_e2_rc_attach.sh
```

Log típico (`logs/xapp_rc_attach.log`):

```
Connected E2 nodes = 1
[xApp]: Successfully subscribed to RAN_FUNC_ID 3

      1 RC Indication Message received:
RAN Parameter Name = RRC Message
...
            <rrcSetupComplete>
                <rrc-TransactionIdentifier>1</rrc-TransactionIdentifier>
                ...
            </rrcSetupComplete>
```

> **Nota:** o `xapp_rc_moni` pode terminar com timeout em `sync_ui.c` após a **primeira** INDICATION — comportamento conhecido do exemplo upstream. A INDICATION já foi capturada antes do crash.



### 6.3 E2SM-KPM (métricas 3GPP, slice lab)

Slice alinhado ao Core/AMF: **SST=222, SD=123** (ver `openairinterface5g/scripts/ue.conf` e `gnb.conf`).

```bash
./scripts/test_e2_kpm.sh

# Parâmetros opcionais:
KPM_SST=222 KPM_SD=123 XAPP_DURATION=45 KPM_TRAFFIC=1 ./scripts/test_e2_kpm.sh
```

Log típico (`logs/xapp_kpm_lab.log`):

```
Connected E2 nodes = 1
[xApp]: Successfully subscribed to RAN_FUNC_ID 2

      1 KPM ind_msg latency = ...
UE ID type = gNB, amf_ue_ngap_id = 7
ran_ue_id = 1
DRB.PdcpSduVolumeDL = 0 [Mb]
DRB.PdcpSduVolumeUL = 0 [Mb]
DRB.RlcSduDelayDl = 0.00 [μs]
DRB.UEThpDl = 18.04 [kbps]
DRB.UEThpUl = 19.18 [kbps]
RRU.PrbTotDl = 0 [%]
RRU.PrbTotUl = 2 [%]

      2 KPM ind_msg latency = ...
DRB.UEThpDl = 3.72 [kbps]
...
```

Com `KPM_TRAFFIC=1` (padrão), o script gera ping para o DN (`192.168.73.135`) via interface UE (`12.1.1.x`), aumentando throughput medido.

### 6.4 Exploração por suite

```bash
./scripts/explore_e2_sm.sh rc      # foco RC
./scripts/explore_e2_sm.sh kpm     # foco KPM
./scripts/explore_e2_sm.sh oran    # KPM + RC
./scripts/explore_e2_sm.sh layers  # custom MAC/RLC/PDCP/GTP
./scripts/explore_e2_sm.sh full    # todas (demorado)
```

---



## 7. Parar o laboratório

```bash
# Só E2 (RIC + xApps)
./scripts/down_flexric.sh

# RAN (gNB + nrUE)
./scripts/down_gnb_oai.sh

# Lab E2 completo
./scripts/down_e2_lab.sh

# Core Docker
./scripts/down_core.sh

# Tudo
./scripts/down_all.sh
```

---



## 8. Configuração relevante


| Parâmetro        | Valor lab                               | Ficheiro                                 |
| ---------------- | --------------------------------------- | ---------------------------------------- |
| PLMN             | 208 / 95                                | `gnb.conf`, `ue.conf`                    |
| S-NSSAI          | SST **222**, SD **123**                 | `gnb.conf`, `ue.conf`                    |
| IMSI UE          | 208950000000032                         | `ue.conf`                                |
| AMF IP (gNB)     | 192.168.70.129 (host, iface `demo-oai`) | `gnb.conf`                               |
| nearRT-RIC       | 127.0.0.1:36421                         | `gnb.conf` → `e2_agent.near_ric_ip_addr` |
| SMs E2           | `flexric-lib/` (projeto)                | `--e2_agent.sm_dir` nos scripts          |
| KPM filtro slice | `KPM_SST=222`, `KPM_SD=123`             | env vars nos scripts KPM                 |


Exemplo `e2_agent` em `openairinterface5g/scripts/gnb.conf`:

```
e2_agent = {
  near_ric_ip_addr = "127.0.0.1";
  sm_dir = ".../flexric-lib/";   # override via --e2_agent.sm_dir nos scripts
};
```

---



## 9. Scripts de referência


| Script                              | Função                                         |
| ----------------------------------- | ---------------------------------------------- |
| `build_e2.sh`                       | Compila gNB/nrUE com E2 agent                  |
| `build_flexric_tools.sh`            | Compila RIC, SMs, xApps; popula `flexric-lib/` |
| `sync_flexric_lib.sh`               | Copia `.so` do build FlexRIC → `flexric-lib/`  |
| `up_e2_lab.sh`                      | Core + RIC + gNB + UE                          |
| `up_flexric.sh` / `down_flexric.sh` | nearRT-RIC                                     |
| `up_gnb_oai.sh` / `down_gnb_oai.sh` | gNB + nrUE                                     |
| `test_e2_kpm.sh`                    | Teste KPM slice 222/123                        |
| `test_e2_rc_attach.sh`              | Teste RC com attach fresco                     |
| `test_e2_sm.sh`                     | Testes por SM (`cust`, `rc`, `kpm`, …)         |
| `explore_e2_sm.sh`                  | Suites de exploração                           |


Logs: diretório `logs/` (`gnb_oai.log`, `ue_oai.log`, `nearRT-RIC.log`, `xapp_kpm_lab.log`, …).

---



## 10. Troubleshooting



### KPM timeout / crash do gNB

**Sintoma:**

```
cp_amf_region_id_to_bit_string: Assertion `src < 64' failed
```

**Causa:** `libkpm_sm.so` de `/usr/local` incompatível com AMF Region ID 128.

**Solução:**

```bash
./scripts/build_flexric_tools.sh
./scripts/down_flexric.sh && ./scripts/down_gnb_oai.sh
./scripts/test_e2_kpm.sh
```



### nearRT-RIC crash `E2 Node not found in the tree`

**Causa:** xApps “zombie” a ligar-se ao RIC sem nó E2 registado, ou gNB desalinhado após restart do RIC.

**Solução:**

```bash
./scripts/down_flexric.sh
pkill -f xapp_ 2>/dev/null || true
./scripts/up_flexric.sh
./scripts/down_gnb_oai.sh && ./scripts/up_gnb_oai.sh
```



### RC sem INDICATIONs

- Subscrever **antes** do attach: `./scripts/test_e2_rc_attach.sh`
- RC é **aperiódico** (eventos RRC); o attach do UE dispara `RRCSetupComplete`



### KPM sem métricas (zeros)

- Confirmar PDU session no slice 222/123
- Usar `KPM_TRAFFIC=1` e verificar ping ao DN
- Aumentar `XAPP_DURATION=60`



### `xapp_oran_moni` (/usr/local)

Não usar para KPM neste lab — filtro SST=1 por defeito. Usar `./scripts/test_e2_kpm.sh`.

---



## 11. Sequência mínima de reprodução (checklist)

```bash
cd code/oai-cn-gnb

# Build (uma vez)
./scripts/build_e2.sh
./scripts/build_flexric_tools.sh

# Subir stack
./scripts/up_e2_lab.sh
sleep 30

# Testes
./scripts/test_e2_sm.sh cust          # custom SMs
./scripts/test_e2_rc_attach.sh        # RC + attach
./scripts/test_e2_kpm.sh              # KPM slice 222/123

# Inspecionar
grep -E 'Successfully subscribed|INDICATION|UEThp' logs/xapp_*.log
grep 'E2 SETUP RESPONSE' logs/gnb_oai.log

# Parar
./scripts/down_e2_lab.sh
```

---



## 12. Próximos passos (opcional)

- Validar `xapp_kpm_rc` (monitor KPM + RC Control) com tráfego sustentado
- Aumentar duração dos testes para séries temporais de métricas KPM
- Integrar recolha automática de logs num pipeline de CI local

---

*Documento gerado com base nos testes executados em Jun/2026 no host de desenvolvimento do projeto* `oai-cn-gnb` *(RNP Failover / CERISE).*