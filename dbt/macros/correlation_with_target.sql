{% macro correlation_with_target(column_name, source_relation, target_column='depression_type') %}
select
    '{{ column_name }}' as variable,
    corr({{ column_name }}, {{ target_column }}) as correlation_with_target
from {{ source_relation }}
{% endmacro %}
