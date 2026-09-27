{% test row_count_between(model, min_rows, max_rows) %}
{#
    Model-level volume check: catches a truncated load (too few rows) or an
    accidental fan-out join (too many) that column-level tests can't see.
#}
select count(*) as row_count
from {{ model }}
having count(*) < {{ min_rows }}
    or count(*) > {{ max_rows }}
{% endtest %}
