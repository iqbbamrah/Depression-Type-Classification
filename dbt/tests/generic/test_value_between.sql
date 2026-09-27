{% test value_between(model, column_name, min_value, max_value) %}
{#
    Fails on any row outside [min_value, max_value]. Used for ordinal/count
    scales too wide to list out with accepted_values. Nulls are left to
    not_null so each test reports exactly one kind of problem.
#}
select {{ column_name }}
from {{ model }}
where {{ column_name }} < {{ min_value }}
   or {{ column_name }} > {{ max_value }}
{% endtest %}
