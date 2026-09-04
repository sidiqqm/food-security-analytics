{#
  Purpose:
    Returns human-readable label for FAOSTAT Flag codes.
    Used in documentation and dashboard tooltip.

  Args:
    flag_column (string): SQL column reference

  Usage:
    {{ flag_label('flag_code') }}
#}

{% macro flag_label(flag_column) %}
    case {{ flag_column }}
        when ''  then 'Official'
        when 'A' then 'Aggregate'
        when 'F' then 'FAO Estimate'
        when 'E' then 'Estimated'
        when 'P' then 'Provisional'
        when 'I' then 'Imputed'
        when 'T' then 'Unofficial'
        when 'C' then 'Calculated'
        when 'S' then 'Standardized'
        when 'R' then 'Mirror Estimate'
        when 'Q' then 'Questionnaire'
        when 'B' then 'Break in Series'
        when 'N' then 'Not Significant'
        when 'M' then 'Missing'
        when 'X' then 'International Organization'
        else 'Unknown'
    end
{% endmacro %}