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
.venv/Scripts/dbt seed                              # loads the CSV into DuckDB
.venv/Scripts/dbt run                                # builds staging -> intermediate -> marts
.venv/Scripts/dbt test                               # 24 tests: not_null / unique / accepted_values
.venv/Scripts/dbt docs generate && .venv/Scripts/dbt docs serve   # browsable lineage + column docs
```

`fct_mental_health_model_input` is the table the classifier reads — see [Depression Type Classification Analysis.ipynb](<Depression Type Classification Analysis.ipynb>) for the Python side. Its first cell reads directly from the DuckDB mart (`dbt/depression.duckdb`) rather than the raw CSV, so it depends on `dbt seed && dbt run` having been run first.

### Orchestration (Apache Airflow)

The manual `dbt seed && dbt run && dbt test` sequence above is also wired up as an [Airflow](https://airflow.apache.org/) DAG (`airflow/`), so the whole pipeline — data build, then docs + model training in parallel once the data passes its tests — can run as one orchestrated unit instead of by hand:

```
dbt_seed -> dbt_run -> dbt_test -> [dbt_docs_generate, train_and_evaluate_model]
```

`train_and_evaluate_model` runs the same notebook linked above headlessly (`jupyter nbconvert --execute`), so the DAG's dependency on `dbt_test` is real: the classifier only trains against dbt output that has actually passed its tests, not just data that happens to be sitting in the warehouse.

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
