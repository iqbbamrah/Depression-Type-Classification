{#
    Model-ready table consumed directly by the scikit-learn classifier.
    All predictors from staging are retained: the source analysis's chi-square
    and correlation checks (see int_mental_health__categorical_chi_square and
    int_mental_health__numeric_correlations) informed model *choice*
    (Logistic Regression over Naive Bayes, given correlated/non-independent
    predictors) rather than dropping any features, so none are excluded here.
#}

select
    response_id,
    gender,
    age,
    education_level,
    employment_status,
    symptoms,
    low_energy,
    low_self_esteem,
    search_depression_online,
    worsening_depression,
    overeating_level,
    eating_frequency,
    social_media_hours,
    social_media_while_eating,
    sleep_hours,
    nervous_level,
    depression_score,
    coping_methods,
    self_harm,
    mental_health_support,
    suicide_attempts,
    depression_type
from {{ ref('stg_mental_health__survey_responses') }}
