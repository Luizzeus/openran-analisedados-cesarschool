# Laboratórios — free5GC + srsRAN (Interfaces e Protocolos)

Roteiros para execução em sala ou autonomamente e para elaboração do **relatório de entrega**.

## Mapa rápido: core + três RANs

| Cenário | Pasta | Roteiro | Ideia principal |
|---------|--------|---------|-----------------|
| **Core 5GC** apenas | `core/` | [01](01-core-5gc.md) | NRF, AMF, SMF, UPF, subscriber |
| **gNB tradicional** (monólito) | `gNB_traditional/` | [02](02-ran-tradicional-n2-n3.md) | Um container `gnb`; N2/N3; srsUE opcional (ZMQ) |
| **gNB desagregado** (split CU/DU, F1) | `gNB_disaggregated/` | [03](03-ran-aberta-cu-du.md) | Dois containers; N2 no CU; F1 entre CU e DU |
| **gNB aberto** O-RAN (CU/DU + **Open Fronthaul**) | `gNB_open/` | [05](05-ran-open-fronthaul-o-ran.md) | CU + DU + **RU emulada**; rede `ofhnet` |

**Nota:** `gNB_disaggregated` e `gNB_open` **não** podem estar ativos ao mesmo tempo (mesmos nomes de contentores e IPs `.51`/`.52` na `free5gc-privnet`). O monolítico `gNB_traditional` pode coexistir com um deles (IDs e portas ZMQ distintos).

| Documento | Conteúdo |
|-----------|----------|
| [00 — Demo rápida: core + 3 RANs](00-demo-rapido-3-rans.md) | Passo a passo curto para demonstração em sala (tradicional, desagregada e aberta) |
| [01 — Infraestrutura e Core 5G](01-core-5gc.md) | Docker, subida do core, subscriber, verificações iniciais |
| [02 — RAN tradicional e interfaces N2/N3](02-ran-tradicional-n2-n3.md) | gNB monolítico, NGAP, GTP-U, E2E com UE, capturas N2/N3 obrigatórias |
| [03 — RAN desagregada (CU/DU, F1)](03-ran-aberta-cu-du.md) | Split em dois containers; comparação com o tradicional |
| [Relatório, entrega e avaliação](04-relatorio-entrega-avaliacao.md) | O que entregar, prints/logs obrigatórios, rubrica |
| [05 — RAN aberta O-RAN (Open Fronthaul)](05-ran-open-fronthaul-o-ran.md) | CU + DU + RU emulada; rede dedicada DU–RU |

**Pré-requisitos:** Linux com Docker e Docker Compose v2, usuário com permissão para `docker` (e eventualmente `sudo` para tcpdump nos roteiros avançados).

**Raiz do projeto (convenção nos comandos):** `free5gc-containerized/` — ajuste os `cd` se o seu clone estiver em outro caminho.
