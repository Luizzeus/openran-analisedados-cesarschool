# Sincronização dos clones `oai-cn-gnb*`

Atualizado: 2026-07-27. Busca em `~/Documents/GitHub` (não existe `~/Documents/GiHub`).

## Inventário

| Caminho | Escopo | Docs | Scripts | AI/SMO | Maturidade |
|---------|--------|------|---------|--------|------------|
| **`cerise/rnp_failover/code/oai-cn-gnb-nonrt-nearrt`** | E2 + nonRT + O-RAN SC + SMO + IA | 19 | 50+ | **Sim** | **Canónico / mais avançado** |
| `cesar/cesar-school-repo/ric/code/oai-cn-gnb-nonrt-nearrt` | Idem sem IA | 18 (+labs aula) | ~48 | SMO sem IA | Intermédio (jun/2026) |
| `cesar/cesar-school-lectures/modulo07-ric/code/oai-cn-gnb-nonrt-nearrt` | Idem sem IA | 17 | ~47 | SMO sem IA | Atrasado vs canónico |
| `cerise/rnp_failover/code/oai-cn-gnb` | E2 FlexRIC only | 5 | ~24 | Não | Subconjunto Fase 1 |
| `cesar/.../oai-cn-gnb-e2` | E2 aula | — | — | Não | Didático |
| `cerise/rnp_failover_working_group/code/oai-cn-gnb` | Core+gNB básico | 1 | ~12 | Não | Legado (mar/2026) |

**Conclusão:** desenvolver e validar **apenas** em
`rnp_failover/code/oai-cn-gnb-nonrt-nearrt`. Os outros são forks/cópias para
aula ou working group.

## O que o canónico tem a mais

- `docs/FASE3_IA_A1.md`, `CASO_USO_LOCAL_VIRTUALIZADO.md`, `SYNC_REPOS.md`
- `scripts/ai_policy_pipeline.py`, `kpm_store.py`
- `scripts/run_ai_policy_lab.sh`, `run_ue_tp_experiment.sh`
- `config/ai-policy/`
- `tests/test_ai_policy_pipeline.py`
- `smo_lab_event.sh` / `smo_lab_snapshot.sh`

## Política de sincronização

1. **Source of truth:** `cerise/rnp_failover/code/oai-cn-gnb-nonrt-nearrt`
2. **Não** sincronizar `openairinterface5g/`, `oai-cn5g-fed/`, `logs/`, binários.
3. Sincronizar só a camada de lab: `docs/`, `scripts/`, `config/`, `tests/`,
   `README.md` (quando fizer sentido).
4. Para CESAR (aulas): espelhar após demos estáveis; manter `docs/labs/` local
   do repositório de aulas.

### Comando sugerido (dry-run)

```bash
SRC=~/Documents/GitHub/cerise/rnp_failover/code/oai-cn-gnb-nonrt-nearrt
DST=~/Documents/GitHub/cesar/cesar-school-repo/ric/code/oai-cn-gnb-nonrt-nearrt

rsync -aun --delete \
  --exclude 'openairinterface5g/' \
  --exclude 'oai-cn5g-fed/' \
  --exclude 'logs/' \
  --exclude 'flexric-lib/' \
  --exclude 'vendor/' \
  --exclude 'ueransim/' \
  --exclude '__pycache__/' \
  --exclude '*.log' \
  --exclude 'docs/labs/' \
  "$SRC"/docs/ "$DST"/docs/

rsync -aun \
  --exclude '__pycache__/' \
  "$SRC"/scripts/ai_policy_pipeline.py \
  "$SRC"/scripts/kpm_store.py \
  "$SRC"/scripts/run_ai_policy_lab.sh \
  "$SRC"/scripts/run_ue_tp_experiment.sh \
  "$SRC"/scripts/smo_lab_event.sh \
  "$SRC"/scripts/smo_lab_snapshot.sh \
  "$DST"/scripts/

rsync -aun "$SRC"/config/ai-policy/ "$DST"/config/ai-policy/
rsync -aun "$SRC"/tests/test_ai_policy_pipeline.py "$DST"/tests/
```

Remover `-n` para aplicar. Repetir `DST` para
`cesar-school-lectures/modulo07-ric/code/oai-cn-gnb-nonrt-nearrt` se necessário.

### Relação com `oai-cn-gnb` (sem nonRT)

Tratar como **subset**. Não copiar nonRT/SMO/IA para lá. Se precisar E2 docs
atualizados:

```bash
SRC=.../oai-cn-gnb-nonrt-nearrt
DST=.../oai-cn-gnb
rsync -aun \
  "$SRC"/docs/E2_FLEXRIC.md \
  "$SRC"/docs/E2_SERVICE_MODELS.md \
  "$SRC"/docs/TUTORIAL_LAB_E2.md \
  "$SRC"/docs/SLIDES_LAB_E2.md \
  "$DST"/docs/
```

### Working group

Atualizar só sob pedido explícito do grupo; está muito atrás e misturar IA/SMO
pode confundir.

## Checklist pós-sync

- [ ] `python3 -m unittest discover -s tests -v` no destino  
- [ ] `./scripts/run_ue_tp_experiment.sh` (offline)  
- [ ] Confirmar que `docs/labs/` CESAR não foi apagado  
- [ ] Não commitar `logs/` nem submódulos OAI alterados sem intenção
