-- dbt/tests/generic/sum_must_match.sql
{% test sum_must_match(model, column_a, column_b,column_c ) %}
/*
Test if a+b=c

Args:
    tolerance: no difference accepted
*/

WITH comparison AS (
    SELECT 
        *,
        {{ column_a }} AS col_a,
        {{ column_b }} AS col_b,
        {{ column_c }} AS col_c

    FROM {{ model }}
    WHERE 
        -- La somme n'est pas cohérente
        ABS(COALESCE({{ column_a }}, 0) + COALESCE({{ column_b }}, 0)) != COALESCE({{ column_c }}, 0))

SELECT 
    *,
    CONCAT(
        'Mismatch: ', '{{ column_a }}', ' (', col_a, ') ',
        '+', '{{ column_b }}', ' (', col_b, ') ','≠ ',
        '{{ column_c }}', ' (', col_c, ') '
    ) AS error_message
FROM comparison

{% endtest %}
