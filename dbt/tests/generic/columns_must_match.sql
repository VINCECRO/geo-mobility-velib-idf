-- dbt/tests/generic/columns_must_match.sql
{% test columns_must_match(model, column_a, column_b, tolerance=0) %}
/*
Test if two colomns values are equal

Args:
    tolerance: no difference accepted
*/

WITH comparison AS (
    SELECT 
        *,
        {{ column_a }} AS col_a,
        {{ column_b }} AS col_b,
        COALESCE({{ column_a }}, 0) - COALESCE({{ column_b }}, 0) AS difference
    FROM {{ model }}
    WHERE 
        -- Valeurs différentes
        {{ column_a }} IS DISTINCT FROM {{ column_b }}
        -- Au-delà de la tolérance
        AND ABS(COALESCE({{ column_a }}, 0) - COALESCE({{ column_b }}, 0)) > {{ tolerance }}
)

SELECT 
    *,
    CONCAT(
        'Mismatch: ', '{{ column_a }}', ' (', col_a, ') ',
        '≠ ', '{{ column_b }}', ' (', col_b, ') ',
        'Δ=', difference
    ) AS error_message
FROM comparison

{% endtest %}
