# Interpretacao - Fase 1 nonRT + FlexRIC

Este guia ajuda a transformar os resultados da Fase 1 em conclusões
operacionais. Ele complementa [FASE1_NONRT_FLEXRIC.md](FASE1_NONRT_FLEXRIC.md):
o outro documento ensina a executar; este explica como interpretar.

## Pergunta que a Fase 1 responde

A Fase 1 responde:

> Consigo observar o comportamento do RAN por E2/KPM e, em paralelo, validar o
> plano nonRT de politicas A1 simuladas sem quebrar o core 5G?

Ela ainda não responde:

> Uma rApp consegue reagir automaticamente a KPM e aplicar uma policy real em
> um nearRT RIC?

Isso pertence a Fase 2/3, porque FlexRIC nao expoe A1.

## Evidencias principais

| Evidencia | Onde ver | Interpretacao |
|-----------|----------|---------------|
| PMS `OK` | `test_nonrt_ric.sh`, `nonrt_before.txt`, `nonrt_after.txt` | plano nonRT esta acessivel |
| RICs `AVAILABLE` no PMS | `/a1-policy/v2/rics` | PMS sincronizou com simuladores A1 |
| `Connected E2 nodes = 1` | logs de xApp | gNB registrou no nearRT FlexRIC |
| `Successfully subscribed` | logs de xApp | xApp conseguiu assinar RAN Function |
| KPM `DRB.*` e `RRU.*` | `kpm_*_summary.txt` | xApp recebeu indications periodicas |
| throughput iperf/ping | `traffic_*_summary.txt` | carga realmente foi gerada no plano de usuario |

## Como ler os arquivos de estresse

O script `stress_ue_observe_apps.sh` cria uma pasta:

```text
logs/ue_stress_<timestamp>/
```

Arquivos mais importantes:

| Arquivo | Como interpretar |
|---------|------------------|
| `kpm_baseline_summary.txt` | estado leve antes da carga |
| `kpm_stress_summary.txt` | comportamento durante iperf/carga |
| `kpm_recovery_summary.txt` | retorno apos a carga |
| `traffic_stress_summary.txt` | confirma bitrate/perda/retransmissoes do teste |
| `nonrt_before.txt` / `nonrt_after.txt` | confirma se PMS/policies ficaram estaveis |

Comparacao recomendada:

```bash
diff -u logs/ue_stress_<id>/nonrt_before.txt logs/ue_stress_<id>/nonrt_after.txt
cat logs/ue_stress_<id>/kpm_baseline_summary.txt
cat logs/ue_stress_<id>/kpm_stress_summary.txt
cat logs/ue_stress_<id>/kpm_recovery_summary.txt
```

## KPMs e leitura pratica

| KPM | Unidade | Se aumenta durante stress | Aplicacao real |
|-----|---------|---------------------------|----------------|
| `DRB.UEThpDl` | `kbps` | mais trafego DL entregue ao UE | medir experiencia de usuario e capacidade DL |
| `DRB.UEThpUl` | `kbps` | mais trafego UL entregue pelo UE | detectar uso intenso de uplink |
| `DRB.PdcpSduVolumeDL` | `Mb` | volume DL acumulado na janela | base para billing, quota, tendencia de consumo |
| `DRB.PdcpSduVolumeUL` | `Mb` | volume UL acumulado na janela | detectar upload intenso, cameras, sensores |
| `DRB.RlcSduDelayDl` | `us` | possivel fila/congestao no RLC | indicador de degradacao antes de queda de throughput |
| `RRU.PrbTotDl` | `%` | maior ocupacao de recursos DL | capacidade de celula e admission control |
| `RRU.PrbTotUl` | `%` | maior ocupacao de recursos UL | detectar saturacao UL e interferencia/carga |

## Padroes esperados

### Padrao saudavel

- baseline: throughput baixo, PRB baixo, delay baixo;
- stress: `DRB.UEThp*` e/ou `RRU.PrbTot*` sobem;
- recovery: metricas voltam proximo ao baseline;
- nonRT before/after sem mudancas inesperadas;
- xApp termina com sucesso.

Conclusao: observabilidade E2 esta funcional e a carga esta sendo refletida nos
KPMs.

### Trafego existe, mas KPM nao muda

Possiveis causas:

- xApp assinou slice errado;
- trafego nao passou pelo tunel UE (`oaitun_ue*` ou `uesimtun0`);
- iperf gerou trafego curto demais para a janela KPM;
- xApp nao estava conectado durante a fase de stress.

Verifique:

```bash
grep -E 'Connected E2 nodes|Successfully subscribed|DRB\.|RRU\.' logs/ue_stress_<id>/kpm_stress.log
cat logs/ue_stress_<id>/traffic_stress_summary.txt
```

### KPM muda, mas nonRT nao muda

Isso e esperado na Fase 1. O nonRT esta falando com A1 simulators, nao com o
FlexRIC. A interpretacao correta e:

- xApps mostram impacto radio/UE;
- nonRT mostra saude do plano de politicas;
- nao ha closed loop real entre os dois.

## Como pensar em aplicacao real

Em uma rede real, esta fase representa um laboratorio de duas capacidades:

1. Observabilidade nearRT: xApps podem enxergar KPM e RC em janelas curtas.
2. Governanca nonRT: rApps/PMS podem criar, versionar e auditar policies.

O desenho de produto que nasce daqui:

```text
KPM baseline/stress/recovery -> detector de degradacao -> recomendacao de policy
policy simulada no PMS       -> auditoria e governanca -> Fase 2 aplica via A1 real
```

Exemplos reais:

- detectar aumento de `RRU.PrbTotUl` e recomendar limite para UEs de baixa prioridade;
- observar `DRB.RlcSduDelayDl` alto e preparar policy de QoS;
- usar `DRB.PdcpSduVolume*` para criar perfil de consumo por slice;
- validar que o Control Panel/PMS continua saudavel durante carga de usuario.

## Critério de saída para avancar para Fase 2

Avance quando:

- `test_nonrt_ric.sh --seed` passa;
- `explore_e2_sm.sh quick` passa;
- `test_e2_kpm.sh` gera KPMs nao vazios;
- `stress_ue_observe_apps.sh` mostra diferenca entre baseline e stress;
- voce aceita a limitacao de que A1 ainda é simulado.

