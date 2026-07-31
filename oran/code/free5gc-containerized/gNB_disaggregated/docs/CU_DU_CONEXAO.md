# Rotina de conexão: CU, DU e o que o AMF mostra

## Visão geral

No *split* F1, o **CU** (Central Unit) e o **DU** (Distributed Unit) são processos separados. O **AMF** só fala com o **CU**, na interface **N2** (SCTP + **NGAP**). O **DU** liga-se ao **CU** na **F1** (F1-C / F1-U), não ao AMF.

```
  [AMF]  ←—— N2 (SCTP/NGAP) ——→  [CU srscu : 10.100.200.51]
                                      ↑
                                      │ F1 (F1AP + GTP-U)
                                      ↓
                                 [DU srsdu : 10.100.200.52]
                                      ↑
                                      │ ZMQ (lab RF) ou RU
                                      ↓
                                   [srsUE no host]
```

## O que significam os logs do AMF

Exemplo:

```text
SCTP Accept from: 10.100.200.51:52511
Create a new NG connection for: 10.100.200.51:52511
Handle NGSetupRequest
Send NG-Setup response
```

- **10.100.200.51** é o IP do **CU** (`srsran-cu`) na rede Docker.
- O **cliente SCTP** é o **srscu**: abre o **porto local efémero** (ex.: `52511`) e liga-se ao **AMF** na **38412** (porto de servidor NGAP).
- **NGSetupRequest / NG-Setup response** = troca inicial NGAP; confirma que **N2** está de pé entre CU e core. Isto **não** prova que o **DU** já tenha estabelecido **F1** (isso vê-se nos logs do CU/DU).

## Ordem típica de arranque (manual)

1. **Core** (AMF, SMF, UPF, …) na `free5gc-privnet`.
2. **CU** (`srscu`): regista-se no AMF (N2) e fica à escuta para **F1** (lado CU).
3. **DU** (`srsdu`): liga ao **CU-CP** (ex.: `10.100.200.51`), **F1 Setup**, depois tráfego de utilizador conforme **RU** (dummy ou ZMQ).
4. Com **ZMQ + srsUE**: o UE no *host* precisa de estar coerente com o **RU** no DU (portas e *sample rate*).

## Como ver se CU e DU estão “saudáveis”

### CU

- **Consola do processo** (se arrancou com `docker exec -it srsran-cu …`): mensagens de *N2 connected*, *NG Setup*, *F1* à escuta.
- **Arquivo de log** (montado em `gNB_disaggregated/logs/`):

```bash
tail -f gNB_disaggregated/logs/cu.log
```

- **Contentor Docker** (stdout do `srscu`):

```bash
docker logs -f srsran-cu
```

- **NGAP em PCAP** (se ativo no `cu.yml`): `gNB_disaggregated/logs/cu_ngap.pcap`.

### DU

```bash
tail -f gNB_disaggregated/logs/du.log
docker logs -f srsran-du
```

Procure **F1 Setup** / ligação ao CU, erros **FATAL**/**ERROR**, e, com ZMQ, mensagens do **RU** / **PHY**.

### AMF

- **NG Setup** estável → N2 OK.
- Quedas de **SCTP** / **bad file descriptor** a seguir a registo → investigar N2 ou compatibilidade NGAP (ver `TROUBLESHOOTING_N2.md`).

## Resumo

| Onde | O quê |
|------|--------|
| AMF | Só **N2** com o **CU** (IP `10.100.200.51`). |
| `cu.log` / `docker logs srsran-cu` | N2 + **F1** (lado CU). |
| `du.log` / `docker logs srsran-du` | **F1** + **RU** (ZMQ ou dummy). |

Não há linha “DU” nos logs do AMF; o DU é **transparente** para o AMF.
