# Interpretacao - Fase 3 SMO/OAM

Este guia explica como interpretar a Fase 3 e como pensar sua aplicacao real.
Ele complementa [FASE3_SMO_OAM.md](FASE3_SMO_OAM.md).

## Pergunta que a Fase 3 responde

A Fase 3 responde:

> Consigo adicionar um plano SMO/OAM isolado para observar topologia, eventos e
> simuladores O1 sem prejudicar Fase 1 ou Fase 2?

Ela nao promete:

> O gNB OAI monolitico sera gerenciado por O1 real.

O caminho realista no lab e O1 com simuladores O-DU/O-RU.

## Evidencias principais

| Evidencia | Onde ver | Interpretacao |
|-----------|----------|---------------|
| snapshot local criado | `./scripts/test_smo_lab.sh` | SMO-lite consegue observar/correlacionar interfaces abertas |
| preflight externo passa | `SMO_MODE=external ./scripts/test_smo_lab.sh --preflight` | checkout SMO/OAM tem compose minimo |
| containers common ativos | `docker compose ps` no modo externo | dependencias base estao de pe |
| SDNC ativo | compose OAM | plano de configuracao/O1 iniciou |
| VES collector ativo | compose OAM/logs | eventos podem ser recebidos |
| NTSIM/O-DU/O-RU ativos | compose `network` | O1 simulado disponivel |
| Fase 1/2 nao alterada | containers/processos existentes | isolamento preservado |

## Como interpretar o scaffold

Os scripts de Fase 3 nao baixam repositorios e nao sobem SMO sem o usuario
apontar `SMO_OAM_DIR`. Isso e deliberado.

Leitura dos resultados:

| Resultado | Interpretacao |
|-----------|---------------|
| modo local gera snapshot com erros de endpoint | esperado quando Fase 2/nonRT nao esta ativa |
| erro `defina SMO_OAM_DIR` | comportamento esperado no modo externo; evita acao acidental |
| erro de compose ausente | checkout externo incompleto ou layout diferente |
| aviso de porta em uso | risco de conflito com Fase 1/2 ou outros servicos |
| abort por stacks ativas | protecao de isolamento do modo externo funcionando |
| `SMO_ALLOW_SHARED_HOST=1` necessario | usuario assumiu risco de coexistencia |

## Relacao com KPM

SMO/OAM nao substitui KPM. A correlacao correta e:

```text
O1/VES/topologia dizem "o que a rede e como ela esta configurada"
KPM/E2 dizem "como o RAN esta performando agora"
A1/policies dizem "qual objetivo ou restricao deve ser aplicada"
```

KPMs a correlacionar com eventos OAM:

| KPM | Unidade | Correlacao real |
|-----|---------|-----------------|
| `DRB.UEThpDl` | `kbps` | throughput antes/depois de mudanca de configuracao |
| `DRB.UEThpUl` | `kbps` | impacto em cargas de uplink |
| `DRB.PdcpSduVolumeDL` | `Mb` | volume transportado durante janela de evento |
| `DRB.PdcpSduVolumeUL` | `Mb` | volume UL durante janela de evento |
| `DRB.RlcSduDelayDl` | `us` | atraso antes/depois de falha, alarme ou mudanca |
| `RRU.PrbTotDl` | `%` | ocupacao DL relacionada a topologia/capacidade |
| `RRU.PrbTotUl` | `%` | ocupacao UL relacionada a carga/interferencia |

## Padroes esperados

### Fase 3 saudavel

- `test_smo_lab.sh --preflight` encontra `infra`, `smo/common`, `smo/oam`;
- `up_smo_lab.sh` sobe com `COMPOSE_PROJECT_NAME` isolado;
- `test_smo_lab.sh` lista containers;
- Fase 1/2 continua igual apos `down_smo_lab.sh`.

Conclusao: plano de gestao pode ser explorado sem destruir o lab RAN/RIC.

### OAM sobe, mas nao ha eventos

Possiveis causas:

- simuladores `network` nao foram habilitados;
- VES endpoint nao recebeu payload;
- SDNC/NETCONF nao esta conectado a nenhum NTSIM;
- topologia TEIV nao foi habilitada.

Acao:

```bash
SMO_WITH_NETWORK=1 SMO_OAM_DIR=/path/para/oam ./scripts/up_smo_lab.sh
SMO_WITH_TEIV=1 SMO_OAM_DIR=/path/para/oam ./scripts/up_smo_lab.sh
```

### KPM muda, mas SMO nao mostra nada

Isso e esperado se a mudanca foi apenas no plano E2/RAN. SMO/OAM precisa de
eventos O1/VES ou topologia conectada para refletir algo.

## Como pensar em aplicacao real

A Fase 3 e a base para operacao de rede, inventario e closed-loop de gestao.
Aplicacoes reais:

- correlacionar alarmes VES com queda de `DRB.UEThp*`;
- usar topologia TEIV para saber qual celula/DU/RU esta afetada;
- disparar rApp que cria policy A1 quando `RRU.PrbTot*` fica alto por janela longa;
- documentar mudancas de configuracao e medir impacto em KPM;
- simular falha O-DU/O-RU e observar se o inventario/eventos explicam a degradacao.

Fluxo conceitual:

```text
evento O1/VES -> contexto topologico -> rApp/nonRT -> policy A1
             -> xApp nearRT -> acao E2 -> KPM confirma impacto
```

## Como validar aplicacao real com o lab

1. Gere baseline KPM na Fase 1 ou Fase 2.
2. Suba SMO/OAM com simuladores.
3. Gere evento/alteracao no simulador O1.
4. Registre timestamp do evento.
5. Compare KPM antes/depois.
6. Se houver rApp/policy, valide se a policy foi criada no PMS e chegou no A1.

Artefatos para guardar:

| Artefato | Para que serve |
|----------|----------------|
| `kpm_*_summary.txt` | efeito no plano radio |
| logs VES/OAM | evento de gestao |
| dump PMS policies | decisao nonRT |
| logs xApp | acao nearRT |
| topologia TEIV | escopo do impacto |

## Criterio de maturidade

| Nivel | Descricao |
|-------|-----------|
| 0 | preflight SMO passa |
| 1 | SMO/OAM sobe isolado |
| 2 | simulador O1 gera evento observavel |
| 3 | evento e correlacionado com KPM |
| 4 | rApp cria policy A1 baseada no evento/KPM |
| 5 | xApp aplica acao E2 e KPM confirma melhoria |
