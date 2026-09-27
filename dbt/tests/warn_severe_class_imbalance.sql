{{ config(severity='warn') }}

-- Informational, not blocking: fires when the largest class outnumbers the
-- smallest by more than 20x. It does fire on this dataset (627 vs 21, ~30x) -
-- that's expected, and it's exactly why the analysis evaluates on Macro F1
-- rather than accuracy. Severity warn so it's reported without stopping training.
with class_counts as (

    select depression_type, count(*) as n_rows
    from {{ ref('fct_mental_health_model_input') }}
    group by 1

)

select
    max(n_rows)                                  as largest_class_rows,
    min(n_rows)                                  as smallest_class_rows,
    round(max(n_rows) * 1.0 / min(n_rows), 1)    as imbalance_ratio
from class_counts
having max(n_rows) > 20 * min(n_rows)
