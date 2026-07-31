# Roteiro — Plano de testes do Projeto 2 (NGO §6)

**Disciplina:** RAN Intelligent Controller (RIC)  
**Uso:** Workshop **Aula 05** · entrega como anexo do relatório do **Projeto 2**  
**Peso na avaliação:** integrado em **P4** (reprodutibilidade) e **P5** (limitações) — ver [avaliacao_seminario_aula06.md](../avaliacao_seminario_aula06.md)

**Código:** `ric/code/oai-cn-gnb-e2/`

---

## Objetivo

Documentar **como o grupo validou** a pilha OAI + FlexRIC e as subscriptions E2, alinhado à abordagem de testes do artigo NGO (§6 — validação em rede real / testbed).

Cada grupo deve preencher este roteiro e anexar ao repositório do projeto (ex.: `docs/PLANO_TESTES.md` no fork ou `TESTES.md` na raiz).

---

## 1. Identificação

| Campo | Preencher |
|-------|-----------|
| Grupo | |
| Integrantes | |
| E2SM principal | KPM / RC / custom / combinação |
| Extensão escolhida | xApp custom / A1 / otimização / nenhuma |
| Data do teste | |
| Ambiente | SO, RAM, Docker version |

---

## 2. Escopo do teste

### 2.1 O que está sendo validado

Marque e descreva:

- [ ] **Deploy:** Core OAI + nearRT-RIC + gNB E2 + nrUE (RFSIM)
- [ ] **E2 SETUP:** associação gNB ↔ FlexRIC
- [ ] **Subscription E2SM-KPM** (slice 222/123)
- [ ] **Subscription E2SM-RC** (eventos RRC)
- [ ] **Custom SM** (MAC/RLC/PDCP/GTP)
- [ ] **Extensão** (descrever)

### 2.2 Fora do escopo (declarar explicitamente)

Exemplos: hardware RF, multi-UE, Non-RT RIC, A1 em produção, OSC em K8s.

---

## 3. Pré-condições

| ID | Pré-condição | Como verificar | OK? |
|----|--------------|----------------|-----|
| P1 | Build E2 concluído | `test -x openairinterface5g/cmake_targets/ran_build/build/nr-softmodem` | |
| P2 | `flexric-lib/libkpm_sm.so` presente | `ls flexric-lib/libkpm_sm.so` | |
| P3 | Core OAI rodando | `docker ps \| grep oai-amf` | |
| P4 | Slice 222/123 no AMF | conferir `gnb.conf` / `ue.conf` | |
| P5 | IP host `192.168.70.129` em `demo-oai` | `ip addr show demo-oai` | |

---

## 4. Casos de teste

Preencha pelo menos **CT-01 a CT-04**. Adicione linhas se necessário.

| ID | Caso | Comando / ação | Resultado esperado | Resultado obtido | Evidência (log) |
|----|------|----------------|--------------------|------------------|-----------------|
| CT-01 | Subir lab E2 | `./scripts/up_e2_lab.sh` | E2 SETUP nos logs | | `logs/gnb_oai.log` |
| CT-02 | Custom SM | `./scripts/test_e2_sm.sh cust` | `Connected E2 nodes = 1` | | `logs/xapp_cust_moni.log` |
| CT-03 | KPM slice 222/123 | `./scripts/test_e2_kpm.sh` | Subscription + `DRB.UEThp*` | | `logs/xapp_kpm_lab.log` |
| CT-04 | RC attach | `./scripts/test_e2_rc_attach.sh` | INDICATION RRC | | `logs/xapp_rc_attach.log` |
| CT-05 | Verificação auto | `./scripts/verify_e2_lab.sh` | Todos OK | | saída terminal |
| CT-06 | Extensão | *(descrever)* | | | |

---

## 5. Métricas e critérios de sucesso

### 5.1 E2 (obrigatório para nota mínima)

| Critério | Pass? |
|----------|-------|
| E2 SETUP RESPONSE no gNB | |
| Pelo menos 1 subscription bem-sucedida | |
| Pelo menos 1 RIC INDICATION capturada em log | |

### 5.2 KPM (se E2SM = KPM)

| Métrica | Valor observado | Unidade |
|---------|-----------------|---------|
| `DRB.UEThpDl` | | kbps |
| `DRB.UEThpUl` | | kbps |
| `RRU.PrbTotUl` | | % |

### 5.3 Limitações conhecidas (obrigatório — NGO / RFSIM)

Liste pelo menos 3:

1.
2.
3.

Exemplos: RFSIM sem RF real; latência E2 não representativa de campo; volume PDCP zero em carga leve; single UE.

---

## 6. Troubleshooting registrado

Documente **pelo menos um** problema encontrado e como resolveram (mesmo que seja “consultamos E2_FLEXRIC.md §8”).

| Problema | Causa | Solução |
|----------|-------|---------|
| | | |

---

## 7. Reprodutibilidade (README do grupo)

O repositório do Projeto 2 deve conter:

```markdown
## Como reproduzir

1. cd ric/code/oai-cn-gnb-e2
2. ./scripts/build_e2.sh && ./scripts/build_flexric_tools.sh
3. ./scripts/up_e2_lab.sh
4. ./scripts/test_e2_kpm.sh
5. Evidências em logs/ ou anexos/
```

Adapte com os comandos que seu grupo realmente usou.

---

## 8. Cronograma sugerido (Aulas 04–06)

| Prazo | Entrega parcial |
|-------|-----------------|
| **Aula 04** (fim) | Evidência CT-01 + CT-02 ou CT-03 (log) |
| **Aula 05** | Plano de testes preenchido (este documento) |
| **Aula 06** | Apresentação 20 min + relatório final |

---

## Referências

- NGO et al. §6 — metodologia de validação
- [02-oai-cn-gnb-flexric-e2.md](02-oai-cn-gnb-flexric-e2.md)
- [../E2_FLEXRIC.md](../../../E2_FLEXRIC.md)
- [avaliacao_seminario_aula06.md](../avaliacao_seminario_aula06.md)
