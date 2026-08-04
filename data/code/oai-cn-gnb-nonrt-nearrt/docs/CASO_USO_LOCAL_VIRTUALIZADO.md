# Caso de uso local virtualizado (rApps do artigo SUTD)

Referência: Ngo et al., *RAN Intelligent Controller (RIC): From open-source
implementation to real-world validation*, ICT Express 10 (2024) 680–691
(`bibliography/articles/open-ran/ric_open_source_implementation_real_world_validation.pdf`).

## Veredito

Para o lab **OAI + RFSIM + FlexRIC/KPM** (uma célula virtual, sem multi-RRU
campus), o caso de uso mais apropriado é o eixo:

> **UE-TP-rApp (traffic / throughput awareness) → decisão de policy A1**

neste repositório materializado como rApp de laboratório
**`ue-tp-load-anomaly`** (baseline robusto MAD sobre KPM E2).

Não é a cópia literal do modelo LSTM do artigo; é o mesmo *papel arquitetural*
(telemetria UE-level → IA nonRT → intenção A1), executável offline/online no
host virtualizado.

## Mapa dos rApps do artigo × viabilidade local

| rApp (artigo) | O que precisa | Viável em RFSIM local? | Notas |
|---------------|---------------|------------------------|-------|
| **UE-TP-rApp** | KPM/radio + throughput | **Sim (melhor fit)** | Usamos PRB UL, delay RLC DL, UEThp UL do xApp KPM |
| Cell-TP-rApp | agregação multi-UE | Parcial | 1 UE RFSIM; agregação trivial |
| Localization-rApp | multi-piso / fingerprint RF real | Não | Sem corredor multi-célula |
| IM-rApp | zona de interferência inter-célula | Não | Precisa ≥2 células overlapping |
| ES-rApp | ligar/desligar RRUs / TX power | Não (atuação física) | Policy A1 pode *simular intenção*; O1/RU real ausente |
| PM-rApp | classificar #RRUs ativos | Não | Dataset multi-RRU do campus |

## Por que UE-TP / load-anomaly

1. O lab já coleta KPM E2 (`stress_ue_observe_apps.sh`) com as features certas.  
2. Não depende de GPS, multi-piso nem multi-RRU.  
3. Fecha o loop desejado: **coleta → BD → treino/inferência → policy A1**.  
4. Alinha-se ao caminho do artigo em que UE-TP alimenta decisões (ES/TS) via
   nonRT → A1 → nearRT.

## Pipeline experimental neste repo

```text
[xApp KPM / logs stress]
        │
        ▼
 kpm_store.py  →  SQLite + JSONL
        │
        ▼
 ai_policy_pipeline.py train/evaluate
        │
        ▼
 decision.json + policy candidata
        │
        ├── dry-run (padrão)
        └── --commit → PMS / A1 (Fase 2)
```

Comando único:

```bash
cd code/oai-cn-gnb-nonrt-nearrt
./scripts/run_ue_tp_experiment.sh
# captura nova (lab E2 no ar):
./scripts/run_ue_tp_experiment.sh --live
# policy type dedicado:
AI_POLICY_CONFIG=config/ai-policy/ue_tp_experiment.json ./scripts/run_ue_tp_experiment.sh
```

## Limites honestos

- A policy A1 **não move a RAN** até existir xApp consumidor do `policytype_id`.  
- RFSIM não reproduz interferência/energia do campus SUTD.  
- O modelo MAD é deliberadamente simples e auditável; LSTM/DNN do artigo são
  evolução quando houver dataset rotulado maior.

## Próximo passo científico

1. Versionar datasets JSONL por `run_id`.  
2. Comparar MAD vs regressão/DNN para predizer `DRB.UEThpUl`.  
3. Publicar policy type próprio no A1 Mediator e xApp TS mínimo.
