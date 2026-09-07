select
    area_name,
    item_name,
    year,
    production_tonnes,
    area_harvested_ha,
    yield_kg_ha

from {{ ref('fct_production') }}
where
    (production_tonnes < 0 and has_production  = true)
    or (area_harvested_ha < 0 and has_area = true)
    or (yield_kg_ha < 0 and has_yield = true)