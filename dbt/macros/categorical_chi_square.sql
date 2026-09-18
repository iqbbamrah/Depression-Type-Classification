{% macro categorical_chi_square(column_name, source_relation, target_column='depression_type') %}
select
    '{{ column_name }}' as variable,
    sum(power(cell.observed - cell.expected, 2) / nullif(cell.expected, 0)) as chi_square_statistic,
    (
        (select count(distinct {{ column_name }}) from {{ source_relation }}) - 1
    ) * (
        (select count(distinct {{ target_column }}) from {{ source_relation }}) - 1
    ) as degrees_of_freedom,
    (select count(*) from {{ source_relation }}) as n_observations
from (
    select
        r.{{ column_name }}   as col_value,
        r.{{ target_column }} as target_value,
        count(*)                                        as observed,
        (row_totals.row_total * col_totals.col_total)
            / cast(grand_total.n as double)               as expected
    from {{ source_relation }} r
    inner join (
        select {{ column_name }} as col_value, count(*) as row_total
        from {{ source_relation }}
        group by 1
    ) row_totals
        on r.{{ column_name }} = row_totals.col_value
    inner join (
        select {{ target_column }} as target_value, count(*) as col_total
        from {{ source_relation }}
        group by 1
    ) col_totals
        on r.{{ target_column }} = col_totals.target_value
    cross join (
        select count(*) as n from {{ source_relation }}
    ) grand_total
    group by 1, 2, row_totals.row_total, col_totals.col_total, grand_total.n
) cell
{% endmacro %}
