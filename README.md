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
├── data/                      # dataset (or link, given Mendeley source/licensing)
├── notebooks/
│   └── depression_type_classification.ipynb
├── report/
│   └── depression_type_classification_report.pdf
└── README.md
```

## Possible extensions
- Test regularized multinomial logistic regression (L1/L2) or a gradient-boosted classifier to see if performance improves further, and whether L1 regularization sharpens the feature-importance picture.
- Per-class error analysis on the confusion matrix (e.g. classes 2, 5, and 9 show more off-diagonal confusion) to understand which depression types are hardest to separate and why.
- SHAP values instead of raw standardized coefficients, for a more robust, interaction-aware view of feature importance.

---
*This project analyzes depression classification for educational/research purposes using an anonymized academic dataset. It is not a diagnostic tool and should not be interpreted as clinical guidance.*
