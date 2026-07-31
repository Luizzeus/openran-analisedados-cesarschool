# Portas ZMQ (gNB_disaggregated vs gNB_traditional)

Para correr **gNB monolítico** e **CU/DU** em paralelo no mesmo host, usam-se pares TCP distintos:

| Pilha | DL (UE `rx` ← gNB `tx`) | UL (UE `tx` → gNB `rx`) | `docker-compose` publica |
|-------|-------------------------|-------------------------|---------------------------|
| `gNB_traditional` | **2000** | **2001** | `2000:2000` |
| `gNB_disaggregated` (DU) | **2002** | **2003** | `2002:2002` (só o **DL**; ver nota abaixo) |

**Nota:** o compose **não** expõe a porta **2003** no contentor. A **2003** é onde o **srsUE no host** escuta (UL); o DU **abre ligação de saída** para `host.docker.internal` ou para o **gateway** da bridge Docker (`lib-zmq-du-runtime.sh`). Por isso “falta” `2003:2003` no `docker-compose` — não é omissão, é o modelo ZMQ deste lab.

O `rx_port` do DU usa `host.docker.internal` no YAML; em **Linux**, `./scripts/start-du-after-ue.sh` e `./scripts/run-du.sh` geram um YAML temporário com o **Gateway IPv4** da rede `free5gc-privnet` (tráfego UL para o srsUE no host). Se arrancar o `srsdu` só com `docker exec` e o ficheiro montado, pode falhar — use os scripts ou `./scripts/diagnose-zmq.sh`.

Têm de estar alinhados:

- `configs/du-zmq-srsue.yml` → `ru_sdr.device_args`
- `configs/ue_srsue.conf` → `[rf] device_args`
- `./scripts/start-du-after-ue.sh` → `UE_ZMQ_UL_PORT` (padrão **2003** para gNB_disaggregated)

**IMSI:** dois srsUE com o mesmo IMSI no mesmo core causam conflito. Para testar os dois ao mesmo tempo, use outro subscritor/IMSI no segundo `ue_srsue.conf` ou pare um dos UEs.
