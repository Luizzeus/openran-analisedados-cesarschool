# RAN desagregada (split CU / DU — F1 e E1)

Dois containers na rede `free5gc-privnet`:

| Container | IP | Binário |
|-----------|-----|---------|
| `srsran-cu` | 10.100.200.51 (N2 / NG-U) + **10.100.200.61** (F1-U, via `entrypoint-cu.sh`) | `srscu` — N2 para AMF + F1-C/F1-U |
| `srsran-du` | 10.100.200.52 | `srsdu` — F1 + `ru_dummy` **ou** RU ZMQ (srsUE) |

**Rotina de conexão (AMF ↔ CU ↔ DU) e onde ver logs:** [docs/CU_DU_CONEXAO.md](docs/CU_DU_CONEXAO.md).

O **NG-U** e o **F1-U** usam UDP **2152** por defeito; no mesmo IP isso gera *bind* duplicado. O entrypoint adiciona **10.100.200.61/24** em `eth0` para o F1-U; o **NG-U** fica em **10.100.200.51** (N3).  
No `cu.yml`, `ran_node_name` / `gnb_id` / `gnb_id_bit_length` ficam no **nível raiz** (não dentro de `cu_cp`): ver [config reference](https://docs.srsran.com/projects/project/en/latest/user_manuals/source/config_ref.html#manual-config-ref).

## Defeito: **CU e DU manuais** (`CU_AUTO_START=0`, `DU_AUTO_START=0`)

`./scripts/up.sh` só levanta os contentores (rede, IPs, `tail` em *idle*). Os binários arrancam no host:

| Passo | Comando | Notas |
|-------|---------|--------|
| 1 | `./scripts/start-cu.sh` | `srscu` → **N2** para o AMF (`10.100.200.51` nos logs). Ver `logs/cu.log`, `docker logs -f srsran-cu`. |
| 2 | `srsue configs/ue_srsue.conf` | Só com **ZMQ**; espere PHY *done* / «Attaching…». |
| 3 | `./scripts/start-du-after-ue.sh` | Espera a porta **UL** em `configs/ue_srsue.conf` (defeito **2003**) e inicia `srsdu`. Ver [configs/ZMQ_PORTS.md](configs/ZMQ_PORTS.md). |

**Logs no disco:** `gNB_disaggregated/logs/cu.log`, `gNB_disaggregated/logs/du.log`.

**Variáveis de ambiente** (antes de `./scripts/up.sh`):

- `CU_AUTO_START=1` — `srscu` no entrypoint do contentor CU.
- `DU_AUTO_START=1` — `srsdu` no entrypoint do contentor DU.

Exemplo *tudo automático* (lab sem ordem manual):  
`CU_AUTO_START=1 DU_AUTO_START=1 DU_CONFIG=du.yml ./scripts/up.sh`

## Lab F1 com `ru_dummy` (sem srsUE)

Com arranque manual: `./scripts/start-cu.sh` e depois `./scripts/run-du.sh` (sem `start-du-after-ue.sh`).

Com arranque automático nos contentores:

```bash
DU_CONFIG=du.yml CU_AUTO_START=1 DU_AUTO_START=1 ./scripts/up.sh
```

## srsUE + ZMQ

**Ordem obrigatória:** **CU → srsUE → DU** (`start-du-after-ue.sh`). O **srsUE** tem de estar a correr **antes** do `srsdu`; caso contrário o ZMQ UL não estabelece e o UE fica em «Attaching…». O script verifica `pgrep srsue`.

1. **Portas:** gNB_disaggregated usa **2002/2003** (DL/UL) para não colidir com o monolítico **2000/2001**. Tudo tem de estar alinhado: `du-zmq-srsue.yml`, `ue_srsue.conf`, `docker-compose` (`2002:2002`), `start-du-after-ue.sh` (padrão UL **2003** para gNB_disaggregated). Detalhe: [configs/ZMQ_PORTS.md](configs/ZMQ_PORTS.md).
2. `./scripts/up.sh`
3. `./scripts/start-cu.sh`
4. **`srsue configs/ue_srsue.conf`** (outro terminal — **não** pare antes do passo 5)
5. `./scripts/start-du-after-ue.sh`

Pode manter o **gNB tradicional** a correr em paralelo (portas diferentes). **Dois srsUE** com o **mesmo IMSI** no mesmo core não são suportados — use outro subscritor ou pare um dos UEs.

Equivalente sem espera na porta UL: `./scripts/run-du.sh` (depois do UE à escuta).  
**Não** arranque o `srsdu` só com `docker exec … -c /etc/srsran/du-zmq-srsue.yml` no Linux — falta a substituição do `host.docker.internal` pelo gateway (feita pelos scripts). Diagnóstico: `./scripts/diagnose-zmq.sh`.

### `configs/ue_srsue.conf`

Inclui **`dl_earfcn` em `[rat.eutra]`** e **`tx_port0`/`rx_port0`** para **um** canal ZMQ — consola: **`Opening 1 channels`**.

**Célula / RF:** `configs/du-zmq-srsue.yml` — **band 3**, **SCS 15 kHz**, **PCI 1**. **Global gNB ID** **412** no `cu.yml`.

### N2 instável no AMF

[docs/TROUBLESHOOTING_N2.md](docs/TROUBLESHOOTING_N2.md)
