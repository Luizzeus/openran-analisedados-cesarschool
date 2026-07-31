# Conectar UE (srsUE) ao Lab 5G SA

Este lab usa **srsRAN Project gNB** e **free5GC**. O UE compatível é o **srsUE** (srsRAN 4G), ligado ao gNB via **ZMQ** (rádio virtual).

## srsUE e 5G: teste E2E adequado?

**Sim.** O srsUE (repositório srsRAN 4G) suporta **5G NR em modo Standalone (SA)** desde a versão 22.04. A pilha completa **srsUE (5G) ↔ srsRAN Project gNB ↔ free5GC** constitui um **teste end-to-end 5G SA** válido:

- **Plano de controle:** registro 5G (NAS), NGAP (N2), autenticação 5G-AKA, estabelecimento de sessão PDU.
- **Plano de dados:** GTP-U (N3), atribuição de IP ao UE, tráfego (ping, iperf) pela core 5G.

A documentação oficial descreve cenários equivalentes (srsUE + core 5G + ZMQ), por exemplo:

- [5G SA End-to-End](https://docs.srsran.com/projects/4g/en/latest/app_notes/source/5g_sa_E2E/source/index.html) (srsRAN 4G com Open5GS e ZMQ).
- [5G SA srsUE](https://docs.srsran.com/projects/4g/en/latest/app_notes/source/5g_sa_amari/source/index.html) (srsUE com rede 5G SA).

As limitações do srsUE (SCS 15 kHz, bandas FDD, 5–20 MHz) estão documentadas abaixo; o gNB deve usar a config ZMQ em banda FDD (`gnb-zmq-srsue.yml`).

---

## Pré-requisitos

- Core free5GC em execução (AMF, SMF, UPF, NRF, etc.)
- N2/NGAP estabelecido: `./scripts/validate-n2-ngap.sh` ou `./scripts/checklist-e2e.sh`
- Subscriber no MongoDB: `./scripts/add-subscriber.sh` (IMSI 208930000000001)
- gNB com **ZMQ** (config padrão: `gnb-zmq-srsue.yml`)

---

## Limitações do srsUE (5G SA)

- **SCS:** apenas 15 kHz (bandas FDD).
- **Largura de canal:** 5, 10, 15 ou 20 MHz.
- **Handover:** não suportado.

Por isso o gNB precisa estar em **banda FDD** (ex.: band 3) com **common_scs: 15** quando for usar srsUE.

---

## 1. Configuração do gNB para ZMQ

O padrão do container **srsran-gnb-tradicional** é **gnb-zmq-srsue.yml** (ZMQ para srsUE). No `docker-compose` publica-se **apenas a porta 2000** (DL do gNB → `127.0.0.1:2000` no host). **Não** mapeie `2001:2001`: isso reserva a 2001 no host e o srsUE não consegue fazer bind (`Address already in use`). O gNB faz **bind** em 2000 (no container) e **connect** em `host.docker.internal:2001` (saída para o host). O srsUE no host faz **bind** em 2001 e **connect** em `127.0.0.1:2000`.

### Subir o gNB

Com `./scripts/up.sh`, o **processo `gnb` não inicia automaticamente** no container (`GNB_AUTO_START=0` por padrão). Para iniciar o `gnb` automaticamente, use `GNB_AUTO_START=1 ./scripts/up.sh`.

```bash
cd gNB_traditional
./scripts/up.sh
docker exec -it srsran-gnb-tradicional bash
```

Dentro do container, execute:

```bash
gnb -c /etc/srsran/gnb-zmq-srsue.yml
```

Para auto-iniciar o `gnb` (tracing manual): `GNB_AUTO_START=1 ./scripts/up.sh`.

Para usar `gnb.yml` (ru_dummy, sem ZMQ para srsUE): `GNB_CONFIG=gnb.yml ./scripts/up.sh`.

---

## 2. Build e instalação do srsUE (srsRAN 4G)

O srsUE faz parte do repositório **srsRAN 4G** (não do srsRAN Project).

```bash
# Dependências (Ubuntu)
sudo apt-get update
sudo apt-get install -y build-essential cmake libfftw3-dev libmbedtls-dev \
  libsctp-dev libyaml-cpp-dev libzmq3-dev

# Clone e build
git clone https://github.com/srsran/srsRAN_4G.git
cd srsRAN_4G
mkdir build && cd build
cmake ..
make -j$(nproc)
sudo make install
ldconfig
```

---

## 3. Configuração do srsUE

Use o arquivo `gNB_traditional/configs/ue_srsue.conf`, alinhado ao subscriber do free5GC.

Credenciais (mesmas do `add-subscriber.sh`):

- **IMSI:** 208930000000001 (MCC 208, MNC 93)
- **K:** 8baf473f2f8fd09487cccbd7097c6862
- **OPC:** 8e27b6af0e692e750f32667a3b14605d
- **AMF:** 8000

ZMQ (gNB em Docker, srsUE no host):

- **tx_port:** UE faz bind em 2001 (UL) — `tcp://0.0.0.0:2001` para aceitar conexões do gNB.
- **rx_port:** UE connect ao gNB DL — `tcp://127.0.0.1:2000`.
- **base_srate:** 23.04e6.
- **5G SA só:** em `srsue`, `rf.nof_carriers = nof_lte + nof_nr`. O default LTE é **1** portadora; com `[rat.nr] nof_carriers = 1` isso dá **2** canais RF e o primeiro par `tx_port`/`rx_port` é consumido pelo canal 0 — o canal 1 fica sem portas. Use **`[rat.eutra] nof_carriers = 0`** (ver [srsRAN_4G#1280](https://github.com/srsran/srsRAN_4G/issues/1280)).

Exemplo no `ue_srsue.conf`:

```ini
[rf]
device_name = zmq
device_args = tx_port=tcp://0.0.0.0:2001,rx_port=tcp://127.0.0.1:2000,id=ue,base_srate=23.04e6
srate = 23.04e6
nof_antennas = 1

[rat.eutra]
nof_carriers = 0

[usim]
mode = soft
algo = milenage
opc = 8e27b6af0e692e750f32667a3b14605d
k = 8baf473f2f8fd09487cccbd7097c6862
imsi = 208930000000001
imei = 353490069873319

[rat.nr]
bands = 3
nof_carriers = 1
max_nof_prb = 106
nof_prb = 106

[rrc]
release = 15
ue_category = 4

[nas]
apn = internet
apn_protocol = ipv4
```

Para isolar a interface do UE use um **network namespace** (ex.: `ue1`):

```ini
[gw]
netns = ue1
ip_devname = tun_srsue
ip_netmask = 255.255.255.0
```

Crie o namespace antes de rodar o srsUE:

```bash
sudo ip netns add ue1
```

---

## 4. Ordem de execução

1. **Core free5GC** (compose) e **subscriber** (`./scripts/add-subscriber.sh`).
2. **gNB em modo ZMQ** (padrão): `cd gNB_traditional && ./scripts/up.sh` — confirmar nos logs que o gNB arrancou (`docker logs srsran-gnb-tradicional`).
3. **srsUE** no host (em outro terminal): `srsue configs/ue_srsue.conf`

**Importante:** O srsUE deve estar em execução (bind 2001) para o gNB completar a conexão ZMQ. Pode iniciar o gNB antes; o gNB tentará conectar e estabelecerá quando o srsUE subir.

### Preso em «Attaching UE...» e gNB ZMQ com 0 amostras no RX

- **gNB mesmo a correr?** Se só subiu o container com `GNB_AUTO_START=0`, **não há** DL no ZMQ. Verifique: `docker logs srsran-gnb-tradicional` deve mostrar `gnb -c ...` e `gNB started` / linha de célula (ex. n3, 1842.5 MHz). `./scripts/up.sh` no repositório usa **`GNB_AUTO_START=1` por defeito**.
- **«ue Tx port not specified» / 2 canais ZMQ:** Com `nof_lte_carriers` (default 1) **e** `nof_nr_carriers` ≥ 1, o srsUE abre **dois** canais RF; o primeiro `tx_port`/`rx_port` no `device_args` só serve ao canal 0. Solução: **`[rat.eutra] nof_carriers = 0`** para só NR, **ou** definir `tx_port0`/`rx_port0`/`tx_port1`/`rx_port1` e alinhar o gNB com o mesmo número de portas ZMQ.
- **gNB.log com 0 amostras no UL** com `tx_port0`…`tx_port1` em portas extra: o gNB (1T1R) pode precisar só de um par; nesse caso use um único canal RF (`rat.eutra.nof_carriers=0`).
- **Banda e SCS:** O srsUE (5G SA + ZMQ) alinha-se à documentação srsRAN em **FDD band 3** e **SCS 15 kHz**. **n78 / SCS 30 kHz** no `gnb-zmq-srsue.yml` com `bands = 78` no srsUE costuma **não sincronizar** no PHY: o gNB mostra `Waiting for reading samples` com **0** amostras e o UE não avança do attach.
- **Correção:** Manter `cell_cfg` em **band: 3**, **common_scs: 15**, **dl_arfcn** coerente (ex.: 368500) e `[rat.nr] bands = 3` no `ue_srsue.conf`. Reinicie o gNB após alterar o YAML.

---

## 5. Verificação e teste de dados

- **Registro:** nos logs do AMF (free5GC) deve aparecer Initial UE Message / Registration; no srsUE, mensagens de attach e "RRC Connected".
- **Sessão PDU:** no SMF, estabelecimento de sessão; no srsUE, "PDU Session Establishment successful. IP: 10.60.x.x" (pool do free5GC é 10.60.0.0/16).
- **Rota no host** para o pool do UE: `sudo ip route add 10.60.0.0/16 via <IP_do_gateway_do_UPF_na_bridge>`
- **Rota no UE** (se usar namespace `ue1`): `sudo ip netns exec ue1 ip route add default via 10.60.0.1 dev tun_srsue`
- **Ping:** do host para o IP do UE (10.60.x.x) ou `sudo ip netns exec ue1 ping 10.60.0.1`.

---

## 6. Arquivos de apoio

- **gNB ZMQ:** `gNB_traditional/configs/gnb-zmq-srsue.yml` — band 3, SCS 15, ru_sdr ZMQ.
- **srsUE:** `gNB_traditional/configs/ue_srsue.conf` ou `gNB_disaggregated/configs/ue_srsue.conf` — ZMQ, USIM e NR alinhados ao subscriber 208930000000001.
- **RAN desagregada (CU/DU):** `gNB_disaggregated` — `./scripts/up.sh` (padrão: `CU_AUTO_START=0`, `DU_AUTO_START=0`). **`./scripts/start-cu.sh`** → **srsUE** (`gNB_disaggregated/configs/ue_srsue.conf`, ZMQ **2002/2003**) → **`./scripts/start-du-after-ue.sh`** — ver `gNB_disaggregated/README.md`, `gNB_disaggregated/configs/ZMQ_PORTS.md` e `gNB_disaggregated/docs/CU_DU_CONEXAO.md`.

---

## Referência rápida

| Item       | Valor                            |
| ---------- | -------------------------------- |
| Config gNB | gnb-zmq-srsue.yml (padrão)       |
| PLMN       | 20893 (MCC 208, MNC 93)          |
| TAC        | 1                                |
| IMSI       | 208930000000001                  |
| Pool UE    | 10.60.0.0/16 (DNN internet)      |
| ZMQ gNB DL | porta 2000 (bind)                |
| ZMQ gNB UL | porta 2001 (gNB connect → UE bind) |
| srsUE      | srsRAN 4G, 23.11 ou mais recente |

Documentação oficial: [srsRAN gNB with srsUE](https://docs.srsran.com/projects/project/en/latest/tutorials/source/srsUE/source/index.html).
