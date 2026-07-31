---
marp: true
theme: default
paginate: true
header: "OAI + E2 Interface · RNP Failover / CERISE"
footer: "Jun 2026 · code/oai-cn-gnb"
style: |
  section {
    font-family: 'Segoe UI', system-ui, sans-serif;
  }
  section.lead h1 {
    text-align: center;
  }
  section.lead p {
    text-align: center;
  }
  code {
    font-size: 0.85em;
  }
  pre {
    font-size: 0.72em;
  }
  table {
    font-size: 0.82em;
  }
  .columns {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 1rem;
  }
---

<!-- _class: lead -->
<!-- _paginate: false -->

# Laboratório OAI + Interface E2

### Resultados com FlexRIC · Service Models RC & KPM

**Projeto:** RNP Failover / CERISE  
**Stack:** Core OAI (UPF-VPP) · gNB/nrUE RFSIM · nearRT-RIC · xApps

`code/oai-cn-gnb`

---

## Objetivo

Validar a **interface E2** no gNB OpenAirInterface com testes de **Service Models**:

| SM | Padrão | Foco |
|----|--------|------|
| Custom | FlexRIC plain | MAC · RLC · PDCP · GTP |
| **E2SM-RC** | O-RAN v1.03 | Eventos RRC (copy UE ID) |
| **E2SM-KPM** | O-RAN v2.03 | Métricas 3GPP por slice |

**Fora de escopo:** Kind multicluster · SD-RAN / Aether · RIC cloud

---

## Arquitetura do laboratório

```
┌──────────────────────────────────────────────┐
│  Core 5G (Docker)  AMF · SMF · UPF-VPP · …   │
│  Rede demo-oai · Slice SST=222 SD=123        │
└────────────────────┬─────────────────────────┘
                     │ NGAP / GTP-U
┌────────────────────▼─────────────────────────┐
│  RAN nativo (host)                           │
│  nr-softmodem + E2 agent  ←RFSIM→  nrUE      │
└────────────────────┬─────────────────────────┘
                     │ E2AP :36421
┌────────────────────▼─────────────────────────┐
│  nearRT-RIC + xApps (FlexRIC branch dev)     │
│  flexric-lib/  ·  iApp E42 :36422            │
└──────────────────────────────────────────────┘
```

---

## Versões e alinhamento

| Componente | Versão / branch |
|------------|-----------------|
| E2AP | **v2** (`E2AP_V2`) |
| E2SM-KPM | **v2.03** (`KPM_V2_03`) |
| FlexRIC | Submodule branch **`dev`** |
| gNB | `nr-softmodem` compilado com `--build-e2` |
| Modo RAN | **RFSIM** (sem hardware RF) |
| Core | `start-basic-vpp` scenario 1 |

> gNB, nearRT-RIC e xApps **devem** partilhar a mesma stack E2AP.

---

## Configuração do slice lab

| Parâmetro | Valor |
|-----------|-------|
| PLMN | 208 / 95 |
| S-NSSAI | **SST 222** · **SD 123** |
| IMSI UE | `208950000000032` |
| AMF (host) | `192.168.70.129` · iface `demo-oai` |
| nearRT-RIC | `127.0.0.1:36421` |

Ficheiros: `openairinterface5g/scripts/gnb.conf` · `ue.conf`

---

## Resultados — visão geral

| Procedimento | Estado |
|--------------|:------:|
| Core OAI + attach UE | ✅ |
| Build gNB E2 + FlexRIC tools | ✅ |
| E2 SETUP gNB ↔ RIC | ✅ |
| Custom SMs (142–148) | ✅ |
| **E2SM-RC** — INDICATION RRC | ✅ |
| **E2SM-KPM** — métricas periódicas | ✅ |
| PoC KPM+RC (`xapp_kpm_rc`) | ⚠️ |
| SLICE / TC emulators | ❌ N/A |

---

## E2 SETUP — ligação estabelecida

```text
[E2 AGENT]: nearRT-RIC IP = 127.0.0.1, PORT = 36421
             RAN type = ngran_gNB, nb_id = 3584
[E2 AGENT]: Opening plugin .../flexric-lib/libkpm_sm.so
[E2 AGENT]: Opening plugin .../flexric-lib/librc_sm.so
[E2-AGENT]: E2 SETUP-REQUEST tx
[E2-AGENT]: E2 SETUP RESPONSE rx
```

**RAN Functions registadas:** KPM (2) · RC (3) · MAC/RLC/PDCP/GTP (142–148)

---

## Custom Service Models

**xApp:** `xapp_cust_moni` · encoding plain · independente do slice

```text
Connected E2 nodes = 1
 Registered node 0 ran func id = 2   # KPM
 Registered node 0 ran func id = 3   # RC
 Registered node 0 ran func id = 142 # MAC
 Registered node 0 ran func id = 143 # RLC
 Registered node 0 ran func id = 144 # PDCP
 Registered node 0 ran func id = 148 # GTP
```

✅ Confirma stack E2 end-to-end antes dos testes O-RAN.

---

## E2SM-RC — subscrição e evento RRC

**Script:** `./scripts/test_e2_rc_attach.sh`  
**Ordem:** RIC → xApp RC → gNB → UE *(subscrição antes do attach)*

```text
[xApp]: Successfully subscribed to RAN_FUNC_ID 3

      1 RC Indication Message received:
RAN Parameter Name = RRC Message
            <rrcSetupComplete>
                <rrc-TransactionIdentifier>1</rrc-TransactionIdentifier>
                ...
            </rrcSetupComplete>
```

✅ Mensagem RRC decodificada em ASN.1 · evento `RRCSetupComplete`

---

## E2SM-RC — nota operacional

O `xapp_rc_moni` pode terminar com **timeout** em `sync_ui.c` após a 1.ª INDICATION — comportamento conhecido do exemplo FlexRIC.

| Aspecto | Detalhe |
|---------|---------|
| Impacto | INDICATION **já capturada** antes do exit |
| Mitigação | Usar `test_e2_rc_attach.sh` · inspecionar log |
| Log | `logs/xapp_rc_attach.log` |

---

## E2SM-KPM — subscrição slice 222/123

**Script:** `./scripts/test_e2_kpm.sh`  
**Filtro:** `KPM_SST=222` · `KPM_SD=123` · Report Style 4 (S-NSSAI)

```text
Connected E2 nodes = 1
[xApp]: Successfully subscribed to RAN_FUNC_ID 2

UE ID type = gNB, amf_ue_ngap_id = 7
ran_ue_id = 1
DRB.UEThpDl = 18.04 [kbps]
DRB.UEThpUl = 19.18 [kbps]
RRU.PrbTotUl = 2 [%]
```

✅ INDICATIONs periódicas (~1 s) com métricas 3GPP

---

## E2SM-KPM — métricas observadas

| Métrica | Exemplo | Unidade |
|---------|---------|---------|
| `DRB.UEThpDl` | 3.72 – 18.04 | kbps |
| `DRB.UEThpUl` | 3.72 – 19.18 | kbps |
| `RRU.PrbTotUl` | 2 | % |
| `DRB.RlcSduDelayDl` | 9 – 141 | μs |
| `DRB.PdcpSduVolume*` | 0* | Mb |

\* Volume PDCP zero em RFSIM leve; **`KPM_TRAFFIC=1`** (ping ao DN) aumenta throughput.

---

## Problema resolvido — libs FlexRIC

### Sintoma
```
cp_amf_region_id_to_bit_string: Assertion `src < 64' failed
```
gNB crash · KPM sem INDICATIONs · RIC instável

### Causa
`libkpm_sm.so` de **`/usr/local`** incompatível com **AMF Region ID 128** (Core OAI)

### Solução
Compilar SMs do submodule **`dev`** → diretório **`flexric-lib/`**

```bash
./scripts/build_flexric_tools.sh   # popula flexric-lib/
```

---

## Como reproduzir (resumo)

```bash
cd code/oai-cn-gnb

# Build (uma vez)
./scripts/build_e2.sh
./scripts/build_flexric_tools.sh

# Subir lab
./scripts/up_e2_lab.sh

# Testes
./scripts/test_e2_sm.sh cust
./scripts/test_e2_rc_attach.sh
./scripts/test_e2_kpm.sh

# Parar
./scripts/down_e2_lab.sh
```

Tutorial completo: `docs/TUTORIAL_LAB_E2.md`

---

## Scripts principais

| Script | Função |
|--------|--------|
| `up_e2_lab.sh` | Core + RIC + gNB + UE |
| `build_flexric_tools.sh` | RIC · SMs · xApps → `flexric-lib/` |
| `test_e2_kpm.sh` | KPM slice 222/123 + tráfego |
| `test_e2_rc_attach.sh` | RC com attach fresco |
| `explore_e2_sm.sh` | Suites `rc` · `kpm` · `oran` · `full` |

Logs: `logs/gnb_oai.log` · `xapp_kpm_lab.log` · `xapp_rc_attach.log`

---

## Conclusões

1. **Interface E2 operacional** no gNB OAI monolítico com nearRT-RIC FlexRIC `dev`
2. **RC e KPM O-RAN** validados com evidência em logs (subscrição + INDICATION)
3. **Slice 222/123** alinhado entre Core, gNB, UE e filtro KPM
4. **Stack nativa no host** — simples de reproduzir, sem Kind multicluster
5. **Lição crítica:** alinhar versões E2AP **e** path das SMs (`flexric-lib/`)

---

## Próximos passos

- [ ] Validar `xapp_kpm_rc` (KPM monitor + RC control)
- [ ] Séries temporais KPM com tráfego sustentado
- [ ] Documentar métricas vs. cenários de carga
- [ ] Pipeline local de recolha de logs / CI

---

<!-- _class: lead -->
<!-- _paginate: false -->

# Obrigado

### Documentação

| Documento | Conteúdo |
|-----------|----------|
| `docs/TUTORIAL_LAB_E2.md` | Tutorial passo a passo |
| `docs/E2_FLEXRIC.md` | Operação FlexRIC |
| `docs/E2_SERVICE_MODELS.md` | Detalhes RC / KPM / custom |

**Exportar estes slides:** extensão [Marp for VS Code](https://marketplace.visualstudio.com/items?itemName=marp-team.marp-vscode) ou `marp docs/SLIDES_LAB_E2.md -o slides.pdf`
