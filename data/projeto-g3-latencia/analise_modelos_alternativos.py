# -*- coding: utf-8 -*-
"""Compara o modelo do docente (robust-baseline-mad) com modelos alternativos.

Roda sobre data/code/datasets/kpm-ue-tp-sample/kpm.jsonl (100 amostras) SEM alterar os dados.
Gera no stdout os numeros usados em:
  - analise-modelos-alternativos.md
  - comparacao-modelos.md

Uso:
    cd data/projeto-g3-latencia
    python analise_modelos_alternativos.py

Dependencias: numpy, pandas, scipy, scikit-learn.  Opcional: ruptures (bloco 6).
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
DS = ROOT / "data/code/datasets/kpm-ue-tp-sample/kpm.jsonl"
MODEL = json.loads((ROOT / "data/code/datasets/kpm-ue-tp-sample/model.json").read_text(encoding="utf-8"))

ORDER = ["baseline", "stress", "recovery"]
FEATS = ["delay", "thp", "prb"]
COLMAP = {"DRB.RlcSduDelayDl": "delay", "DRB.UEThpUl": "thp", "RRU.PrbTotUl": "prb"}


def load() -> pd.DataFrame:
    rows = [json.loads(l) for l in DS.read_text(encoding="utf-8").splitlines() if l.strip()]
    raw = pd.json_normalize(rows).rename(columns={
        "metrics.DRB.RlcSduDelayDl": "delay",
        "metrics.DRB.UEThpUl": "thp",
        "metrics.RRU.PrbTotUl": "prb",
    })
    df = raw[["phase", "sample_index", *FEATS]].copy()
    df["phase"] = pd.Categorical(df["phase"], categories=ORDER, ordered=True)
    return df.sort_values(["phase", "sample_index"]).reset_index(drop=True)


DF = load()
Y_STRESS = (DF.phase == "stress").to_numpy().astype(int)


def pct(mask) -> dict:
    s = pd.Series(np.asarray(mask), index=DF.index)
    return {p: round(100 * s[DF.phase == p].mean(), 1) for p in ORDER}


def header(txt: str) -> None:
    print("\n" + "=" * 72 + f"\n{txt}\n" + "=" * 72)


# ----------------------------------------------------------------------------
header("DADOS")
print(DF.groupby("phase", observed=True).agg(
    n=("delay", "size"),
    delay_med=("delay", "median"),
    delay_p95=("delay", lambda x: np.percentile(x, 95)),
    delay_max=("delay", "max"),
    ativas=("delay", lambda x: int((x > 0).sum())),
))

# ----------------------------------------------------------------------------
header(f"1. MODELO DO DOCENTE  (algorithm = {MODEL['algorithm']})")
mad_floor, thr, minfeat = MODEL["mad_floor"], MODEL["score_threshold"], MODEL["min_anomalous_features"]
flags_por_feature = {}
for feat, params in MODEL["features"].items():
    col = COLMAP[feat]
    scale = max(params["mad"], mad_floor)
    flags = (DF[col] - params["median"]).abs() / scale > thr
    flags_por_feature[col] = flags
    print(f"  {feat:22s} median={params['median']:9.2f} mad={params['mad']:.2f} "
          f"-> escala={scale:.2f} | anomalas %/fase: {pct(flags)}")
n_anom = sum(flags_por_feature.values())
apply = n_anom >= minfeat
print(f"  decisao 'apply' (>= {minfeat} features) %/fase: {pct(apply)}  | total {int(apply.sum())}/100")
tp = int((apply & (DF.phase == "stress")).sum())
fp = int((apply & (DF.phase != "stress")).sum())
print(f"  recall stress = {tp}/60 = {tp/60:.0%}   falsos 'apply' fora de stress = {fp}/40 = {fp/40:.0%}")

# ----------------------------------------------------------------------------
header("2. CONSERTO A  -  z-score modificado com MAD sobre baseline ATIVO")
ba = DF.loc[(DF.phase == "baseline") & (DF.delay > 0), "delay"].to_numpy()
med, mad = np.median(ba), np.median(np.abs(ba - np.median(ba)))
print(f"  baseline ativo n={len(ba)} valores={sorted(ba.astype(int))}  median={med:.0f} MAD={mad:.0f}")
for k in (3.5, 5):
    lo, hi = med - k * mad / 0.6745, med + k * mad / 0.6745
    print(f"  |M|>{k}: %/fase {pct(0.6745 * (DF.delay - med).abs() / mad > k)}  (fora de [{lo:.0f},{hi:.0f}] us)")

# ----------------------------------------------------------------------------
header("3. CONSERTO B  -  escala robusta Qn (Rousseeuw-Croux)")
def qn(x):
    x = np.sort(np.asarray(x, float)); n = len(x)
    d = np.abs(x[:, None] - x[None, :])[np.triu_indices(n, 1)]
    if d.size == 0:
        return 0.0
    h = n // 2 + 1
    d.sort()
    return 2.2219 * d[max(h * (h - 1) // 2 - 1, 0)]
for label, arr in [("baseline BRUTO", DF.loc[DF.phase == "baseline", "delay"].to_numpy()),
                   ("baseline ATIVO", ba)]:
    q, m = qn(arr), np.median(arr)
    print(f"  {label:15s} median={m:6.1f} Qn={q:6.1f} MAD={np.median(np.abs(arr - np.median(arr))):.1f}")
    if q > 0:
        print(f"      L = median + 3*Qn = {m + 3 * q:.0f} us  ->  %/fase {pct(DF.delay > m + 3 * q)}")

# ----------------------------------------------------------------------------
header("4. LIMIAR EMPIRICO  -  p75 do baseline bruto + bootstrap")
base = DF.loc[DF.phase == "baseline", "delay"].to_numpy()
L = float(np.percentile(base, 75))
print(f"  L = p75(baseline bruto) = {L:.1f} us  ->  %/fase {pct(DF.delay > L)}")
rng = np.random.default_rng(42)
bs = np.percentile(rng.choice(base, size=(10000, len(base)), replace=True), 75, axis=1)
print(f"  bootstrap: media={bs.mean():.1f}  IC95%=[{np.percentile(bs, 2.5):.1f},{np.percentile(bs, 97.5):.1f}]  CV={bs.std() / bs.mean():.0%}")
uniq = np.sort(DF.delay.unique())
print("  zonas mortas (gap>20us, 50..200):",
      [(float(a), float(b)) for a, b in zip(uniq[:-1], uniq[1:]) if b - a > 20 and 50 < a < 200])
for Lt in (100, 110, 120, 133):
    print(f"    L={Lt}: %/fase {pct(DF.delay > Lt)}")

# ----------------------------------------------------------------------------
header("5. PERSISTENCIA  -  CUSUM e EWMA no lugar da janela fixa W=5")
seq = DF.delay.to_numpy(float)
sigma = 1.4826 * np.median(np.abs(ba - np.median(ba)))
for mu0, tag in [(np.median(base), "mu0 = mediana baseline BRUTO (0)"), (med, "mu0 = mediana baseline ATIVO (137)")]:
    kC, hC = 0.5 * sigma, 5 * sigma
    sh = np.zeros(len(seq))
    for i in range(1, len(seq)):
        sh[i] = max(0.0, sh[i - 1] + (seq[i] - mu0) - kC)
    al = sh > hC
    pre = int((al & (DF.index.to_numpy() < 20)).sum())
    print(f"  CUSUM {tag:34s} k={kC:.0f} h={hC:.0f} -> %/fase {pct(al)}  | alarmes antes de stress: {pre}")
lam = 0.3
z = np.zeros(len(seq)); z[0] = np.median(base)
for i in range(1, len(seq)):
    z[i] = lam * seq[i] + (1 - lam) * z[i - 1]
ucl = np.median(base) + 3 * sigma * np.sqrt(lam / (2 - lam))
print(f"  EWMA lambda={lam} UCL={ucl:.1f} -> %/fase {pct(z > ucl)}")

# ----------------------------------------------------------------------------
header("6. CHANGE-POINT offline  (requer 'ruptures'; senao corte unico ingenuo)")
try:
    import ruptures as rpt
    bkps = rpt.Pelt(model="rbf").fit(seq).predict(pen=10)
    print(f"  ruptures PELT breakpoints: {bkps}  (esperado ~[20, 80, 100])")
except Exception as e:
    best, bi = -1.0, None
    for i in range(2, len(seq) - 2):
        d = abs(seq[:i].mean() - seq[i:].mean())
        if d > best:
            best, bi = d, i
    print(f"  ({type(e).__name__}) melhor corte unico por delta-media: idx {bi} (delta={best:.0f}); esperado 20")

# ----------------------------------------------------------------------------
header("7. MULTIVARIADO  (delay, thp, prb;  treino = baseline)")
from scipy.stats import chi2
from sklearn.covariance import MinCovDet
from sklearn.ensemble import IsolationForest
from sklearn.neighbors import LocalOutlierFactor
from sklearn.preprocessing import StandardScaler

X = DF[FEATS].to_numpy(float)
Xtr = DF.loc[DF.phase == "baseline", FEATS].to_numpy(float)
try:
    d2 = MinCovDet(random_state=0).fit(Xtr).mahalanobis(X)
    print(f"  Mahalanobis-MCD  corte chi2_0.975(3)={chi2.ppf(0.975, 3):.2f}  -> %/fase {pct(d2 > chi2.ppf(0.975, 3))}")
except Exception as e:
    print("  MCD falhou:", e)
sc = StandardScaler().fit(Xtr)
for c in (0.1, 0.2):
    p = IsolationForest(contamination=c, n_estimators=200, random_state=0).fit(sc.transform(Xtr)).predict(sc.transform(X))
    print(f"  IsolationForest(contamination={c})  -> %/fase {pct(p == -1)}")
p = LocalOutlierFactor(n_neighbors=10, novelty=True).fit(sc.transform(Xtr)).predict(sc.transform(X))
print(f"  LOF(k=10)  -> %/fase {pct(p == -1)}")

# ----------------------------------------------------------------------------
header("8. SUPERVISIONADO  -  delay -> P(stress)  (validacao do limiar)")
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score, roc_curve
from sklearn.model_selection import cross_val_score
from sklearn.tree import DecisionTreeClassifier, export_text

Xd = DF[["delay"]].to_numpy()
tree = DecisionTreeClassifier(max_depth=1, random_state=0).fit(Xd, Y_STRESS)
print(f"  arvore prof.1: split em delay <= {tree.tree_.threshold[0]:.1f} us")
print("   ", export_text(tree, feature_names=["delay"]).replace("\n", "\n    ").strip())
print(f"  acuracia 5-fold CV = {cross_val_score(DecisionTreeClassifier(max_depth=1, random_state=0), Xd, Y_STRESS, cv=5).mean():.2f}")
fpr, tpr, thrs = roc_curve(Y_STRESS, DF.delay.to_numpy())
j = np.argmax(tpr - fpr)
print(f"  ROC AUC (delay isolado) = {roc_auc_score(Y_STRESS, DF.delay):.3f}")
print(f"  Youden-J: L* = {thrs[j]:.1f} us  (TPR={tpr[j]:.2f}, FPR={fpr[j]:.2f})")
lg = LogisticRegression(max_iter=1000).fit(DF[FEATS], Y_STRESS)
print(f"  logistica coefs (delay,thp,prb) = {lg.coef_[0].round(4)}  AUC in-sample = {roc_auc_score(Y_STRESS, lg.predict_proba(DF[FEATS])[:, 1]):.3f}")

# ----------------------------------------------------------------------------
header("9. LIMIAR ABSOLUTO POR ORCAMENTO DE RADIO")
st = DF.loc[DF.phase == "stress", "delay"].to_numpy()
for La in (105.5, 150.0, 200.0):
    w5 = sum(bool((st > La)[i:i + 5].all()) for i in range(len(st) - 4))
    print(f"  L={La:6.1f} us -> %/fase {pct(DF.delay > La)}  | janelas W5 stress = {w5}/56")

print("\nFIM")
