# Plano de integração — nonRT RIC + SMO + nearRT RIC (O-RAN SC) + pilha OAI

Documento de **planeamento e viabilidade** para o projeto `oai-cn-gnb-nonrt-nearrt`.

**Data:** Jun 2026  
**Estado atual do repositório:** lab OAI funcional com **nearRT-RIC FlexRIC** (Fase 1), **nonRT RIC com A1 simulators** (Fase 1), base **nearRT O-RAN SC + A1 real** (Fase 2) e scaffold inicial **SMO/OAM** (Fase 3).

---

## 1. Resumo executivo

| Pergunta | Resposta |
|----------|----------|
| É possível integrar nonRT RIC O-RAN SC + SMO + nearRT + OAI? | **Sim**, com arquitetura em camadas e decisões explícitas |
| O lab atual já cobre o quê? | Core 5G OAI + gNB E2 + **FlexRIC nearRT**, xApps, **nonRT PMS/A1 simulators** e base **O-RAN SC nearRT/A1** |
| O que falta para “stack O-RAN completa”? | Fechar SMO/OAM com O1 simulado/TEIV e evoluir closed loop rApp -> A1 -> xApp |
| FlexRIC substitui nearRT O-RAN SC? | **Parcialmente** (E2/xApps). **Não** expõe A1 nem O1 — insuficiente para SMO↔nearRT |
| Kind / Kubernetes obrigatório? | **Não** para R&D mínimo; **sim** para deploy “oficial” M-release (it/dep `smo-install`) |
| Recomendação para este projeto | **Abordagem em 3 fases** (secção 5), começando por Docker Compose no host |

---

## 2. Estado atual (`oai-cn-gnb-nonrt-nearrt`)

### O que já funciona (validado no clone)

```
Core OAI (Docker, UPF-VPP)  →  gNB/nrUE RFSIM (host)  →  E2AP :36421  →  FlexRIC nearRT-RIC (host)
                                                                    →  xApps (KPM, RC, custom SMs)
```

| Componente | Tecnologia | Porta / path |
|------------|------------|--------------|
| 5G Core | `oai-cn5g-fed` Docker Compose | `demo-oai` 192.168.70.0/24 |
| RAN | OAI `nr-softmodem` + E2 agent | `--e2_agent.sm_dir flexric-lib/` |
| nearRT-RIC | FlexRIC submodule `dev` | SCTP **36421**, E42 **36422** |
| SMs | `flexric-lib/*.so` | KPM v2.03, RC, MAC/RLC/PDCP/GTP |

### O que existe por fase

| Fase | Implementado | Principais artefatos |
|------|--------------|----------------------|
| Fase 1 | nonRT RIC com A1 simulators + FlexRIC E2/xApps | `config/nonrtric/`, `up_e2_lab.sh`, `test_nonrt_ric.sh`, `explore_e2_sm.sh` |
| Fase 2 | nearRT O-RAN SC base + A1 Mediator + gNB E2 `:36422` | `config/oran-ric/`, `up_oai_oran_lab.sh`, `build_e2_oran_sc.sh`, `test_oran_ric.sh` |
| Fase 3 | Scaffold SMO/OAM isolado | `config/smo/env.example`, `up_smo_lab.sh`, `test_smo_lab.sh`, `docs/FASE3_SMO_OAM.md` |

### Lacunas atuais

- rApps reais consumindo KPM e emitindo policies A1 de forma automatizada.
- O1 real no gNB OAI monolítico.
- SMO/OAM completo embutido no repositório; a Fase 3 usa checkout externo via `SMO_OAM_DIR`.
- TEIV/topologia completa validada end-to-end.

---

## 3. Arquitetura O-RAN alvo

```
┌─────────────────────────────────────────────────────────────────────────┐
│  SMO (Service Management & Orchestration)                               │
│  OAM · TEIV · VES · NETCONF/O1 · (opcional) rApps                       │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │ O1
┌───────────────────────────────▼─────────────────────────────────────────┐
│  nonRT RIC (O-RAN SC)                                                   │
│  Policy Mgmt (PMS) · Information Service · Control Panel · A1 Simulator │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │ A1 (policy / enrichment / ML models)
┌───────────────────────────────▼─────────────────────────────────────────┐
│  nearRT RIC (O-RAN SC ricplt OU FlexRIC*)                               │
│  E2 Termination · Subscription Manager · xApp runtime                    │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │ E2AP SCTP
┌───────────────────────────────▼─────────────────────────────────────────┐
│  E2 Node — OAI gNB (E2 agent) + opcional O-DU simulators (O1)             │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │ NGAP / GTP-U
┌───────────────────────────────▼─────────────────────────────────────────┐
│  5G Core OAI (AMF/SMF/UPF-VPP) — já existente                           │
└─────────────────────────────────────────────────────────────────────────┘

* FlexRIC: válido para E2/xApps; **sem A1** → não fecha o triângulo SMO–nonRT–nearRT
```

### Interfaces relevantes

| Interface | Entre | Protocolo típico | No lab atual |
|-----------|-------|------------------|--------------|
| **E2** | nearRT ↔ gNB | SCTP (36421 FlexRIC / **36422** O-RAN SC) | ✅ FlexRIC |
| **A1** | nonRT ↔ nearRT | REST/gRPC (policy, enrichment) | ❌ |
| **O1** | SMO ↔ RAN/nearRT | NETCONF / HTTP | ❌ |
| **O2** | SMO ↔ cloud/K8s | K8s API | ❌ (fora de escopo inicial) |

---

## 4. Viabilidade técnica — evidências

### 4.1 OAI gNB ↔ nearRT O-RAN SC (E2)

Documentado no upstream OAI (`openairinterface5g/openair2/E2AP/README.md` §5):

- Porta E2AP O-RAN SC: **36422** (FlexRIC usa 36421)
- Recompilar gNB com `e2ap_server_port=36422`
- Integrações demonstradas: **H-release** (kpm_rc-xapp), **J-release** (xDevSM)
- KPM/RC SMs do FlexRIC reutilizados no xDevSM (só E2AP é validado entre agente e ricplt)

**Conclusão:** viável; exige **trocar ou paralelizar** nearRT (FlexRIC → ricplt ou `oran-sc-ric`).

### 4.2 nearRT O-RAN SC sem Kubernetes

Repositório comunitário **[srsran/oran-sc-ric](https://github.com/srsran/oran-sc-ric)**:

- nearRT ricplt **i-release** em **Docker Compose** (7 containers)
- Routing Manager simulado (`rtmgr_sim`) — sem K8s
- xApps Python de exemplo (KPM, RC)
- Usado no tutorial srsRAN Project para nearRT + gNB

**Conclusão:** melhor candidato para nearRT O-RAN SC **no mesmo host** que o gNB OAI, sem Kind.

### 4.3 nonRT RIC O-RAN SC

Fontes oficiais:

- Repositório: `gerrit.o-ran-sc.org/r/nonrtric`
- Deploy preferido: **Helm** via `it/dep` → `smo-install` (flavour `standalone-nonrtric`)
- Deploy R&D: **Docker Compose** em `nonrtric/docker-compose/` + integração OAM (`smo/non-rt-ric/docker-compose.yml`)

Componentes principais (M-release):

| Componente | Função |
|------------|--------|
| **PMS** | Policy Management Service (A1 policies) |
| **A1 Simulator** | Simula nearRT para testes A1 sem ricplt real |
| **Information Service** | Metadados / discovery |
| **Control Panel** | UI de gestão |
| **Topology / DMAAP** | Integração com ecossistema ONAP/SMO |

**Conclusão:** viável em Docker Compose para lab; stack completa pede **≥16 GB RAM** e vários serviços (Kafka, Kong, PostgreSQL, …).

### 4.4 SMO (OAM)

Fontes: `o-ran-sc/oam` — deploy Docker Compose para R&D:

```bash
docker compose -f infra/docker-compose.yaml up -d
docker compose -f smo/common/docker-compose.yaml up -d    # Kafka, Keycloak, Zookeeper
docker compose -f smo/oam/docker-compose.yaml up -d     # SDNC, VES collector
docker compose -f network/docker-compose.yaml up -d     # Simuladores O-DU/O-RU (opcional)
```

SMO L-release inclui **TEIV** (Topology Exposure) em compose separado (`smo/teiv`).

**Conclusão:** viável em Docker; ordem de arranque importa (Keycloak primeiro). O1 real com gNB OAI monolítico é **limitado** — OAM target são O-DU/O-RU simulados (`ntsim-ng`).

### 4.5 FlexRIC + nonRT RIC em paralelo?

| Cenário | A1 real? | E2 OAI? | Complexidade |
|---------|----------|---------|--------------|
| FlexRIC nearRT + nonRT com A1 Simulator | Simulado apenas | ✅ porta 36421 | Baixa — **Fase 1** |
| `oran-sc-ric` nearRT + nonRT PMS | ✅ possível | ✅ porta 36422 | Média — **Fase 2** |
| ricplt K8s + it/dep smo-install full | ✅ produção | ✅ | Alta — **Fase 3** |

**FlexRIC não implementa A1.** Para políticas A1 reais no nearRT, é necessário **ricplt** (Docker ou K8s).

---

## 5. Estratégia recomendada — 3 fases

### Fase 1 — nonRT RIC isolado + lab E2 existente (2–3 dias)

**Objetivo:** Subir nonRT RIC O-RAN SC sem alterar o nearRT FlexRIC já validado.

| Item | Ação |
|------|------|
| nonRT RIC | Clone `nonrtric`, `docker compose` (PMS + Control Panel + A1 Simulator) |
| Rede | Bridge Docker `oran-mgmt` + host gateway para A1 Simulator |
| OAI + E2 | Manter `up_e2_lab.sh` inalterado |
| Validação | UI Control Panel; REST PMS; A1 Simulator health |

**Entregáveis:** `scripts/up_nonrt_ric.sh`, `scripts/down_nonrt_ric.sh`, `scripts/test_nonrt_ric.sh`, `config/nonrtric/`, `docs/NONRT_RIC.md` — **implementado**

**Limitação:** A1 Simulator não fala com FlexRIC — apenas prova nonRT RIC.

---

### Fase 2 — nearRT O-RAN SC + E2 OAI + A1 (1–2 semanas)

**Objetivo:** Stack nearRT+nonRT O-RAN SC com E2 real no gNB OAI.

| Item | Ação |
|------|------|
| nearRT | Integrar `srsran/oran-sc-ric` (Docker Compose) ou ricplt mínimo |
| gNB | Rebuild E2 com **porta 36422**; apontar `near_ric_ip_addr` para container/host |
| nonRT | Configurar PMS → A1 endpoint do ricplt (não simulator) |
| xApps | Python KPM/RC do `oran-sc-ric` ou xDevSM |
| FlexRIC | Desativar nearRT FlexRIC neste modo (`RIC_STACK=oran-sc`) |

**Entregáveis:** `vendor/oran-sc-ric`, `config/oran-ric/`, `scripts/up_oran_ric.sh`, `up_oai_oran_lab.sh`, `build_e2_oran_sc.sh`, `docker-compose.oran.yml`, `docs/ORAN_RIC_FASE2.md` — **implementado (base)**

**Risco:** versões E2AP/KPM entre OAI, ricplt e xApps devem alinhar (testar H ou J release).

**Nota:** Fase 1 inalterada — perfis separados (`up_e2_lab.sh` vs `up_oai_oran_lab.sh`).

---

### Fase 3 — SMO OAM + topologia completa (2–4 semanas)

**Objetivo:** SMO deployado; O1 com simuladores; visão “management plane” integrada.

| Item | Ação |
|------|------|
| SMO common | Kafka + Keycloak + Zookeeper (`smo/common`) |
| SMO OAM | SDNC + VES collector (`smo/oam`) |
| TEIV (opcional) | Topology inventory L-release |
| Simuladores | `ntsim-ng` O-DU/O-RU para O1 (`network/`) |
| Orquestração | `up_smo_lab.sh` com ordem de dependências |

**Limitação:** gNB OAI monolítico **não** expõe O1 NETCONF nativo — O1 será com simuladores, não com o gNB real.

**Alternativa produção:** `it/dep` `smo-install` em cluster K8s dedicado (não multicluster Kind do SD-RAN).

---

## 6. Recursos e pré-requisitos

### Hardware mínimo estimado

| Fase | RAM | CPU | Disco |
|------|-----|-----|-------|
| Atual (Core + FlexRIC + gNB) | 8 GB | 4 cores | 15 GB |
| + Fase 1 (nonRT) | 12 GB | 6 cores | 25 GB |
| + Fase 2 (oran-sc-ric) | 16 GB | 8 cores | 35 GB |
| + Fase 3 (SMO full) | 24–32 GB | 8+ cores | 50 GB |

### Software

- Docker 24+ / Compose v2
- (Fase 3+) Python 3 para scripts OAM `config.py`
- (Opcional Fase 3 K8s) cluster single-node Kind ou k3s — **separado** do lab SD-RAN

### Portas a reservar

| Serviço | Porta(s) |
|---------|----------|
| FlexRIC E2AP | 36421 |
| O-RAN SC E2AP | **36422** |
| E42 / xApp (FlexRIC) | 36422 (conflito nome — hosts distintos ou stacks mutuamente exclusivos) |
| A1 (PMS) | 8080, 8433 (varia por release) |
| SMO Keycloak | 8080 (conflito — usar profiles ou portas remapeadas) |
| Kafka | 9092 |

> **Importante:** FlexRIC e `oran-sc-ric` **não devem** correr em simultâneo na mesma máquina sem remapear portas — usar perfis `RIC_STACK=flexric|oran-sc`.

---

## 7. Decisões de projeto

| # | Decisão | Recomendação |
|---|---------|--------------|
| D1 | nearRT: FlexRIC vs O-RAN SC | **Coexistir por perfil** — FlexRIC para dev E2 rápido; `oran-sc-ric` para stack A1 |
| D2 | Kubernetes | **Evitar** no host do lab OAI; usar Docker Compose até Fase 3; K8s só se SMO full |
| D3 | Kind multicluster | **Não integrar** com `charmed-aether-sd-ran` (requisito anterior do projeto) |
| D4 | SMO scope | Fase 3: OAM + simuladores O1; **não** prometer O1 no gNB OAI monolítico |
| D5 | Release O-RAN SC | Alinhar numa release: **I/J** para `oran-sc-ric`; **M** para nonRT `it/dep` |
| D6 | E2AP version | Manter `E2AP_V2` + `KPM_V2_03` (lab atual) até validar matriz com ricplt |

---

## 8. Matriz de compatibilidade (resumo)

| Componente A | Componente B | Compatível? | Notas |
|--------------|--------------|-------------|-------|
| OAI E2 agent | FlexRIC nearRT | ✅ Validado | porta 36421 |
| OAI E2 agent | O-RAN SC ricplt | ✅ Documentado | porta **36422**, rebuild |
| OAI E2 agent | ONOS SD-RAN nearRT | ⚠️ Não testado aqui | outro stack (Helm/k8s) |
| FlexRIC nearRT | nonRT A1 PMS | ❌ | Sem A1 no FlexRIC |
| oran-sc-ric nearRT | nonRT PMS | ✅ Esperado | configurar A1 endpoint |
| SMO OAM | gNB OAI | ⚠️ Parcial | O1 via simuladores, não gNB real |
| SMO OAM | nonRT RIC | ✅ | via `it/dep` / compose integrado |

---

## 9. Roadmap de implementação no repositório

```
Semana 1
├── docs/FASE1_NONRT_FLEXRIC.md
├── config/nonrtric/
├── scripts/up_nonrt_ric.sh / down_nonrt_ric.sh
├── scripts/test_nonrt_ric.sh / explore_nonrt_ric.sh
└── Validado PMS + Control Panel + A1 Simulator

Semana 2–3
├── docs/FASE2_ORAN_SC_A1.md
├── Integrar srsran/oran-sc-ric (submodule/vendor externo)
├── scripts/build_e2_oran_sc.sh (E2AP :36422)
├── scripts/up_oran_ric.sh
├── scripts/up_oai_oran_lab.sh
├── Wire A1: nonRT PMS → ricplt A1 endpoint
└── Teste E2 KPM com xApp oran-sc-ric

Semana 4+
├── docs/FASE3_SMO_OAM.md
├── scripts/up_smo_lab.sh / down_smo_lab.sh / test_smo_lab.sh
├── config/smo/env.example
├── Integrar checkout O-RAN SC OAM via SMO_OAM_DIR
├── Validar topologia O1 + ntsim-ng
└── (Opcional) PoC it/dep standalone-nonrtric em Kind isolado
```

---

## 10. Referências

| Recurso | URL |
|---------|-----|
| OAI E2AP + O-RAN SC interoperability | `openairinterface5g/openair2/E2AP/README.md` §5 |
| FlexRIC + OSC nearRT | `openairinterface5g/openair2/E2AP/flexric/README.md` §6.1 |
| nonRT RIC install guide | https://docs.o-ran-sc.org/projects/o-ran-sc-nonrtric/en/latest/installation-guide.html |
| nonRT M-release K8s | https://lf-o-ran-sc.atlassian.net/wiki/spaces/RICNR/pages/679903652 |
| it/dep smo-install | https://gerrit.o-ran-sc.org/r/admin/repos/it/dep |
| ricplt ric-dep | https://docs.o-ran-sc.org/projects/o-ran-sc-ric-plt-ric-dep/en/latest/ |
| oran-sc-ric (Docker, sem K8s) | https://github.com/srsran/oran-sc-ric |
| SMO OAM deploy | https://docs.o-ran-sc.org/projects/o-ran-sc-oam/en/latest/deployment.html |
| NIST TN 2311 (blueprint testbeds) | https://nvlpubs.nist.gov/nistpubs/TechnicalNotes/NIST.TN.2311.pdf |
| Lab E2 atual | `docs/TUTORIAL_LAB_E2.md` |

---

## 11. Conclusão

A integração **é viável e faz sentido** neste repositório, com estas condições:

1. **Não é um único `docker compose up`** — são 3 planos (Core, RIC/SMO, RAN host) coordenados por scripts.
2. **“Stack completa” O-RAN** (SMO + nonRT + nearRT + A1 + E2) exige **substituir FlexRIC por nearRT O-RAN SC** na Fase 2; FlexRIC sozinho não fecha A1.
3. **SMO com O1 real no gNB OAI** não é realista no curto prazo; usar simuladores O-DU ou documentar como limitação.
4. **Kind multicluster** do projeto SD-RAN permanece **fora de escopo**; K8s só se necessário para `it/dep` full, em cluster **isolado**.
5. O caminho de **menor risco** permanece por fases isoladas: Fase 1 para FlexRIC/nonRT simulado, Fase 2 para O-RAN SC/A1 real e Fase 3 para SMO/OAM.

**Próximo passo sugerido:** fixar o checkout/release O-RAN SC OAM usado por `SMO_OAM_DIR`, validar `test_smo_lab.sh --preflight` e depois adicionar um teste O1 mínimo com simuladores.
