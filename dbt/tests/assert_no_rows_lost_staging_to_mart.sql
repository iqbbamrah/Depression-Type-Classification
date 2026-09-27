-- The mart keeps every respondent, so any difference in row count between
-- staging and the mart means a filter or join somewhere is dropping (or
-- duplicating) rows.
with counts as (

    select
        (select count(*) from {{ ref('stg_mental_health__survey_responses') }}) as staging_rows,
        (select count(*) from {{ ref('fct_mental_health_model_input') }})       as mart_rows

)

select *
from counts
where staging_rows <> mart_rows
