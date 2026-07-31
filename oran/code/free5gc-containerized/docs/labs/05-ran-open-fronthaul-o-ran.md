# Roteiro 05 — RAN “aberta” O-RAN: CU/DU + Open Fronthaul (RU emulada)

**Objetivos:** executar a mesma pilha **split CU/DU** do Roteiro 03, acrescentando a rede **Open Fronthaul** (O-RAN): interface dedicada **DU ↔ RU** com o binário **`ru_emulator`** do srsRAN Project; comparar com **ZMQ** (srsUE) e com **`ru_dummy`**.

**Pré-requisitos:**

- Roteiro 01 concluído (**core** ativo, rede `free5gc-privnet`, assinante criado).
- Imagem **`srsran-gnb:local`** (primeira subida pode fazer *build* longo).

**Pasta do laboratório:** `gNB_open/` (não confundir com `gNB_disaggregated/`).

**Importante — exclusividade com o Roteiro 03:** `gNB_open` e `gNB_disaggregated` usam os **mesmos** nomes de contentores (`srsran-cu`, `srsran-du`) e os **mesmos** IPs na `free5gc-privnet` (**10.100.200.51** / **.52**). **Não** suba os dois *stacks* ao mesmo tempo. Antes deste roteiro:

```bash
cd gNB_disaggregated && ./scripts/down.sh 2>/dev/null || true
```

O monolítico **`gNB_traditional`** pode permanecer ativo em paralelo se precisar comparar N2 (IDs **411** vs **412** e portas ZMQ distintas) — veja [gNB_open/configs/ZMQ_PORTS.md](../../gNB_open/configs/ZMQ_PORTS.md).

**Caminhos:** comandos relativos à raiz `free5gc-containerized/` (ajuste o clone se necessário).

---

## 1. Visão da arquitetura (para o relatório)

| Rede Docker | Liga |
|-------------|------|
| `free5gc-privnet` (externa, partilhada com o core) | CU/DU ↔ AMF (N2), NG-U (N3), F1 entre CU e DU |
| `gnb-open-ofhnet` (criada pelo compose de `gNB_open`) | DU (MAC `02:00:00:00:01:02`) ↔ RU emulada `srsran-ru` (MAC `02:00:00:00:01:01`) — Open Fronthaul |

**Contentores:** `srsran-cu`, `srsran-du`, `srsran-ru`.

**Referência rápida:** [gNB_open/README.md](../../gNB_open/README.md).

---

## 2. Modo A — Open Fronthaul com RU emulada (foco do laboratório O-RAN)

### 2.1 Subida automática (recomendada em sala)

Com o **core** já em execução:

```bash
cd gNB_open
DU_CONFIG=du-ofh-ru-emulator.yml CU_AUTO_START=1 DU_AUTO_START=1 RU_AUTO_START=1 ./scripts/up.sh
```

**O que esperar:** `srscu` no CU, `ru_emulator` no RU, `srsdu` no DU com perfil **`ru_ofh`** (ficheiro `configs/du-ofh-ru-emulator.yml`).

**Verificação:**

```bash
docker compose ps
docker ps --filter name=srsran- --format 'table {{.Names}}\t{{.Status}}'
```

**Evidência:** *print* ou texto com **três** serviços **Up** (`srsran-cu`, `srsran-du`, `srsran-ru`).

### 2.2 Verificação do fronthaul (opcional mas útil)

```bash
./scripts/verify-ofh.sh
```

Confirma as interfaces e MACs do DU/RU na rede `ofhnet`.

### 2.3 Modo manual (ordem pedagógica)

Útil para explicar dependências no quadro:

1. `./scripts/up.sh` (contentores em *idle*)
2. `./scripts/start-cu.sh`
3. `./scripts/verify-ofh.sh` (opcional)
4. `./scripts/start-ru-emulator.sh`
5. `./scripts/start-du-ofh.sh`

**Logs em disco:** `gNB_open/logs/cu.log`, `du-ofh.log` (ou `du.log`, conforme config), ficheiros na pasta `logs/` do RU.

---

## 3. Validação N2 / NGAP (core)

A partir de `core/`:

```bash
cd ../core
./scripts/validate-n2-ngap.sh
```

**Evidência:** saída completa (anexo `.txt`). O script concatena `docker logs` do `srsran-cu` com `gNB_open/logs/cu.log` quando existir.

**Se falhar:** [gNB_open/docs/TROUBLESHOOTING_N2.md](../../gNB_open/docs/TROUBLESHOOTING_N2.md), [gNB_open/docs/CU_DU_CONEXAO.md](../../gNB_open/docs/CU_DU_CONEXAO.md).

---

## 4. PCAPs e interfaces (NGAP, F1, OFH)

Como no Roteiro 03, os YAML podem gerar PCAPs sob `gNB_open/logs/` (ex.: `cu_ngap.pcap`, `du_f1ap.pcap`, `du_f1u.pcap`). Liste e identifique no relatório:

- **N2:** NGAP/SCTP entre CU e AMF  
- **F1-C / F1-U:** entre DU e CU  
- **Open Fronthaul:** tráfego entre DU e RU emulada (conforme dissectors disponíveis na versão do srsRAN)

```bash
ls -la gNB_open/logs/
```

---

## 5. Modo B — Mesma pasta com `ru_dummy` ou ZMQ (srsUE)

Para alinhar com o Roteiro 03 sem hardware OFH:

**F1 + `ru_dummy` (sem UE):**

```bash
cd gNB_open
DU_CONFIG=du.yml CU_AUTO_START=1 DU_AUTO_START=1 ./scripts/up.sh
```

**E2E com srsUE (portas 2002/2003):** mesma ordem **CU → srsUE → DU** que em `gNB_disaggregated`:

1. `./scripts/up.sh`
2. `./scripts/start-cu.sh`
3. `srsue configs/ue_srsue.conf` (a partir de `gNB_open/`)
4. `./scripts/start-du-after-ue.sh`

Detalhes: secção “srsUE + ZMQ” em [gNB_open/README.md](../../gNB_open/README.md).

**Atenção:** não use o **mesmo IMSI** em dois UEs no mesmo core.

---

## 6. Tabela comparativa (sugerida no relatório)

| Aspeto | Tradicional (Roteiro 02) | Desagregado (Roteiro 03) | Open / OFH (este roteiro) |
|--------|---------------------------|---------------------------|----------------------------|
| Pasta | `gNB_traditional/` | `gNB_disaggregated/` | `gNB_open/` |
| Contentores srsRAN | 1 (`gnb`) | 2 (CU + DU) | 3 (CU + DU + **RU**) |
| “Rádio” no lab | ZMQ / `ru_dummy` | ZMQ / `ru_dummy` | **RU emulada** (`ru_emulator`) + rede **`ofhnet`** |
| Interface extra vs split simples | — | F1 | F1 + **Open Fronthaul** (DU–RU) |

---

## 7. Encerramento

```bash
cd gNB_open
./scripts/down.sh
```

A rede `gnb-open-ofhnet` pode ser removida pelo Compose ao encerrar o *stack*. O **core** pode ficar ativo.

---

## Checklist do Roteiro 05

- [ ] `gNB_disaggregated` **parado** antes de subir `gNB_open` (se aplicável).
- [ ] Três contentores **Up** no modo OFH **ou** justificação se usou apenas Modo B.
- [ ] Saída de `validate-n2-ngap.sh` (a partir de `core/`).
- [ ] Listagem de `gNB_open/logs/` + frase sobre **N2 / F1 / OFH**.
- [ ] Parágrafo no relatório: o que a **RU emulada** e a rede **`ofhnet`** representam face ao **ZMQ** no host.

**Referências:** [gNB_open/README.md](../../gNB_open/README.md), [O-RAN / srsRAN CU-DU](https://docs.srsran.com/projects/project/en/latest/tutorials/source/cu_du_split/source/index.html), Roteiros [02](02-ran-tradicional-n2-n3.md) e [03](03-ran-aberta-cu-du.md).
