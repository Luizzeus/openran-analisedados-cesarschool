# Roteiro — OAI CN+GNB + FlexRIC (Near-RT RIC, E2, E2SM)

**Disciplina:** RAN Intelligent Controller (RIC) · **Aulas 04, 05 e 06**

**Código:** `ric/code/oai-cn-gnb-e2/`

## Documentação relacionada

| Documento | Uso |
|-----------|-----|
| [03-demo-e2-aula04.md](03-demo-e2-aula04.md) | Demo guiada em sala (Bloco 3, Aula 04) |
| [04-projeto2-plano-testes.md](04-projeto2-plano-testes.md) | Plano de testes Projeto 2 (workshop Aula 05) |
| [../E2_FLEXRIC.md](../E2_FLEXRIC.md) | Índice de documentação E2 |
| [../E2_FLEXRIC.md](../../../E2_FLEXRIC.md) | Build, deploy, scripts, troubleshooting |
| [../E2_SERVICE_MODELS.md](../../../E2_SERVICE_MODELS.md) | KPM, RC, custom, interpretação de logs |
| [../avaliacao_seminario_aula06.md](../avaliacao_seminario_aula06.md) | Rubrica Projeto 2 (40%) |

---

## Objetivos

- Operar a pilha **OAI** (core `oai-cn5g-fed` + gNB/nrUE com **RFSIM**)
- Subir **FlexRIC** como Near-RT RIC e associar o **E2 agent** integrado ao gNB OAI
- Executar **subscriptions E2** e xApps de referência (E2SM-KPM, E2SM-RC conforme build)
- Mapear atividades ao **ciclo de vida** do xApp (Design → Onboard → Deploy → Operate → Retire)
- Produzir evidências para **Projeto 2 (40%)** — apresentação na Aula 06

---

## Arquitetura do lab

```
FlexRIC (near-RT RIC + xApps)
        │ E2AP :36421
        ▼
OAI gNB (nr-softmodem + E2 agent) ── RFSIM ── OAI nrUE
        │ NGAP/N2, GTP-U/N3
        ▼
OAI 5G Core (docker-compose oai-cn5g-fed)
```

| Parâmetro | Valor no lab |
|-----------|--------------|
| Slice | SST=222, SD=123 |
| E2AP | v2 |
| E2SM-KPM | v2.03 |
| RF | RFSIM (`-w SIMU`) |

Configuração E2 no gNB: `openairinterface5g/scripts/gnb.conf` → bloco `e2_agent`  
Os scripts passam `--e2_agent.sm_dir flexric-lib/` quando o build FlexRIC foi executado.

---

## Pré-requisitos

- Ubuntu 22.04+, 16 GB RAM recomendados
- Docker para o core OAI
- Build com E2 e FlexRIC alinhados (**E2AP_V2**, **KPM_V2_03**):

```bash
cd ric/code/oai-cn-gnb-e2
./scripts/build_e2.sh
./scripts/build_flexric_tools.sh
```

---

## Ordem de subida (obrigatória)

**Opção rápida:**

```bash
cd ric/code/oai-cn-gnb-e2
./scripts/up_e2_lab.sh
```

**Passo a passo:**

1. `./scripts/up_core.sh` — Core OAI  
2. `./scripts/up_flexric.sh` — nearRT-RIC  
3. `./scripts/up_gnb_oai.sh` — gNB + nrUE (E2 agent → `127.0.0.1`)  
4. `./scripts/test_e2_sm.sh cust` — validar E2  
5. `./scripts/test_e2_kpm.sh` e/ou `./scripts/test_e2_rc_attach.sh`

Parar: `./scripts/down_e2_lab.sh` (adicione `--all` para parar o Core)

**Verificação automatizada:**

```bash
./scripts/verify_e2_lab.sh        # cust + KPM
./scripts/verify_e2_lab.sh full   # + RC attach
```

> **UERANSIM** (`./scripts/up_ueransim.sh`) serve apenas para N2/N3 sem E2 no gNB OAI — não substitui o gNB OAI para testes E2.

---

## Cronograma por aula

### Aula 04 — xApps open source + demo E2

| Bloco | Conteúdo | Roteiro |
|-------|----------|---------|
| 1 | OAI, deploy, interface E2, ciclo de vida xApp | Slides `aula04-xapps_opensource.md` |
| 2 | OSC, FlexRIC, SD-RAN | NGO §3 |
| 3 | **Demo guiada** — subir lab e testes KPM/RC | [03-demo-e2-aula04.md](03-demo-e2-aula04.md) |

**Entrega parcial (fim da Aula 04):** pelo menos uma evidência de E2 SETUP + subscription (log ou screenshot).

### Aula 05 — SMO + workshop Projeto 2

| Atividade | Roteiro |
|-----------|---------|
| Arquitetura integrada (NGO Fig. 6) | Slides Aula 05 |
| **Workshop:** preencher plano de testes | [04-projeto2-plano-testes.md](04-projeto2-plano-testes.md) |
| Reproduzir CT-01 a CT-04 no ambiente do grupo | Este documento § ordem de subida |

### Aula 06 — Apresentação Projeto 2 (40%)

| Item | Detalhe |
|------|---------|
| Horário | 08:00–11:00 |
| Duração | 20 min por grupo (mesma ordem do Projeto 1) |
| Rubrica | [avaliacao_seminario_aula06.md](../avaliacao_seminario_aula06.md) |
| Anexos | Plano de testes + logs + README reprodutível |

---

## Ciclo de vida do xApp ↔ laboratório

| Fase | Ação no lab | Comando / evidência |
|------|-------------|---------------------|
| **Design** | Escolher E2SM e extensão do Projeto 2 | Documentar em relatório |
| **Onboard** | Build alinhado OAI + FlexRIC | `build_e2.sh`, `build_flexric_tools.sh` |
| **Deploy** | Subir Core, RIC, gNB | `up_e2_lab.sh`, log `E2 SETUP` |
| **Operate** | Subscriptions e INDICATIONs | `test_e2_kpm.sh`, `test_e2_rc_attach.sh` |
| **Retire** | Parar xApps e lab | `down_e2_lab.sh` |

---

## Verificações E2

```bash
grep -iE 'E2 SETUP' logs/gnb_oai.log
./scripts/test_e2_sm.sh cust
./scripts/test_e2_kpm.sh
```

Consulte [E2_SERVICE_MODELS.md](../../../E2_SERVICE_MODELS.md) para interpretação dos logs.

---

## Entregáveis — Projeto 2 (40%, Aula 06)

### Mínimo (roteiro)

- Diagrama: OAI gNB ↔ FlexRIC ↔ xApp(s)
- Logs ou screenshots de associação E2 e subscription KPM (`test_e2_kpm.sh`)
- [Plano de testes](04-projeto2-plano-testes.md) preenchido
- Relatório técnico reprodutível (2–3 páginas): E2SM, limitações RFSIM vs srsRAN ZMQ

### Extensão (escolher ao menos um eixo)

- xApp customizado, ou estudo aplicado (políticas, otimização near-RT)
- Integração conceitual com Non-RT / A1 (Aula 03)
- Apresentação na Aula 06, **20 min** por grupo

---

## Troubleshooting

| Sintoma | Ação |
|---------|------|
| `demo-oai` não encontrada | Subir core antes do gNB (`up_core.sh`) |
| E2 setup falha | Mesmas versões E2AP/KPM em OAI e FlexRIC; ver [E2_FLEXRIC.md](../../../E2_FLEXRIC.md) §8 |
| xApp em `Resending Setup Request` | `ls flexric-lib/libkpm_sm.so`; `./scripts/sync_flexric_lib.sh` |
| Crash KPM / `Unknown RAN function ID` | Usar `flexric-lib/` (não `/usr/local`); reiniciar RIC |
| Subscrição OK, sem métricas KPM | `KPM_TRAFFIC=1`; aguardar attach UE; slice 222/123 |
| Binários ausentes | `./scripts/build_e2.sh` |

---

## Referências

- [E2_FLEXRIC.md](../E2_FLEXRIC.md) · [E2_FLEXRIC técnico](../../../E2_FLEXRIC.md)
- OAI E2: `ric/code/oai-cn-gnb-e2/openairinterface5g/openair2/E2AP/README.md`
- NGO et al. §3 (FlexRIC) · §6 (validação) · Polese — E2/E2SM
