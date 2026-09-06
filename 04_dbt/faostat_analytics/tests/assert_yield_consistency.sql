-- Purpose:
--   Validate that computed yield (Production / Area Harvested × 10,000) is
--   within reasonable tolerance of the reported yield value in FAOSTAT.

--   This test catches data integrity issues where one of the three elements
--   (production, area, yield) may have been incorrectly reported or estimated.

-- Tolerance: 5% — allows for rounding differences in FAOSTAT's own derivation.

-- Notes:
--   - Yield in FAOSTAT is officially "calculated" (Flag C) as Production / Area
--   - We compare in hg/ha units to avoid floating point issues from conversion
--   - Only test on country-level data (is_country = true)
--   - Exclude rows where production or area is NULL or zero
-- =============================================================================

with production_area as (

    select
        area_code,
        area_name,
        item_code,
        item_name,
        year,
        sum(case when element_category = 'production' then value_original end) as prod_tonnes,
        sum(case when element_category = 'area_harvested' then value_original end) as area_ha,
        sum(case when element_category = 'yield' then value_original end) as yield_hg_ha_reported

    from {{ ref('stg_faostat__production') }}
    where
        is_country = true
        and is_in_project_period = true
        and not is_missing
        and element_category in ('production', 'area_harvested', 'yield')

    group by
        area_code, area_name, item_code, item_name, year

),

with_computed_yield as (

    select
        *,
        -- Recompute yield: Production(t) / Area(ha) × 10,000 = hg/ha
        safe_divide(prod_tonnes, area_ha) * 10000.0 as yield_hg_ha_computed,

        abs(
            safe_divide(
                yield_hg_ha_reported - safe_divide(prod_tonnes, area_ha) * 10000.0,
                nullif(yield_hg_ha_reported, 0)
            )
        ) * 100 as yield_deviation_pct

    from production_area
    where
        prod_tonnes is not null and prod_tonnes > 0
        and area_ha is not null and area_ha > 0
        and yield_hg_ha_reported is not null

)

select
    area_code,
    area_name,
    item_code,
    item_name,
    year,
    round(prod_tonnes, 0) as prod_tonnes,
    round(area_ha, 0) as area_ha,
    round(yield_hg_ha_reported, 1) as yield_reported_hg_ha,
    round(yield_hg_ha_computed, 1) as yield_computed_hg_ha,
    round(yield_deviation_pct, 2) as deviation_pct

from with_computed_yield
where yield_deviation_pct > 5.0   -- 5% tolerance

order by yield_deviation_pct desc