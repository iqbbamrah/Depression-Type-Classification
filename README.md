# Depression-Type-Classification
Project completed for Statistics for Data Science Course in the University of Waterloo WATSPEED Data Science Certificate Program.

# Predicting Depression Type from Lifestyle & Behavioural Factors

Multi-class classification of depression type (12 classes) from psychological, behavioural, demographic, and support-related survey variables, with a focus on choosing the right evaluation metric and model for imbalanced, non-independent predictors.

## Problem

Depression isn't one condition — this dataset labels 12 distinct types (from "no clinically significant" through major, seasonal, postpartum, and psychotic depression). The goal was to test whether lifestyle and behavioral survey data (sleep, social media use, coping methods, support access, etc.) combined with psychological indicators could predict which type a respondent falls into, and — just as important — to reason carefully about *why* one modeling approach would outperform another given the structure of the data, rather than just reporting whichever model scored higher.

## Data

- **Source:** [Mendeley Data — Mental Health Dataset (Choudhury, 2022)](https://data.mendeley.com/datasets/xppzm3kv9g/2)
- 1,998 observations, 21 variables, 12 target classes (`Depression_Type`), 0 missing values, 0 duplicates.
- Variables span numerical (age, sleep hours, social media hours), ordinal (low energy, low self-esteem, nervousness, overeating level, depression score), and nominal categorical (gender, education, employment, symptoms, coping methods, self-harm, suicide attempts, etc.) — each type analyzed with an appropriate statistical method rather than treating everything as generic numeric input.

## Data Pipeline

The data-prep layer that used to live in pandas notebook cells has been rebuilt as a proper [dbt-core](https://docs.getdbt.com/) project against a local [DuckDB](https://duckdb.org/) warehouse (`dbt/`) — no cloud warehouse required. Modeling and evaluation are unchanged and still run in scikit-learn; only how the model-ready table gets built has moved.

```
dbt/
├── seeds/
│   └── mental_health_survey.csv          # raw Mendeley export, loaded via `dbt seed`
├── models/
│   ├── staging/
│   │   └── stg_mental_health__survey_responses.sql   # rename to snake_case, cast types
│   ├── intermediate/
│   │   ├── int_mental_health__categorical_chi_square.sql   # chi-square test of independence
│   │   │                                                    #   vs. Depression_Type, in SQL, for
│   │   │                                                    #   every categorical predictor the
│   │   │                                                    #   original notebook tested
│   │   └── int_mental_health__numeric_correlations.sql     # each predictor's correlation with
│   │                                                        #   the target, via DuckDB's corr()
│   └── marts/
│       └── fct_mental_health_model_input.sql   # final model-ready table read by sklearn
├── macros/                                # reusable chi-square / correlation SQL generators
├── tests/
│   ├── generic/                           # custom reusable tests: value_between, row_count_between
│   └── assert_*.sql / warn_*.sql          # singular business-logic tests (see Data quality below)
├── dbt_project.yml
└── profiles.yml                           # local DuckDB target, no credentials needed
```

**Lineage:**

![dbt lineage graph](dbt/docs_assets/lineage_graph.svg)

**Why SQL for the chi-square/correlation step, not just feature engineering:** the original analysis used `scipy.stats.chi2_contingency` and pandas `.corr()` as *diagnostics* that informed model choice (Logistic Regression over Naive Bayes, given correlated/non-independent predictors) rather than as a feature-selection filter — no columns were actually dropped. `int_mental_health__categorical_chi_square` reproduces the same test (contingency table → expected frequencies → chi-square statistic, done via `join`s and window aggregates rather than `scipy`) so that diagnostic is now a versioned, testable SQL model instead of a one-off notebook cell. It was validated against the original notebook's findings: `gender` and `suicide_attempts` — the two variables the original analysis flagged as *not* significantly associated with the target — come out with the lowest chi-square statistics relative to their degrees of freedom here too.

**Running it:**

```bash
cd dbt
python -m venv .venv
.venv/Scripts/pip install -r requirements.txt      # dbt-core + dbt-duckdb
.venv/Scripts/dbt build                              # seed -> staging -> intermediate -> marts, testing each node before anything downstream of it
.venv/Scripts/dbt docs generate && .venv/Scripts/dbt docs serve   # browsable lineage + column docs
```

`fct_mental_health_model_input` is the table the classifier reads — see [Depression Type Classification Analysis.ipynb](<Depression Type Classification Analysis.ipynb>) for the Python side. Its first cell reads directly from the DuckDB mart (`dbt/depression.duckdb`) rather than the raw CSV, so it depends on `dbt build` having been run first.

### Data quality

57 tests run on every build (56 blocking, 1 warning). `dbt build` stops at the first failing layer, so bad data never reaches the mart the model trains on:

| Layer | What's checked |
|---|---|
| Seed | Row volume (1,900–2,100), target never null |
| Staging | Every one of 22 columns `not_null` and range-checked against the dataset's codebook (`accepted_values` for code sets, custom `value_between` for wider scales); `response_id` is an md5 of all raw columns, so its `unique` test doubles as a duplicate-row check |
| Intermediate | Correlations non-null and within [-1, 1]; chi-square statistics non-negative with ≥1 degree of freedom |
| Mart | **Enforced model contract** — dbt refuses to build the table if a column is missing, renamed, or changes type, so the notebook can't silently receive a different schema. Plus: no rows lost between staging and mart, and all 12 classes present with ≥10 rows (so the stratified 80/20 split stays valid) |
| Mart (warn) | Class-imbalance ratio > 20x — fires on this dataset (627 vs 21 rows, ~30x) by design, as a reminder of why Macro F1 is the headline metric; reported but never blocks training |

`store_failures` is on, so any failing test's offending rows can be inspected directly in DuckDB at `main_dbt_test__audit.<test_name>`.

### Orchestration (Apache Airflow)

The pipeline is also orchestrated as an [Airflow](https://airflow.apache.org/) DAG (`airflow/`), with a data-quality gate at every layer:

```
dbt_build_seeds -> dbt_build_staging -> dbt_build_intermediate -> dbt_build_marts
  -> quality_report -> train_and_evaluate_model -> dbt_docs_generate
```

- **Layer-by-layer gates:** each `dbt_build_<layer>` task builds *and tests* one layer (`dbt build --indirect-selection buildable`, so cross-layer tests like "no rows lost staging → mart" wait until both sides exist). A failure stops the run at that layer — a bad staging row means intermediate and marts never build.
- **`quality_report`:** runs even when a layer failed (`trigger_rule="all_done"`), reads every layer's `run_results.json`, and logs pass/warn/fail counts plus each non-passing test by name. It fails the run on any blocking failure; warn-severity tests are reported but don't block.
- **`train_and_evaluate_model`** runs the notebook headlessly (`jupyter nbconvert --execute`) only after `quality_report` passes, so the classifier only ever trains on data that passed every test.
- **Strictly linear on purpose:** DuckDB allows only one read-write process per database file, so no two tasks touch it at once.

Airflow doesn't support native Windows (it needs POSIX `os.register_at_fork`, confirmed by hitting that exact error trying to run it locally), so this runs via Docker:

```bash
cd airflow
docker compose up   # first run also builds the image (dbt + the sklearn/jupyter stack on top of apache/airflow:3.3.2)
```

Then open `http://localhost:8080` (`airflow standalone` prints a generated admin password to the container logs on first run) and trigger `depression_type_classification_pipeline` manually — it has no cron schedule, since the source data is a static one-time survey export, not something that gets new rows on a recurring basis; an automatic schedule would just be decorative here. `docker compose` mounts the whole repo into the container, so DAG runs operate on the exact same `dbt/` and notebook files documented above.

## Methodology

- **EDA:** class-distribution check confirmed significant imbalance across the 12 depression types — this drove the choice of evaluation metric later.
- **Categorical variables:** tested against the target using **Chi-square tests of independence**. Nearly all categorical variables (Symptoms, Coping_Methods, Employment_Status, Education_Level, etc.) showed statistically significant associations (p < 0.001). Gender and Suicide_Attempts did not.
- **Numerical/ordinal variables:** correlation analysis showed several psychological/behavioral predictors were moderately inter-correlated — i.e., not independent — which directly informed model choice (see below).
- **Modeling:** 80/20 stratified train/test split (preserves class proportions in an imbalanced multi-class problem). Compared:
  - **Logistic Regression** (standardized via a pipeline) — can model relationships between correlated predictors.
  - **Gaussian Naive Bayes** — assumes predictor independence, used as a contrasting baseline to test whether that assumption holds up in this data.
- **Evaluation:** both accuracy and **Macro F1-score** — Macro F1 was treated as the primary metric because it weights all 12 classes equally, which matters when several classes are rare.
- **Tools:** Python, pandas, scikit-learn (`LogisticRegression`, `GaussianNB`, `Pipeline`, `StandardScaler`, `train_test_split`), SciPy (`stats` — chi-square testing), matplotlib.

## Results

| Model | Accuracy | Macro F1 |
|---|---|---|
| **Logistic Regression** | **0.7175** | **0.8659** |
| Naive Bayes | 0.5325 | 0.7563 |

Logistic Regression outperformed Naive Bayes on both metrics, and — importantly — the Macro F1 gap shows the improvement wasn't just from getting majority classes right. It held up across the rarer depression types too.

**Top predictive signals** (by standardized coefficient magnitude): `SocialMedia_WhileEating`, `Low_SelfEsteem`, `Search_Depression_Online`, `Symptoms`, `Education_Level`, `Nervous_Level` — a mix of psychological and contextual/behavioral variables, not just one category.

## Key takeaways

- The correlation and chi-square results predicted the modeling outcome *before* any model was fit: since predictors were shown to be correlated/non-independent, Naive Bayes' core assumption was already known to be a poor fit for this data — the model comparison confirmed a hypothesis rather than being a blind horse race.
- Macro F1 vs. accuracy mattered in practice: on this imbalanced 12-class target, accuracy alone would have overstated how well the models handle rare depression types.
- Some intuitive predictors (sleep hours) were weak on their own, the model's actual signal came from a genuine mix of psychological state variables and contextual/behavioral ones — supporting the paper's framing of depression classification as multi-dimensional, not driven by any single factor.
- Feature importance ≠ causation — flagged explicitly, since interpreting logistic regression coefficients as causal drivers of depression type would overstate what this analysis supports.

## Repo structure
```
├── Data/
│   └── Mental Health Classification.csv
├── dbt/                                            # dbt-core + DuckDB data pipeline (see Data Pipeline above)
├── airflow/                                        # orchestrates the dbt + training pipeline (see Orchestration above)
├── Depression Type Classification Analysis.ipynb   # Jupyter notebook: EDA, chi-square, modeling, evaluation
├── requirements.txt                                # deps for running the notebook itself (pandas/sklearn/duckdb/jupyter)
├── Predicting Depression Type...pdf                # write-up
└── README.md
```

## Possible extensions
- Test regularized multinomial logistic regression (L1/L2) or a gradient-boosted classifier to see if performance improves further, and whether L1 regularization sharpens the feature-importance picture.
- Per-class error analysis on the confusion matrix (e.g. classes 2, 5, and 9 show more off-diagonal confusion) to understand which depression types are hardest to separate and why.
- SHAP values instead of raw standardized coefficients, for a more robust, interaction-aware view of feature importance.

---
*This project analyzes depression classification for educational/research purposes using an anonymized academic dataset. It is not a diagnostic tool and should not be interpreted as clinical guidance.*
