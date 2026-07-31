# RAN aberta (Open Networks / ORAN Alliance — split CU / DU — F1/E1 + Open Fronthaul)

Dois containers na rede `free5gc-privnet`:

| Container | IP | Binário |
|-----------|-----|---------|
| `srsran-cu` | 10.100.200.51 (N2 / NG-U) + **10.100.200.61** (F1-U, via `entrypoint-cu.sh`) | `srscu` — N2 para AMF + F1-C/F1-U |
| `srsran-du` | 10.100.200.52 | `srsdu` — F1 + `ru_dummy` **ou** RU ZMQ (srsUE) |

## Open Fronthaul (O-RAN) — RU emulada (sem hardware)

Além da rede `free5gc-privnet`, este projeto cria uma rede Docker dedicada ao fronthaul (L2):

- `ofhnet` (bridge): liga **DU** ↔ **RU emulada** (confira pelas MACs do OFH: DU `02:00:00:00:01:02`, RU `02:00:00:00:01:01`)
- Serviço RU: `srsran-ru` (binário `ru_emulator` do srsRAN Project)

O perfil do DU para Open Fronthaul está em `configs/du-ofh-ru-emulator.yml` (seção `ru_ofh`).

### Fluxo recomendado (manual)

1. `bash ./scripts/up.sh` (sobe CU, DU e RU containers em modo *idle*)
2. `bash ./scripts/start-cu.sh`
3. (opcional) `bash ./scripts/verify-ofh.sh` (confere as interfaces/MACs do link OFH)
4. `bash ./scripts/start-ru-emulator.sh`
5. `bash ./scripts/start-du-ofh.sh` (DU com `ru_ofh` + RU emulada)

### Fluxo recomendado (automático)

```bash
DU_CONFIG=du-ofh-ru-emulator.yml CU_AUTO_START=1 DU_AUTO_START=1 RU_AUTO_START=1 bash ./scripts/up.sh
```

O `srsran-cu` inicia `srscu`, o `srsran-ru` inicia `ru_emulator`, e o `srsran-du` inicia `srsdu` com `ru_ofh`.

**Rotina de conexão (AMF ↔ CU ↔ DU) e onde ver logs:** [docs/CU_DU_CONEXAO.md](docs/CU_DU_CONEXAO.md).

O **NG-U** e o **F1-U** usam UDP **2152** por defeito; no mesmo IP isso gera *bind* duplicado. O entrypoint adiciona **10.100.200.61/24** em `eth0` para o F1-U; o **NG-U** fica em **10.100.200.51** (N3).  
No `cu.yml`, `ran_node_name` / `gnb_id` / `gnb_id_bit_length` ficam no **nível raiz** (não dentro de `cu_cp`): ver [config reference](https://docs.srsran.com/projects/project/en/latest/user_manuals/source/config_ref.html#manual-config-ref).

## Defeito: **CU e DU manuais** (`CU_AUTO_START=0`, `DU_AUTO_START=0`)

`bash ./scripts/up.sh` só levanta os contentores (rede, IPs, `tail` em *idle*). Os binários arrancam no host:

| Passo | Comando | Notas |
|-------|---------|--------|
| 1 | `bash ./scripts/start-cu.sh` | `srscu` → **N2** para o AMF (`10.100.200.51` nos logs). Ver `logs/cu.log`, `docker logs -f srsran-cu`. |
| 2 | `srsue configs/ue_srsue.conf` | Só com **ZMQ**; espere PHY *done* / «Attaching…». |
| 3 | `bash ./scripts/start-du-after-ue.sh` | Espera a porta **UL** em `configs/ue_srsue.conf` (defeito **2003**) e inicia `srsdu`. Ver [configs/ZMQ_PORTS.md](configs/ZMQ_PORTS.md). |

**Logs no disco:** `gNB_open/logs/cu.log`, `gNB_open/logs/du.log`.

**Variáveis de ambiente** (antes de `bash ./scripts/up.sh`):

- `CU_AUTO_START=1` — `srscu` no entrypoint do contentor CU.
- `DU_AUTO_START=1` — `srsdu` no entrypoint do contentor DU.
- `RU_AUTO_START=1` — `ru_emulator` no entrypoint do contentor RU (só relevante no modo Open Fronthaul).

Exemplo *tudo automático* (lab sem ordem manual):  
`CU_AUTO_START=1 DU_AUTO_START=1 DU_CONFIG=du.yml bash ./scripts/up.sh`

## Lab F1 com `ru_dummy` (sem srsUE)

Com arranque manual: `bash ./scripts/start-cu.sh` e depois `bash ./scripts/run-du.sh` (sem `start-du-after-ue.sh`).

Com arranque automático nos contentores:

```bash
DU_CONFIG=du.yml CU_AUTO_START=1 DU_AUTO_START=1 bash ./scripts/up.sh
```

## srsUE + ZMQ

**Ordem obrigatória:** **CU → srsUE → DU** (`start-du-after-ue.sh`). O **srsUE** tem de estar a correr **antes** do `srsdu`; caso contrário o ZMQ UL não estabelece e o UE fica em «Attaching…». O script verifica `pgrep srsue`.

1. **Portas:** gNB_open usa **2002/2003** (DL/UL) para não colidir com o monolítico **2000/2001**. Tudo tem de estar alinhado: `du-zmq-srsue.yml`, `ue_srsue.conf`, `docker-compose` (`2002:2002`), `start-du-after-ue.sh` (defeito UL **2003**). Detalhe: [configs/ZMQ_PORTS.md](configs/ZMQ_PORTS.md).
2. `bash ./scripts/up.sh`
3. `bash ./scripts/start-cu.sh`
4. **`srsue configs/ue_srsue.conf`** (outro terminal — **não** pare antes do passo 5)
5. `bash ./scripts/start-du-after-ue.sh`

Pode manter o **gNB tradicional** a correr em paralelo (portas diferentes). **Dois srsUE** com o **mesmo IMSI** no mesmo core não são suportados — use outro subscritor ou pare um dos UEs.

Equivalente sem espera na porta UL: `bash ./scripts/run-du.sh` (depois do UE à escuta).  
**Não** arranque o `srsdu` só com `docker exec … -c /etc/srsran/du-zmq-srsue.yml` no Linux — falta a substituição do `host.docker.internal` pelo gateway (feita pelos scripts). Diagnóstico: `bash ./scripts/diagnose-zmq.sh`.

### `configs/ue_srsue.conf`

Inclui **`dl_earfcn` em `[rat.eutra]`** e **`tx_port0`/`rx_port0`** para **um** canal ZMQ — consola: **`Opening 1 channels`**.

**Célula / RF:** `configs/du-zmq-srsue.yml` — **band 3**, **SCS 15 kHz**, **PCI 1**. **Global gNB ID** **412** no `cu.yml`.

### N2 instável no AMF

[docs/TROUBLESHOOTING_N2.md](docs/TROUBLESHOOTING_N2.md)
