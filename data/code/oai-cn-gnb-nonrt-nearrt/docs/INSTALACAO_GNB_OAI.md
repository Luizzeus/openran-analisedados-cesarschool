# Instalação e Uso do gNB OAI (RFSIM)

Guia detalhado para instalação, build e execução do **gNB OAI** e **nrUE** em modo **RFSIM** (simulador de RF), integrado ao Core OAI do projeto oai-cn-gnb.

---

## Índice

1. [Visão geral](#1-visão-geral)
2. [Pré-requisitos](#2-pré-requisitos)
3. [Instalação de dependências](#3-instalação-de-dependências)
4. [Build do openairinterface5g](#4-build-do-openairinterface5g)
5. [Configuração de rede](#5-configuração-de-rede)
6. [Execução](#6-execução)
7. [Troubleshooting](#7-troubleshooting)

---

## 1. Visão geral

O gNB OAI é compilado a partir do código-fonte do **openairinterface5g**. Em modo **RFSIM**, não é necessário hardware de RF (USRP, etc.): o gNB e o nrUE comunicam-se via loopback interno.

| Componente | Descrição |
|------------|-----------|
| **nr-softmodem** | Binário do gNB |
| **nr-uesoftmodem** | Binário do nrUE (UE simulado) |
| **gnb.conf** | Configuração do gNB (AMF, PLMN, frequências) |
| **ue.conf** | Configuração do nrUE (IMSI, chaves, etc.) |

O build gera os binários em:

```
openairinterface5g/cmake_targets/ran_build/build/
├── nr-softmodem
├── nr-uesoftmodem
├── librfsimulator.so
└── ...
```

---

## 2. Pré-requisitos

- **Sistema**: Ubuntu 22.04 ou 24.04 (recomendado)
- **RAM**: ~8 GB livre para o build
- **Espaço em disco**: ~10 GB para o repositório e build
- **Kernel**: Qualquer kernel recente (ex.: 6.17.x)
- **Core OAI**: Deve estar rodando antes de iniciar o gNB (ver [README principal](../README.md))

---

## 3. Instalação de dependências

Execute **uma vez** para instalar pacotes necessários:

```bash
cd oai-cn-gnb/openairinterface5g/cmake_targets
./build_oai -I
```

Ou, se preferir usar Ninja (recomendado):

```bash
./build_oai --ninja -I
```

O script `-I` instala, entre outros:

- `libxml2`, `libxml2-dev`
- `libconfig`, `libconfig-dev`
- `libsctp`, `libsctp-dev`
- `libforms-dev`, `libforms-bin` (para nrscope)
- Compilador, CMake, Ninja, etc.

---

## 4. Build do openairinterface5g

### 4.1 Build para RFSIM (gNB + nrUE)

```bash
cd oai-cn-gnb/openairinterface5g/cmake_targets
./build_oai --ninja -I                    # Se ainda não instalou dependências
./build_oai --ninja --gNB --nrUE -w SIMU -c
```

| Opção | Significado |
|-------|-------------|
| `--ninja` | Usa Ninja em vez de Make |
| `--gNB` | Compila o gNB (nr-softmodem) |
| `--nrUE` | Compila o nrUE (nr-uesoftmodem) |
| `-w SIMU` | Modo simulador (RFSIM) — sem hardware de RF |
| `-c` | Clean build (apaga build anterior) |

O build pode levar **10–30 minutos** dependendo da máquina.

### 4.2 Verificar o build

```bash
ls -la oai-cn-gnb/openairinterface5g/cmake_targets/ran_build/build/nr-softmodem
ls -la oai-cn-gnb/openairinterface5g/cmake_targets/ran_build/build/nr-uesoftmodem
```

Se os arquivos existirem e forem executáveis, o build foi bem-sucedido.

### 4.3 Rebuild sem limpar

Para recompilar sem apagar o build anterior (mais rápido):

```bash
./build_oai --ninja --gNB --nrUE -w SIMU
```

---

## 5. Configuração de rede

O gNB precisa se comunicar com o AMF no Core OAI. O Core usa a rede Docker **demo-oai-public-net** com subnet **192.168.70.0/24** e interface de bridge **demo-oai**.

### 5.1 Interface demo-oai

Quando o Core está rodando, o Docker cria a interface **demo-oai**. O gNB usa:

- **GNB_IPV4_ADDRESS_FOR_NG_AMF**: 192.168.70.129
- **AMF**: 192.168.70.132

O host precisa ter um IP na mesma subnet. Após iniciar o Core:

```bash
# Verificar se a interface demo-oai existe
ip link show demo-oai

# Adicionar IP ao host na rede do Core (se necessário)
sudo ip addr add 192.168.70.129/24 dev demo-oai 2>/dev/null || true
```

### 5.2 Verificar conectividade

```bash
ping -c 2 192.168.70.132
```

Se o Core estiver rodando e a interface configurada, o ping deve funcionar.

---

## 6. Execução

### 6.1 Método recomendado: scripts do projeto

A partir do diretório **oai-cn-gnb**:

```bash
# 1. Iniciar o Core (se ainda não estiver rodando)
./scripts/up_core.sh

# 2. Iniciar gNB + nrUE
./scripts/up_gnb_oai.sh
```

O script `up_gnb_oai.sh` configura automaticamente o IP 192.168.70.129 na interface demo-oai (se existir) e:

- Verifica se os binários existem
- Inicia o gNB em background
- Aguarda 10 s e inicia o nrUE em background
- Grava logs em `logs/gnb_oai.log` e `logs/ue_oai.log`

Para parar:

```bash
./scripts/down_gnb_oai.sh
```

### 6.2 Execução manual (run_gnb.sh / run_ue.sh)

Os scripts `run_gnb.sh` e `run_ue.sh` **devem ser executados a partir de** `openairinterface5g/scripts/`, pois usam caminhos relativos ao diretório de build.

**Erro comum**: executar de `code/` ou de outro diretório causa:

```
cd: ../cmake_targets/ran_build/build: No such file or directory
sudo: ./nr-softmodem: command not found
```

**Forma correta**:

```bash
cd oai-cn-gnb/openairinterface5g/scripts
./run_gnb.sh
```

Em outro terminal:

```bash
cd oai-cn-gnb/openairinterface5g/scripts
./run_ue.sh
```

### 6.3 Execução direta (sem scripts)

```bash
cd oai-cn-gnb/openairinterface5g/cmake_targets/ran_build/build

# Terminal 1: gNB
sudo ./nr-softmodem -O ../../../scripts/gnb.conf \
    --gNBs.[0].min_rxtxtime 6 \
    --rfsim

# Terminal 2: nrUE (após o gNB estar rodando)
sudo ./nr-uesoftmodem -O ../../../scripts/ue.conf \
    --rfsim -r 106 --numerology 1 --band 78 -C 3619200000 --ssb 516
```

---

## 7. Troubleshooting

### 7.1 `cd: ../cmake_targets/ran_build/build: No such file or directory`

**Causa**: O script foi executado do diretório errado.

**Solução**: Execute a partir de `openairinterface5g/scripts/`:

```bash
cd oai-cn-gnb/openairinterface5g/scripts
./run_gnb.sh
```

Ou use o script do projeto: `./scripts/up_gnb_oai.sh`.

---

### 7.2 `sudo: ./nr-softmodem: command not found`

**Causa**: O build não foi feito ou o diretório de build não existe.

**Solução**:

```bash
cd oai-cn-gnb/openairinterface5g/cmake_targets
./build_oai --ninja -I
./build_oai --ninja --gNB --nrUE -w SIMU -c
```

Verifique se os binários existem:

```bash
ls openairinterface5g/cmake_targets/ran_build/build/nr-softmodem
```

---

### 7.3 gNB não conecta ao AMF — "Cannot assign requested address"

**Sintomas**: Logs mostram `failed to bind socket: 192.168.70.129`, `SCTP could not open socket`, `No AMF is associated to the gNB`.

**Causa**: O host não tem o IP 192.168.70.129. O gNB precisa fazer bind nesse IP para NGAP (SCTP) e GTP-U.

**Solução**:

```bash
# 1. Verificar se a interface demo-oai existe (criada quando o Core sobe)
ip link show demo-oai

# 2. Adicionar o IP
sudo ip addr add 192.168.70.129/24 dev demo-oai

# 3. Reiniciar o gNB
./scripts/down_gnb_oai.sh
./scripts/up_gnb_oai.sh
```

O script `up_gnb_oai.sh` agora adiciona o IP automaticamente se a interface existir.

---

### 7.4 UE não registra (SGMM-REG-INITIATED)

**Causa**: IMSI do nrUE não está cadastrado no banco do Core.

**Solução**: Use os scripts de diagnóstico e correção:

```bash
./scripts/diagnose-ue-connection.sh
./scripts/fix-ue-subscriber.sh
```

Reinicie Core e gNB após corrigir.

---

### 7.5 Erro de PLMN / S-NSSAI

O AMF do Core usa **SST=222, SD=123**. O `gnb.conf` em `openairinterface5g/scripts/` pode usar `sst=1`. Se o UE não registrar, verifique se o `plmn_list` e `snssaiList` no `gnb.conf` estão compatíveis com o AMF. O AMF serve os slices configurados em `SST_0`, `SD_0`, etc.

---

### 7.6 Build falha com erro de dependência

Execute novamente a instalação de dependências:

```bash
./build_oai --ninja -I
```

Para pacotes opcionais (pcre, libssh, libxml2):

```bash
./build_oai --install-optional-packages
```

---

## Referências

- [OAI 5G NR SA Tutorial (nrUE)](../openairinterface5g/doc/NR_SA_Tutorial_OAI_nrUE.md)
- [OAI 5G RFSIM (containers)](../openairinterface5g/ci-scripts/yaml_files/5g_rfsimulator/README.md)
- [README principal do oai-cn-gnb](../README.md)
