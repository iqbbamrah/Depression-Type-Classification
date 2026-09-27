-- The notebook does a stratified 80/20 train/test split, which needs every one
-- of the 12 classes present with enough rows that the 20% test split still
-- gets a couple of examples of it. Returns each class that's missing or too
-- small (the smallest real class currently has 21 rows).
with expected as (

    select unnest(range(0, 12)) as depression_type

),

class_counts as (

    select depression_type, count(*) as n_rows
    from {{ ref('fct_mental_health_model_input') }}
    group by 1

)

select
    expected.depression_type,
    coalesce(class_counts.n_rows, 0) as n_rows
from expected
left join class_counts using (depression_type)
where coalesce(class_counts.n_rows, 0) < 10
