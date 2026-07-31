# N2 instável (AMF: NG Setup → SCTP shutdown) e UE em «Attaching…»

## Sintomas

- **AMF:** `Handle NGSetupRequest` → `Send NG-Setup response` → em seguida `SCTP_SHUTDOWN_EVENT`, `SCTPWrite failed bad file descriptor`, `Remove RAN Context`.
- **srsUE:** fica em **Attaching…** (o UE precisa de N2 estável para registo 5G).

### Antes de assumir N2: o `srsdu` está a correr (e na ordem certa com ZMQ)?

Com **`CU_AUTO_START=0`** / **`DU_AUTO_START=0`** (defeito), o contentor **não** inicia `srscu`/`srsdu`. Ordem típica: **`./scripts/start-cu.sh`** (N2/AMF) → srsUE (ZMQ) → **`./scripts/start-du-after-ue.sh`**. Sem o `srsdu`, não há RF ZMQ e o UE fica em **Attaching…**. Confirme: `docker logs srsran-du` mostra o `srsdu` após o último passo.

### Ordem de arranque: **srsUE antes do DU**

O **srsdu** tem de ligar o **UL** ZMQ ao *host* **depois** do srsUE fazer **bind** na porta UL (**2003**). Se executar `./scripts/start-du-after-ue.sh` **antes** de `srsue …`, ou se o DU tiver sido iniciado manualmente primeiro, a ligação RX no contentor pode ficar inconsistente e o UE permanece em **«Attaching…»**. **Pare** o `srsdu` (Ctrl+C no terminal do DU), confirme `pgrep srsue`, volte a correr **srsUE** e só então **start-du-after-ue.sh**. O script exige processo `srsue` no host (`REQUIRE_SRSUE_RUNNING=1` por defeito).

### N2 e F1-C OK, mas o UE continua em «Attaching…» — **plano de rádio (ZMQ)**

O registo 5G precisa de **sincronismo PHY** entre **DU** e **srsUE** no *host*. **AMF/CU/DU F1-C** podem estar todos verdes e o UE ainda assim não avança se o **ZMQ** não trocar amostras.

- **`du-zmq-srsue.yml`** `ru_sdr.device_args` tem de usar as **mesmas portas TCP** que **`ue_srsue.conf`**, e o `docker-compose` tem de publicar o **DL** (ex. `2002:2002` se DL=2002). Ver **`configs/ZMQ_PORTS.md`** (gNB_disaggregated **2002/2003** vs monolítico **2000/2001**).
- **`start-du-after-ue.sh`** espera a porta **UL** correta (`UE_ZMQ_UL_PORT`, padrão **2003** para gNB_disaggregated). Se ainda apontar para **2001**, o script nunca deteta o UE ou deteta o srsUE do monolítico → **Attaching…** ou comportamento errático.
- **Linux / Docker Engine:** o DU liga o UL ZMQ a `host.docker.internal:2003`. Em muitos hosts isso **não** encaminha TCP para o processo srsUE no *host*. Os scripts **`start-du-after-ue.sh`** / **`run-du.sh`** substituem por o **Gateway** da rede `free5gc-privnet` (ver `scripts/lib-zmq-du-runtime.sh`). Não use só `docker exec … -c /etc/srsran/du-zmq-srsue.yml` sem essa substituição. Diagnóstico: `./scripts/diagnose-zmq.sh`.
- Portas DL/UL desalinhadas entre DU e UE → **zero DL** no srsUE → eternamente **Attaching…**.
- **1,92 MHz / x12 decimation** no arranque do srsUE é frequente antes de fechar o relógio a **23,04 MHz** — por si só não prova desalinhamento com o DU.

### srsUE (srsRAN 4G) — **dl_nr_arfcn** / **ssb_nr_arfcn** / **scs**

O **srsUE** não vem do mesmo repositório que o DU (é o **srsRAN_4G**). Com ZMQ, se **não** definir em `[rat.nr]` os ARFCN alinhados ao que o **DU/gNB** imprime no arranque (`dl_arfcn` e `dl_ssb_arfcn`), a procura de célula pode falhar e o terminal fica em **«Attaching…»**. Os `ue_srsue.conf` deste repo incluem `scs=15`, `dl_nr_arfcn=368500`, `ssb_nr_arfcn=368410` (band 3, mesma célula que `du-zmq-srsue.yml`). Se mudar a célula, copie os valores do log do DU. Use **srsRAN 4G ≥ 23.11** (nota srsRAN Project). Log UE: `/tmp/srsue_gnb_disaggregated.log`. Ref.: [srsRAN_Project#1318](https://github.com/srsran/srsRAN_Project/issues/1318).

### ZMQ e F1 OK, PHY «done», mas «Attaching…» não completa — **S-NSSAI no CU**

O `cu.yml` tem de listar em `tai_slice_support_list` os **mesmos** SST/SD que o **AMF** (`plmnSupportList.snssaiList`) e o **subscritor** no UDM (`010203` / `112233` → decimais **66051** / **1122867**). Se só existir `sst: 1` **sem** `sd`, o registo NAS ou o contexto de rede podem falhar após o RRC — o srsUE fica em **Attaching…**. Confirme no ficheiro e **reinicie o `srscu`** após editar.

### Dois gNBs / dois UEs

Não use o **mesmo IMSI** em dois srsUE ao mesmo tempo no mesmo core. Pare o UE do monólito ou use outro subscritor.

---

Isto indica que a **associação SCTP/N2** não permanece: ou o **CU** (`srscu`) fecha o socket, ou o **AMF** encerra após detetar incompatibilidade.

## Endereço do RAN nos logs do AMF (ex.: `10.100.200.11` vs `10.100.200.51`)

O **CU** neste repositório deve ter **`10.100.200.51`** em `eth0` (ver `gNB_disaggregated/docker-compose.yaml`). Nos logs do AMF, o contexto RAN deve referir **esse** IP.

- Se aparecer **outro** (p.ex. **`.11`**), o *peer* SCTP **não** é o CU com IP estático — rede Docker incorreta, compose antigo ou contentor a usar IP dinâmico.
- Execute: `./scripts/verify-ran-net.sh` (a partir de `gNB_disaggregated/`) e confira a saída.
- Recrie a stack: `./scripts/down.sh`, confirme `docker network inspect free5gc-privnet`, volte a subir com `./scripts/up.sh`.

## Passos (por ordem)

### 1. Garantir **um** só gNB a usar N2 na mesma configuração de teste

Pare o monólito: `cd gNB_traditional && ./scripts/down.sh` e confirme que não há outro processo a ligar ao AMF na **38412**.

### 2. Ver o **CU** (causa mais comum do «shutdown» imediato)

```bash
docker logs srsran-cu 2>&1 | tail -80
tail -80 gNB_disaggregated/logs/cu.log
```

Procure **ERROR** / **FATAL** / **assert** logo após `N2: Connection to AMF` ou `NG Setup`. Se o processo **srscu** sair ou reiniciar, o AMF vê o mesmo padrão de SCTP a fechar.

### 3. Alinhar **S-NSSAI** com o core (já no `cu.yml` do repositório)

O **AMF** e o **NSSF** declaram slices com **SD** `010203` e `112233`. O `cu.yml` deve anunciar as mesmas combinações em `tai_slice_support_list` (valores em decimal no YAML srsRAN). Sem isso, cenários com free5GC podem comportar-se mal após o NG Setup.

### 4. IE NGAP opcionais (já desativados no repositório para interop srsRAN)

Em `core/config/amfcfg.yaml`, **`mobilityRestrictionList`** e **`maskedIMEISV`** estão com **`enable: false`** para evitar falhas SCTP após **Registration** / mensagens com IEs que o srsRAN pode não tratar bem.

**Reinicie o contentor `amf`** depois de alterar o ficheiro:

```bash
cd core && docker compose restart amf
```

Os valores **SCTP** `maxInitTimeout` e `maxAttempts` estão no máximo permitido pelo validador do AMF (**`maxAttempts` só pode ser 1–5** em v3.4.x; valores maiores impedem o arranque).

### 5. Captura NGAP

```bash
# Com o CU a correr
ls -la gNB_disaggregated/logs/cu_ngap.pcap
```

Analise no Wireshark a sequência **NGSetupRequest** → **NGSetupResponse** → mensagens seguintes ou **ABORT**.

### 6. Subscriber

Confirme que o UE está registado com o mesmo **PLMN/slice** que o core (`./scripts/add-subscriber.sh` no `core/`).

---

**Referência:** padrão semelhante em [free5gc#744](https://github.com/free5gc/free5gc/issues/744) (NG Setup seguido de `SCTP_SHUTDOWN_EVENT`).
