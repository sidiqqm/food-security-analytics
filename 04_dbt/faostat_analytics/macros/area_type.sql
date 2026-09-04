{#
  Purpose:
    Classifies FAOSTAT area codes into their geographic grouping type.
    Critical for preventing double-counting when aggregating globally.

  Args:
    area_code_column (string): SQL column reference for area_code

  Returns:
    STRING: 'Country', 'Sub-Regional Group', or 'Global/Major Region'

  FAOSTAT Area Code Ranges:
    1 – 999   → Individual Country
    1000 – 4999  → Sub-Regional Group (e.g., Eastern Africa)
    5000+        → Global/Major Region (e.g., World, Africa, Asia)

  Usage:
    {{ area_type('area_code') }}
#}

{% macro area_type(area_code_column) %}
    case
        when {{ area_code_column }} < 1000  then 'Country'
        when {{ area_code_column }} >= 5000 then 'Global/Major Region'
        else 'Sub-Regional Group'
    end
{% endmacro %}