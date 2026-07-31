# free5GC Containerized

Laboratório completo de rede 5G Core usando free5GC totalmente containerizado.

## 📋 Visão Geral

Este projeto implementa uma arquitetura completa de 5G Core Network usando free5GC, incluindo:
- **Control Plane**: NRF, AMF, SMF, AUSF, UDM, UDR, PCF, NSSF
- **User Plane**: UPF
- **RAN**: srsRAN Project — compose em `../gNB_traditional` ou `../gNB_disaggregated` (rede compartilhada `free5gc-privnet`); UE: srsUE (srsRAN 4G) opcional
- **Aplicações**: WebUI, NEF, CHF
- **Interworking**: N3IWF, TNGF

## 🚀 Início Rápido

### 1. Inicializar Sistema

```bash
./scripts/up.sh
```

Este script:
- Inicia os serviços **do core** na ordem correta (não inclui gNB)
- Verifica e corrige problemas do UPF
- Adiciona subscriber automaticamente
- Indica como subir a RAN em `../gNB_traditional` ou `../gNB_disaggregated`

### 2. Verificar Saúde

```bash
./scripts/healthcheck.sh
```

### 3. Testar Sistema

```bash
# Testes básicos
./scripts/test.sh

# Testes End-to-End (E2E)
./scripts/test-e2e.sh
```

### 4. Encerrar Sistema

```bash
# Preservar dados
./scripts/down.sh

# Remover tudo (incluindo dados)
./scripts/down.sh --volumes
```

## 📁 Estrutura do Projeto

```
free5gc-containerized/
├── scripts/
│   ├── up.sh                  # Inicializar sistema
│   ├── down.sh                # Encerrar sistema
│   ├── healthcheck.sh         # Verificar saúde
│   ├── test.sh                # Testes básicos
│   ├── test-e2e.sh            # Testes End-to-End
│   ├── add-subscriber.sh      # Adicionar subscriber
│   └── fix-upf.sh             # Corrigir problemas do UPF
├── config/                     # Configurações dos serviços
├── cert/                       # Certificados TLS
├── logs/                       # Logs persistentes
│   ├── amf/
│   ├── ausf/
│   ├── nrf/
│   ├── smf/
│   ├── upf/
│   └── (logs srsRAN ficam em ../gNB_*/logs)
├── docs/                      # + roteiros de aula em repo: ../docs/laboratorios/
│   └── DOCKER_COMPOSE_EXPLAINED.md
├── docker-compose.yaml         # Definição dos serviços
├── README.md                   # Este arquivo
├── README_SCRIPTS.md           # Guia dos scripts
├── README_FUNCIONALIDADE.md    # Guia de funcionalidade
└── README_TROUBLESHOOTING.md   # Troubleshooting
```

## 🔧 Requisitos

- Docker e Docker Compose instalados
- Permissões para criar redes Docker
- IP forwarding habilitado (o script `up.sh` faz isso automaticamente)

## 📚 Documentação

- **Roteiros de laboratório e relatório (entrega):** [../docs/laboratorios/INDICE.md](../docs/laboratorios/INDICE.md)
- **Scripts:** `README_SCRIPTS.md` - Guia de uso dos scripts
- **Funcionalidade:** `README_FUNCIONALIDADE.md` - O que é necessário para E2E
- **Troubleshooting:** `README_TROUBLESHOOTING.md` - Solução de problemas
- **Docker Compose:** `docs/DOCKER_COMPOSE_EXPLAINED.md` - Explicação detalhada

## ✅ Checklist de Funcionalidade

Para garantir que o sistema está pronto para testes E2E:

- [ ] MongoDB está rodando
- [ ] NRF está rodando e acessível
- [ ] AMF está registrado no NRF
- [ ] SMF está registrado no NRF
- [ ] **UPF está rodando** (CRÍTICO - use `./scripts/fix-upf.sh` se necessário)
- [ ] **Associação PFCP estabelecida** (SMF ↔ UPF)
- [ ] NG Setup estabelecido (gNB ↔ AMF)
- [ ] **Subscriber existe no MongoDB** (CRÍTICO - use `./scripts/add-subscriber.sh`)
- [ ] UE pode se registrar
- [ ] Sessão PDU pode ser estabelecida

Execute `./scripts/test-e2e.sh` para verificar todos esses itens automaticamente.

## 🔍 Problemas Comuns

### UPF não está rodando

```bash
./scripts/fix-upf.sh
```

### Subscriber não encontrado

```bash
./scripts/add-subscriber.sh
```

### PFCP não associado

1. Garanta que UPF está rodando
2. Verifique logs: `docker compose logs free5gc-smf | grep PFCP`

Veja `README_TROUBLESHOOTING.md` para mais detalhes.

## 📊 Scripts Disponíveis

| Script | Descrição |
|-------|-----------|
| `up.sh` | Inicializa todo o sistema |
| `down.sh` | Encerra o sistema |
| `healthcheck.sh` | Verifica saúde dos serviços |
| `test.sh` | Testes básicos do sistema |
| `test-e2e.sh` | Testes End-to-End completos |
| `add-subscriber.sh` | Subscriber na WebUI (UDR) + coleção `free5gc.subscribers` |
| `fix-upf.sh` | Corrige problemas do UPF |

## 🌐 Rede Docker

O sistema usa uma única rede Docker `privnet` (10.100.200.0/24) para todos os serviços, com aliases DNS para comunicação via nome (ex: `amf.free5gc.org`).

Veja `docs/DOCKER_COMPOSE_EXPLAINED.md` para explicação detalhada.

## 🔗 Referências

- [free5GC Documentation](https://free5gc.org/)
- [free5GC GitHub](https://github.com/free5gc/free5gc)
- [srsRAN Project](https://github.com/srsran/srsRAN_Project) (gNB) · [srsUE (srsRAN 4G)](https://github.com/srsran/srsRAN_4G)

## 📝 Notas

- **Versões:** free5GC v4.2.0, srsRAN Project (gNB), srsUE (srsRAN 4G), MongoDB 4.4
- **Rede:** 10.100.200.0/24
- **Logs:** Persistem em `./logs/<servico>/`
- **Dados:** MongoDB data persiste em volume nomeado `dbdata`
