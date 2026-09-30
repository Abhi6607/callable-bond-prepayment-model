# Modeling Mortgage Prepayment as a Callable Bond: A Survival Analysis Approach

**Abhinav Mallampati**
Third-year B.Tech, Mathematics and Computer Science, Rajiv Gandhi Institute of Petroleum Technology (RGIPT)

---

## 1. Motivation

A residential mortgage-backed security is, in essence, short an embedded call option: the borrower has the right, but not the obligation, to "call away" the loan by prepaying it, typically by refinancing when market rates fall below their original note rate. This project models that prepayment behavior directly as a time-to-event problem using survival analysis, following a suggestion from Tom Schopflocher (Managing Director, Structured Finance Research, S&P Global Ratings) to build a callable-bond prepayment model using the Cox proportional hazards framework.

The goal was to answer: **what factors predict when a mortgage loan will prepay, and how does the borrower's refinancing incentive evolve that risk over the life of the loan?**

## 2. Data

**Source:** Freddie Mac Single-Family Loan-Level Dataset (SFLLD), 2015 origination vintage, accessed via Freddie Mac's Clarity Data Intelligence portal. The dataset provides two linked files per vintage:

- **Origination file** — static loan characteristics at the time of origination (credit score, original interest rate, LTV, DTI, loan term, property state, etc.), one row per loan.
- **Performance file** — monthly loan-level performance history (current UPB, delinquency status, loan age, zero-balance code), one row per loan per month.

50,000 loans were sampled from the 2015 vintage; of these, 12,380 had traceable monthly performance history in the sample window used.

**Note on the "sample files" pitfall:** Freddie Mac's site also distributes a small format-demonstration "Sample Files" pack, intended purely to illustrate file layout rather than for analysis — the origination and performance records in that pack do not share matching loan IDs. This was identified and discarded early; the real vintage-year sample files (`sample_orig_2015.txt` / `sample_pref_2015.txt`) were used for all actual modeling.

**Event definition:** A loan is coded as experiencing the event of interest (`event = 1`) if its terminal zero-balance code is `01` (Prepaid or Matured, isolated to early payoffs by loan age relative to original term). All other exits — short sale (`03`), REO disposition (`09`), and other codes — are treated as censored in the baseline model, a simplification discussed in Section 6.

**Duration:** loan age (months) at the last observed performance record.

## 3. Methodology

### 3.1 Data pipeline
A parser was built in base R (no external dependencies) to:
1. Read the pipe-delimited origination and performance files with explicit column typing (avoiding silent coercion of leading-zero string codes, e.g. zero-balance code `"01"`, into numeric values — an early bug caught during development).
2. Collapse monthly performance records to one terminal record per loan.
3. Recode Freddie Mac's missing-data placeholder (DTI = 999) to `NA`.
4. Merge event/duration data with origination covariates.

### 3.2 Exploratory analysis: Kaplan-Meier estimation
Kaplan-Meier survival curves were fit both unconditionally and stratified by original interest rate bucket, to visualize raw prepayment behavior before fitting any model.

### 3.3 Baseline Cox proportional hazards model
A Cox model was fit using static, origination-time covariates:

```
coxph(Surv(duration, event) ~ orig_rate + credit_score + orig_ltv + orig_dti + orig_loan_term + num_borrowers)
```

### 3.4 Time-varying extension: refinancing incentive
Following feedback from Tom Schopflocher, the model was extended to use a **time-varying refinancing incentive** covariate rather than the static origination rate — the economically correct driver of prepayment behavior. This was constructed as:

```
rate_incentive(t) = orig_rate − market_rate(t)
```

where `market_rate(t)` is the Freddie Mac Primary Mortgage Market Survey (PMMS) 30-year fixed rate prevailing at each calendar month, sourced from FRED (`MORTGAGE30US`) and matched to each loan's monthly `reporting_period`. The dataset was restructured into counting-process (start, stop, event) format to allow this monthly-varying covariate, and refit as:

```
coxph(Surv(tstart, tstop, event) ~ rate_incentive + credit_score + orig_ltv)
```

### 3.5 Diagnostics
The proportional hazards assumption was tested for every model using `cox.zph()`, which tests whether each covariate's effect on the hazard is constant over time — a core assumption of the Cox framework.

## 4. Results

### 4.1 Kaplan-Meier: rate-stratified survival
Loans were bucketed by original interest rate `(0,3], (3,3.5], (3.5,4], (4,4.5], (4.5,10]`. The resulting survival curves separated cleanly and monotonically: higher-original-rate loans consistently showed faster, deeper prepayment, exactly as refinancing-incentive theory predicts. A log-rank test confirmed the separation was highly significant (χ² = 136, df = 4, p < 2×10⁻¹⁶).

All curves showed a common shape: a slow decline through month ~40, a steep drop between months ~45–75, and a flattening thereafter. Given the 2015 vintage, this window corresponds almost exactly to the 2020–2021 refinancing wave triggered by historically low mortgage rates — the data visibly reflects real macroeconomic history.

### 4.2 Baseline Cox model
| Covariate | HR | p-value | Interpretation |
|---|---|---|---|
| orig_rate | 1.438 | < 2×10⁻¹⁶ | Each 1-point increase in original rate → 44% higher prepayment hazard |
| orig_ltv | 1.002 | 9.6×10⁻⁸ | Small but significant positive effect |
| num_borrowers | 1.067 | 0.003 | Modest positive effect, suggestive rather than strong |
| credit_score | 0.9998 | 0.50 | Not significant once rate is controlled for |
| orig_dti | 1.0007 | 0.54 | Not significant |
| orig_loan_term | 0.9997 | 0.16 | Not significant |

Concordance = 0.554. The model was jointly highly significant (likelihood ratio test p < 2×10⁻¹⁶), but `cox.zph()` showed the proportional hazards assumption was violated, most strongly for `orig_rate` (χ² = 53.4, p = 2.7×10⁻¹³) — consistent with the KM plot showing rate's effect concentrated in a specific historical window rather than constant over the loan's life.

### 4.3 Time-varying model
| Covariate | HR | p-value |
|---|---|---|
| rate_incentive | 1.316 | < 2×10⁻¹⁶ |
| orig_ltv | 1.002 | 2.4×10⁻⁴ |
| credit_score | 1.0003 | 0.18 |

The dynamic refinancing-incentive variable confirmed the same directional story as the static model (HR ≈ 1.3), now correctly measuring incentive at each point in the loan's life rather than only at origination.

**Notably, the proportional hazards violation persisted** (`rate_incentive` χ² = 58.0, p = 2.6×10⁻¹⁴) even after making the covariate time-varying, and concordance did not meaningfully improve (0.548). This was an unexpected but informative result.

## 5. Interpretation: burnout

The persistence of non-proportionality after accounting for time-varying incentive points to **burnout** — a well-documented phenomenon in mortgage prepayment modeling in which borrowers who face a strong refinancing incentive but do not act on it (due to credit constraints, moving costs, inattention, or other frictions) become a self-selected, progressively less rate-sensitive subpopulation over time. As a result, an equivalent incentive level does not move the same fraction of the remaining loan pool at different points in the loan's life — precisely what the persistent PH violation indicates. This diagnosis was confirmed as consistent with known industry behavior by Tom Schopflocher.

## 6. Limitations and future work

- **Competing risks simplification.** The event definition treats all non-prepayment exits (short sale, REO disposition, etc.) as censored, rather than as distinct competing risks. A competing-risks framework (e.g., Fine-Gray subdistribution hazards or cause-specific hazards) would more accurately separate prepayment from default-driven exits. This question was posed to Dr. Anna Matuszyk, whose research focuses on competing-risk survival models for credit/prepayment risk.
- **Burnout is not explicitly modeled.** The current model captures burnout only as a diagnosed limitation, not as an explicit covariate. A natural extension is a nonlinear incentive term or an explicit cumulative-exposure "burnout factor," both standard approaches in the prepayment modeling literature.
- **Single vintage year.** Results are drawn from a single 2015 vintage sample; a fuller analysis would pool multiple vintages to test robustness across different rate environments.

## 7. Tools

R (base R for data parsing; `survival` package for Kaplan-Meier estimation, Cox regression, and diagnostics). Data sourced from Freddie Mac's Single-Family Loan-Level Dataset and FRED's `MORTGAGE30US` series.
