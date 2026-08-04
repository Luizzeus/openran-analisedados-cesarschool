# Vendor — dependências externas

## oran-sc-ric

Cópia de [srsran/oran-sc-ric](https://github.com/srsran/oran-sc-ric) (i-release) para nearRT O-RAN SC em Docker.

Customizações do lab em `config/oran-ric/docker-compose.override.yml` (E2 :36422, A1 Mediator).

Atualizar upstream:

```bash
cd vendor/oran-sc-ric
git init && git remote add origin https://github.com/srsran/oran-sc-ric.git
git fetch --depth 1 origin main && git checkout FETCH_HEAD
```
