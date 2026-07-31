# Roteiro 03 — RAN desagregada: *split* CU / DU e interface F1

**Objetivos:** executar **srsCU** e **srsDU** em containers separados; compreender **F1-C / F1-U** entre CU e DU; comparar com o gNB **monolítico** do Roteiro 02.

**Nota:** este roteiro usa a pasta **`gNB_disaggregated/`** (split sem Open Fronthaul). Para CU/DU **+ RU emulada** e rede **O-RAN Open Fronthaul**, veja o [Roteiro 05 — RAN aberta O-RAN](05-ran-open-fronthaul-o-ran.md) (`gNB_open/`).

**Pré-requisitos:**

- Roteiro 01 concluído (**core** ativo na rede Docker `free5gc-privnet`).
- **Imagem `srsran-gnb:local`:** o `docker compose` de `gNB_disaggregated` usa o **mesmo** `Dockerfile.srsRAN` que o `gNB_traditional`. Na primeira subida, o *build* pode demorar (vários minutos).

**Caminhos:** os comandos assumem a pasta `code/free5gc-containerized` no repositório (ajuste se o seu clone estiver em outro nível).

**Convivência com o Roteiro 02:** com **`DU_CONFIG=du.yml`** (`ru_dummy`), pode manter o **gNB tradicional** **em paralelo** (IDs distintos: `411` vs `412`). Com **`du-zmq-srsue.yml`**, o repositório usa ZMQ **2002/2003** no `gNB_disaggregated` e **2000/2001** no `gNB_traditional` — podem coexistir; veja [gNB_disaggregated/configs/ZMQ_PORTS.md](../../gNB_disaggregated/configs/ZMQ_PORTS.md). Dois UEs com o **mesmo IMSI** no mesmo core não são suportados.

**Exclusividade com `gNB_open`:** não suba **`gNB_disaggregated`** e **`gNB_open`** ao mesmo tempo (mesmos contentores `srsran-cu` / `srsran-du` e IPs **.51** / **.52**).

**Modo laboratório (padrão):** o **DU** usa **`ru_dummy`** (sem RF ZMQ). **Opcional:** `du-zmq-srsue.yml` e **`gNB_disaggregated/configs/ue_srsue.conf`** (portas **2002/2003**) para E2E (secção **1.1**).

---

## 1. Subida da RAN desagregada

Com o core ativo:

```bash
cd gNB_disaggregated
./scripts/up.sh
```

**O que o script faz:** verifica a rede `free5gc-privnet`; executa `docker compose up -d --build`. O **compose** define `depends_on: srsran-cu` para o **DU** — o container do CU **inicia primeiro**; o DU só sobe depois (mas o binário `srsdu` só funciona quando o CU-CP em `10.100.200.51` responde ao *ping*, conforme o `entrypoint-du.sh`).

**Verificação:**

```bash
docker compose ps
docker ps --filter name=srsran-cu --format '{{.Names}} {{.Status}}'
docker ps --filter name=srsran-du --format '{{.Names}} {{.Status}}'
```

**Resultado esperado:** **ambos** `Up` — `srsran-cu` e `srsran-du`.

**Logs esperados (trechos típicos):**

- **CU** (`docker logs srsran-cu 2>&1 | tail -50`): espera ao AMF; em seguida linhas do **srscu** com ligação ao **AMF** / **N2** / **NGAP** e *F1* à escuta no IP do CU.
- **DU** (`docker logs srsran-du 2>&1 | tail -50`): espera ao AMF **e** ao CU-CP (`10.100.200.51`); depois **srsDU** com **F1 Setup** / ligação ao CU. Com **`DU_AUTO_START=0`** (padrão para ZMQ), o **srsdu** só aparece depois de **`./scripts/start-du-after-ue.sh`** (ou `./scripts/run-du.sh`) **no host**, com o srsUE já à escuta na porta **UL** (padrão **2003** para `gNB_disaggregated`).

Se aparecer `FATAL: srscu não encontrado` ou `srsdu não encontrado`, a imagem não contém os binários do *split* — confira o *build* do `Dockerfile.srsRAN` (repositório **srsRAN Project** com `ninja install`).

**Evidência obrigatória:** *print* ou texto de `docker ps` com **os dois** containers **Up**.

### 1.1 Opcional — srsUE (ZMQ)

Use **`gNB_disaggregated/configs/ue_srsue.conf`**. Confirme **`Opening 1 channels`** na consola do srsUE (não 2).

**Defeito — CU e DU manuais** (`CU_AUTO_START=0`, `DU_AUTO_START=0`): ordem **CU → UE (ZMQ) → DU**:

1. (Opcional) `cd gNB_traditional && ./scripts/down.sh` — só se não quiser o monolítico em paralelo; com portas **2002/2003** no `gNB_disaggregated` não é obrigatório.
2. `cd gNB_disaggregated && ./scripts/up.sh`.
3. `cd gNB_disaggregated && ./scripts/start-cu.sh` (N2/AMF; ver `logs/cu.log`).
4. Terminal A: `cd gNB_disaggregated && srsue configs/ue_srsue.conf` (até «Attaching UE…» / PHY *done*).
5. Terminal B: `cd gNB_disaggregated && ./scripts/start-du-after-ue.sh` (espera pela **2003** e inicia o `srsdu`).

**Alternativa:** `CU_AUTO_START=1 DU_AUTO_START=1 ./scripts/up.sh` — só se não precisar de ordem manual; para ZMQ com problemas de PHY, prefira o fluxo acima.

Rotina AMF/CU/DU: [gNB_disaggregated/docs/CU_DU_CONEXAO.md](../../gNB_disaggregated/docs/CU_DU_CONEXAO.md).

Detalhes: [gNB_disaggregated/README.md](../../gNB_disaggregated/README.md).

---

## 2. Mapa de endereços (preencher no relatório)

| Entidade | IPv4 (esperado neste repositório) |
|----------|-----------------------------------|
| AMF (N2 a partir do CU) | 10.100.200.16 |
| **srsCU** | 10.100.200.51 (N2, NG-U) — **10.100.200.61** (F1-U, adicionado pelo `entrypoint-cu.sh`) |
| **srsDU** | 10.100.200.52 |
| gNB tradicional (se ativo, Roteiro 02) | 10.100.200.50 |

**Tarefa:** confirmar no *runtime*:

```bash
docker exec srsran-cu ip -4 addr show eth0
docker exec srsran-du ip -4 addr show eth0
```

**Evidência:** anexar as saídas (ou *print*) com os endereços **/24** na rede `10.100.200.0/24`.

---

## 3. Configuração: identidade e célula

No relatório, **transcreva ou anexe *print*** dos arquivos (caminhos relativos a `gNB_disaggregated/`):

### `configs/cu.yml`

- No **nível raiz** do YAML (não dentro de `cu_cp`): `ran_node_name`, `gnb_id` / `gnb_id_bit_length` (no repositório: **412** — distinto do monolítico **411**). Colocar `gnb_id` sob `cu_cp` faz o **srscu** falhar com erro de parse.
- `cu_cp.amf`: `addr`, `port`, **`bind_addr`** (IP do CU para N2: **10.100.200.51**)
- `cu_cp.f1ap.bind_addr` (interface F1-C no CU)
- `cu_up.ngu.socket` / `cu_up.f1u.socket` — **NG-U** (N3) em **.51** e **F1-U** em **.61** (evita conflito na porta UDP 2152)

### `configs/du.yml` (padrão) ou `configs/du-zmq-srsue.yml` (srsUE)

- `f1ap.cu_cp_addr` (deve ser **10.100.200.51**)
- `f1ap.bind_addr` e `f1u.socket.bind_addr` (DU: **10.100.200.52**)
- `cell_cfg`: `pci`, `plmn`, `tac`, `band`, `dl_arfcn` — em **`du.yml`**: **band 78 / SCS 30** e **`ru_dummy`**. Em **`du-zmq-srsue.yml`**: **band 3 / SCS 15** e **`ru_sdr` ZMQ** (alinhado ao `ue_srsue.conf`).

**Pergunta-guia (resposta esperada em uma frase):** por que o **N2** (SCTP/NGAP para o AMF) termina no **CU** e não no **DU**?  
*(Sugestão: no *split* O-RAN, o CU-CP concentra a interface N2; o DU trata da camada inferior da célula e do F1 com o CU.)*

---

## 4. Logs, F1 e validação N2

### 4.1 Coletar saída dos containers

```bash
docker logs srsran-cu 2>&1 | tail -n 80
docker logs srsran-du 2>&1 | tail -n 80
```

**Evidência:** dois trechos no relatório (ou dois ficheiros `.txt`).

**O que procurar e citar:**

| Container | Indícios de sucesso (exemplos — o texto exato pode variar com a versão do srsRAN) |
|-----------|-------------------------------------------------------------------------------------|
| **srsran-cu** | Conexão / associação ao **AMF**; **NGSetupRequest** / **NGSetupResponse** ou “Connected to AMF”; mensagens **F1** (servidor à escuta para o DU). |
| **srsran-du** | **F1 Setup** concluído (pedido/resposta entre DU e CU-CP); célula / **MAC** ativada após o F1. |

### 4.2 Arquivos de log em disco (recomendado)

Os YAML gravam também em **`logs/`** dentro de `gNB_disaggregated/` (volume montado). A partir da pasta **`free5gc-containerized`**:

```bash
ls -la gNB_disaggregated/logs/
tail -n 60 gNB_disaggregated/logs/cu.log
tail -n 60 gNB_disaggregated/logs/du.log
```

Se já estiver em **`gNB_disaggregated/`**, use `logs/` em vez de `gNB_disaggregated/logs/`.

**Arquivos esperados** (quando o *pcap* está habilitado nos YAML): `cu_ngap.pcap`, `du_f1ap.pcap`, `du_mac.pcap`, `du_f1u.pcap` (podem estar vazios até haver tráfego).

### 4.3 Script de validação N2 (core)

A partir da pasta **`free5gc-containerized`** (subir um nível se estiver em `gNB_disaggregated/`):

```bash
cd core
./scripts/validate-n2-ngap.sh
```

**O que esperar:**

- O script reconhece **um ou mais** *gateways* RAN com N2 (`srsran-cu`, `srsran-gnb-tradicional`, etc.).
- Com **CU aberto + tradicional** ao mesmo tempo, a saída menciona **vários** containers — leia a secção **[5] Logs RAN** com atenção: o **NGAP** para o AMF está no **CU** (`srsran-cu`), não no DU.
- **Resumo final:** “N2/NGAP validado com sucesso” quando não há falhas nos critérios do script.

**Evidência obrigatória:** saída **completa** do `validate-n2-ngap.sh` (anexo `.txt`).

**Se o passo [5] mostrar aviso no `srsran-cu`:** confira se existe `gNB_disaggregated/logs/cu.log` com NGAP; o script do repositório concatena esse arquivo ao analisar o CU.

---

## 5. PCAP e Wireshark (NGAP vs F1)

Com os serviços estáveis, liste os artefactos (a partir de **`free5gc-containerized`**; em **`gNB_disaggregated/`** use `logs/`):

```bash
ls -la gNB_disaggregated/logs/
```

**Evidência:** listagem + uma frase no relatório:

- **`cu_ngap.pcap`:** tráfego **NGAP** sobre **SCTP** (interface **N2** entre CU e AMF).
- **`du_f1ap.pcap`:** sinalização **F1AP** (interface **F1-C** entre DU e CU-CP).
- **`du_f1u.pcap`:** tráfego de utilizador sobre **F1-U** (entre DU e CU-UP), conforme configuração.

*(Se os `.pcap` estiverem vazios ou mínimos, indique no relatório — ainda assim vale o registo dos ficheiros gerados.)*

---

## 6. Comparação estruturada (tabela no relatório)

Preencha com base no que observou nos Roteiros 02 e 03:

| Aspeto | RAN tradicional (Roteiro 02) | RAN desagregada (Roteiro 03) |
|--------|-------------------------------|--------------------------|
| Nº de containers srsRAN | 1 (`srsran-gnb-tradicional`) | 2 (`srsran-cu` + `srsran-du`) |
| Onde termina N2 (NGAP/SCTP) | Processo **gnb** monolítico | **srscu** (CU-CP) |
| Interface entre “baseband” e centralização | (interna ao monólito) | **F1** (F1-C / F1-U) entre DU e CU |
| RU / rádio no repositório | `gnb-zmq-srsue.yml` + srsUE (ZMQ) **ou** `ru_dummy` em `gnb.yml` | `ru_dummy` no **DU** (`du.yml`) |
| Comentário (escalabilidade / O-RAN) | | |

---

## 7. Encerramento

```bash
cd gNB_disaggregated
./scripts/down.sh
```

(O **core** pode continuar ativo para outros roteiros.)

---

## 8. Problemas frequentes

| Sintoma | O que verificar |
|---------|-----------------|
| `INI was not able to parse cu_cp.gnb_id` / **exit 110** | No `cu.yml`, `gnb_id` e `gnb_id_bit_length` devem estar no **nível raiz** (junto de `ran_node_name`), não dentro de `cu_cp`. |
| `Failed to bind UDP socket … :2152` / **Address already in use** (NG-U) | **F1-U** e **NG-U** usam a porta **2152** no mesmo host; o repositório separa com **NG-U em .51** e **F1-U em .61** (`entrypoint-cu.sh` + `cu_up` no YAML). Recrie o container do CU após alterar o entrypoint. |
| DU reinicia ou não passa do *wait* | O **CU** tem de estar **Up** e a responder em **10.100.200.51** (`docker exec srsran-cu ping -c1 10.100.200.16`). |
| “Network is unreachable” no CU | `bind_addr` no `cu.yml` deve ser **10.100.200.51** (IP do `eth0` do container). |
| Dois N2 no AMF e confusão nos logs | Normal com **tradicional + CU**; identifique pelo **Global gNB ID** (411 vs 412) nos logs do AMF. |
| Validação N2 falha só no CU | Leia `gNB_disaggregated/logs/cu.log` e `docker logs amf`; confirme que o *build* instalou **`srscu`**. |
| srsUE em **«Attaching UE…»** com ZMQ (`du-zmq-srsue.yml`) | Confirme que o **`srsdu` está a correr** (`docker logs srsran-du`). Se usou `DU_AUTO_START=0`, tem de correr **`./scripts/start-du-after-ue.sh`** depois do srsUE (secção **1.1**). |
| **AMF:** NG Setup OK e logo **SCTP_SHUTDOWN** / UE não regista | N2 instável — ver [TROUBLESHOOTING_N2.md](../../gNB_disaggregated/docs/TROUBLESHOOTING_N2.md): `docker logs srsran-cu`, `cu.log`, slices no `cu.yml`, teste `mobilityRestrictionList: false` no `amfcfg.yaml`. |

---

## Checklist do Roteiro 03

- [ ] **srsran-cu** e **srsran-du** ativos; **.51** / **.61** (CU, se aplicável) e **.52** (DU) confirmados.
- [ ] Parâmetros de **`cu.yml`** e **`du.yml`** documentados no relatório.
- [ ] Trechos de **`docker logs`** (CU e DU) com indícios de **N2** (CU) e **F1** (DU).
- [ ] Opcional: trechos de **`cu.log`** / **`du.log`** em `gNB_disaggregated/logs/`.
- [ ] Saída completa de **`./scripts/validate-n2-ngap.sh`** (executado a partir de **`core/`**).
- [ ] Tabela comparativa (secção 6) preenchida.
- [ ] Listagem de **`gNB_disaggregated/logs/`** e nota sobre PCAPs (**NGAP** vs **F1**).

**Referências:**

- [O-RAN CU-DU Split (documentação srsRAN)](https://docs.srsran.com/projects/project/en/latest/tutorials/source/cu_du_split/source/index.html)
- Roteiro 02 (monólito): [02-ran-tradicional-n2-n3.md](02-ran-tradicional-n2-n3.md)
- README do *split*: [gNB_disaggregated/README.md](../../gNB_disaggregated/README.md)
