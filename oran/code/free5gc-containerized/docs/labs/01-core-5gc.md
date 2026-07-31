# Roteiro 01 — Infraestrutura e Core 5G (free5GC)

**Objetivos:** Compreender a stack containerizada; levantar o **5GC SA** sem RAN; validar NRF/AMF/SMF/UPF e dados de subscrição.

**Duração indicativa:** 45–60 min (primeira vez, incluindo build de imagens).

---

## 1. Preparação do ambiente

Execute e **guarde a saída** nos anexos do relatório (ou cole num bloco de código / PDF).

```bash
docker --version
docker compose version
uname -a
```

**Evidência:** print ou copiar-colar dos três comandos.

Verifique se o daemon Docker está ativo:

```bash
docker info
```

**Evidência:** primeiras 15–20 linhas da saída (sem dados sensíveis).

---

## 2. Limpeza opcional (se repetir o lab)

Só se tiver corrido o lab antes e quiser estado limpo:

```bash
cd free5gc-containerized/gNB_open && ./scripts/down.sh 2>/dev/null || true
cd ../gNB_disaggregated && ./scripts/down.sh 2>/dev/null || true
cd ../gNB_traditional && ./scripts/down.sh 2>/dev/null || true
cd ../core && ./scripts/down.sh --volumes   # apaga Mongo — confirme quando o script pedir
```

**Evidência:** não obrigatória; mencione no relatório se usou reset total.

---

## 3. Subida do Core

```bash
cd free5gc-containerized/core
./scripts/up.sh
```

Aguarde o fim do script. Se o UPF falhar, o próprio roteiro sugere correções; consulte `docs/README_TROUBLESHOOTING.md` na pasta `core`.

**Comandos de verificação imediata:**

```bash
docker compose ps
docker network inspect free5gc-privnet --format '{{json .IPAM.Config}}'
```

**Evidências obrigatórias:**

1. **Print ou texto** de `docker compose ps` com os serviços **Up** (db, nrf, amf, smf, upf, …).
2. Confirmação da subnet **10.100.200.0/24** na rede `free5gc-privnet` (comando acima ou `docker network ls | grep free5gc`).

---

## 4. Subscriber (UdmUdr)

O docker-compose.yaml do core já possui um serviço de webui que pode ser acessado em [http://localhost:5000](http://localhost:5000). Para adicionar um novo subscriber, acesse o webui e clique em "ADD A SUBSCRIBER" e preencha os campos com as informações do subscriber. Em seguida, clique em "SUBMIT" para adicionar o subscriber. Alternativamente, execute o seguinte comando:

```bash
cd free5gc-containerized/core
./scripts/add-subscriber.sh
```

**Evidência:** saída do script (indicação de SUPI/IMSI usado, sucesso).

**Verificação manual (opcional, para o relatório):**

```bash
docker compose exec -T db mongo free5gc --quiet --eval 'db.subscribers.countDocuments({})'
docker compose exec -T db mongo free5gc --quiet --eval 'db.subscribers.find().toArray()'
```

**Evidência:** o número retornado (deve ser ≥ 1).

---

## 5. Healthcheck e testes básicos

```bash
./scripts/healthcheck.sh
./scripts/test.sh
```

**Evidência:** anexe a saída **completa** de ambos (arquivos `.txt` ou PDF).

**Nota:** Sem RAN, o healthcheck pode indicar que não há container RAN N2 — é **esperado** neste roteiro. Explique isso no relatório (“N2 só após Roteiro 02”).

---

## 6. Web UI (opcional mas recomendado)

Com o core ativo, abra no navegador (conforme configuração do projeto):

- WebUI: porta publicada no `docker-compose` (tipicamente **5000** ou **2121/2122** — confira `core/docker-compose.yaml` em `free5gc-webui`).

**Evidência:** **print** da página de login ou dashboard (sem palavras-passe visíveis).

---

## 7. Logs mínimos a recolher

Para o relatório, guarde **trechos recentes** (últimas ~30–50 linhas) de:

```bash
docker compose logs --tail 80 free5gc-nrf
docker compose logs --tail 80 free5gc-amf
docker compose logs --tail 80 free5gc-smf
docker compose logs --tail 80 free5gc-upf
```

**Evidência:** arquivo `logs-core-amostra.txt` (ou por serviço) no anexo.

---

## 8. Encerramento (fim do dia)

```bash
cd free5gc-containerized/core
./scripts/down.sh
```

Se quiser remover volumes Mongo para a próxima aula: `./scripts/down.sh --volumes`.

---

## Checklist Roteiro 01

- Versões Docker anexadas  
- `docker compose ps` com core saudável  
- Rede `free5gc-privnet` identificada  
- Subscriber criado (saída + eventual `countDocuments`)  
- `healthcheck.sh` e `test.sh` anexados  
- Amostra de logs NRF/AMF/SMF/UPF  
- Texto curto: o que é N2 e por que ainda não aparece neste roteiro

**Referência técnica:** [core/docs/DOCKER_COMPOSE_EXPLAINED.md](../../core/docs/DOCKER_COMPOSE_EXPLAINED.md)