{#
  Purpose:
    Returns a numeric quality score (0–5) for a FAOSTAT Flag value.
    Used consistently across all staging models to avoid
    duplicating this logic.

  Args:
    flag_column (string): SQL column reference containing the flag code

  Returns:
    INT64: Quality score where 5 = official data, 0 = missing

  Usage:
    {{ flag_quality_score('flag_code') }}

  FAOSTAT Flag Quality Scores:
    5 — Official ('') or Questionnaire ('Q')
    4 — Aggregate (A), Standardized (S), Calculated (C), Intl Org (X)
    3 — FAO Estimate (F), Estimated (E), Provisional (P)
    2 — Imputed (I), Unofficial (T), Mirror (R)
    1 — Not Significant (N)
    0 — Missing (M) — no data available
#}

{% macro flag_quality_score(flag_column) %}
    case {{ flag_column }}
        when ''  then 5    -- Official (empty string = highest quality)
        when 'Q' then 5    -- Questionnaire
        when 'A' then 4    -- Aggregate
        when 'S' then 4    -- Standardized
        when 'C' then 4    -- Calculated
        when 'X' then 4    -- International Organization
        when 'F' then 3    -- FAO Estimate
        when 'E' then 3    -- Estimated
        when 'P' then 3    -- Provisional
        when 'I' then 2    -- Imputed
        when 'T' then 2    -- Unofficial
        when 'R' then 2    -- Mirror Estimate
        when 'N' then 1    -- Not Significant
        when 'M' then 0    -- Missing
        else null
    end
{% endmacro %}