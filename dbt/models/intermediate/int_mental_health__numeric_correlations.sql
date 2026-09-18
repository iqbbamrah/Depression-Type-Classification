{%- set predictor_columns = [
    'gender', 'age', 'education_level', 'employment_status', 'symptoms',
    'low_energy', 'low_self_esteem', 'search_depression_online', 'worsening_depression',
    'overeating_level', 'eating_frequency', 'social_media_hours', 'social_media_while_eating',
    'sleep_hours', 'nervous_level', 'depression_score', 'coping_methods', 'self_harm',
    'mental_health_support', 'suicide_attempts'
] -%}

{#
    SQL analog of the pandas correlation matrix from the original notebook,
    reduced to each predictor's correlation with the target (depression_type)
    rather than the full pairwise matrix, since that's what the intermediate
    layer needs to surface for downstream use.
#}

{% for column_name in predictor_columns %}
{{ correlation_with_target(column_name, ref('stg_mental_health__survey_responses')) }}
{% if not loop.last %}union all{% endif %}
{% endfor %}
