{%- set categorical_columns = [
    'gender',
    'education_level',
    'employment_status',
    'search_depression_online',
    'mental_health_support',
    'social_media_while_eating',
    'symptoms',
    'worsening_depression',
    'eating_frequency',
    'coping_methods',
    'self_harm',
    'suicide_attempts'
] -%}

{#
    Reproduces, in SQL, the chi-square test of independence against depression_type
    that the original analysis ran in pandas/SciPy (scipy.stats.chi2_contingency)
    for each candidate categorical predictor. Used downstream purely as a
    documented diagnostic (per the source analysis, no features were actually
    dropped based on these results) rather than as a feature-selection filter.
#}

{% for column_name in categorical_columns %}
{{ categorical_chi_square(column_name, ref('stg_mental_health__survey_responses')) }}
{% if not loop.last %}union all{% endif %}
{% endfor %}
