-- Guards the chi-square / correlation macros against regressions: a correlation
-- must exist (null means a constant column) and fall in [-1, 1], and a
-- chi-square statistic can't be negative or have fewer than 1 degree of freedom.
select 'correlation' as check_name, variable
from {{ ref('int_mental_health__numeric_correlations') }}
where correlation_with_target is null
   or correlation_with_target not between -1 and 1

union all

select 'chi_square' as check_name, variable
from {{ ref('int_mental_health__categorical_chi_square') }}
where chi_square_statistic is null
   or chi_square_statistic < 0
   or degrees_of_freedom < 1
