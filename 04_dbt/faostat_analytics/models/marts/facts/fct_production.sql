{{
    config(
        materialized = 'table',
        description  = """
            Fact table: Agricultural production measurements.

            Grain: One row per (area × item × year)
            — individual countries only, project period only (1991–2022),
            — all items (not filtered to strategic commodities)
              to preserve flexibility for ad-hoc analysis.

            Measures:
            - production_tonnes: total production in metric tonnes
            - area_harvested_ha: harvested area in hectares
            - yield_kg_ha: yield (production per harvested area) in kg/ha

            Foreign Keys → Dimension Tables:
            - area_key → dim_area
            - item_key → dim_item
            - year_key → dim_year

            Data Quality:
            - Rows with all three measures missing are excluded.
            - Partial rows (e.g., only production, no yield) are included
              with NULL for missing measures.
            - quality_score_avg reflects average flag quality across measures.
        """
    )
}}

with int_production as (

    select *
    from {{ ref('int_faostat__production_pivoted') }}

),

dim_area as (

    select
        area_code,
        area_key

    from {{ ref('dim_area') }}

),

dim_item as (

    select
        item_code,
        item_key,
        is_strategic_commodity

    from {{ ref('dim_item') }}

),

dim_year as (

    select
        year,
        year_key

    from {{ ref('dim_year') }}

),

final as (

    select

        {{
            dbt_utils.generate_surrogate_key([
                'p.area_code',
                'p.item_code',
                'p.year'
            ])
        }} as production_sk,

        da.area_key,
        di.item_key,
        dy.year_key,

        p.area_code,
        p.item_code,
        p.year,

        p.area_name,
        p.item_name,

        round(p.production_tonnes, 2) as production_tonnes,
        round(p.area_harvested_ha, 2) as area_harvested_ha,
        round(p.yield_kg_ha, 2) as yield_kg_ha,

        round(
            p.production_tonnes / 1e6,
            4
        ) as production_million_tonnes,

        round(p.yield_kg_ha_computed, 2) as yield_kg_ha_computed,
        round(p.yield_deviation_pct, 2) as yield_deviation_pct,

        p.flag_production,
        p.flag_area_harvested,
        p.flag_yield,
        p.quality_score_avg,
        p.has_production,
        p.has_area,
        p.has_yield,
        p.elements_complete_count,

        coalesce(
            di.is_strategic_commodity,
            false
        ) as is_strategic_commodity,

        current_timestamp() as _fact_updated_at

    from int_production p

    left join dim_area da
        on p.area_code = da.area_code

    left join dim_item di
        on p.item_code = di.item_code

    left join dim_year dy
        on p.year = dy.year

)

select *
from final