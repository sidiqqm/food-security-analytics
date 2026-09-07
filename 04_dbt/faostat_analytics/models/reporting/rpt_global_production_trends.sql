{{
    config(
        materialized = 'table',
        description  = """
            Reporting table: Global production trends for strategic commodities.
            Pre-aggregated for Power BI Executive and Trend dashboards.

            Grain: One row per (item × year) — global aggregate of all countries.
            Scope: Strategic commodities only, 1991–2022.

            Metrics:
            - total_production_tonnes: sum of all country production
            - total_area_harvested_ha: sum of all country harvested area
            - avg_yield_kg_ha: production-weighted average yield
            - country_count: number of countries with data
            - yoy_production_growth_pct: year-over-year production growth
            - cagr_10y_pct: 10-year CAGR (2012–2022)
        """
    )
}}

with fct_prod as (

    select
        p.item_code,
        p.item_name,
        p.year,
        p.production_tonnes,
        p.area_harvested_ha,
        p.yield_kg_ha,
        p.area_code,
        p.is_strategic_commodity

    from {{ ref('fct_production') }} p

    where
        p.is_strategic_commodity = true
        and p.has_production = true

),

global_aggregates as (

    select
        item_code,
        item_name,
        year,

        -- ── GLOBAL TOTALS ──
        sum(production_tonnes) as total_production_tonnes,
        sum(area_harvested_ha) as total_area_harvested_ha,
        count(distinct area_code) as country_count_with_data,

        -- ── PRODUCTION-WEIGHTED AVERAGE YIELD ──
        -- Simple average of yield would be misleading (gives equal weight to
        -- small and large producers). Weighted by area harvested is more accurate.
        round(
            safe_divide(
                sum(production_tonnes),
                nullif(sum(area_harvested_ha), 0)
            ) * 10.0,    -- Convert back: (t/ha) × 10 = kg/ha
            1
        ) as avg_yield_kg_ha_weighted

    from fct_prod

    group by
        item_code,
        item_name,
        year

),

-- ─────────────────────────────────────────────────────────────────────────────
-- YEAR-OVER-YEAR GROWTH using BigQuery window function LAG
-- ─────────────────────────────────────────────────────────────────────────────

with_yoy as (

    select
        *,

        -- Previous year production (for YoY calculation)
        lag(total_production_tonnes, 1) over (
            partition by item_code
            order by year
        ) as prev_year_production_tonnes,

        -- Production 10 years ago (for CAGR calculation)
        lag(total_production_tonnes, 10) over (
            partition by item_code
            order by year
        ) as production_10y_ago_tonnes

    from global_aggregates

),

with_growth_metrics as (

    select
        *,

        -- ── YoY PRODUCTION GROWTH (%) ──
        round(
            safe_divide(
                total_production_tonnes - prev_year_production_tonnes,
                nullif(prev_year_production_tonnes, 0)
            ) * 100,
            2
        ) as yoy_production_growth_pct,

        -- ── 10-YEAR CAGR (%) ──
        -- Formula: (Current / Base)^(1/n) - 1
        -- n = 10 years
        round(
            (
                pow(
                    safe_divide(
                        total_production_tonnes,
                        nullif(production_10y_ago_tonnes, 0)
                    ),
                    1.0 / 10.0
                ) - 1.0
            ) * 100,
            2
        ) as cagr_10y_pct,

        -- ── PRODUCTION INDEX (base year = 2000) ──
        -- Normalizes production to 100 in year 2000 for cross-commodity comparison
        -- This is computed later in Power BI using DAX or here via subquery

        -- ── DISPLAY METRICS (human-readable) ──
        round(
            total_production_tonnes / 1e6,
            3
        ) as total_production_million_tonnes,

        round(
            total_area_harvested_ha / 1e6,
            3
        ) as total_area_million_ha

    from with_yoy

),

-- Join with dim tables for additional context
with_dim_info as (

    select
        g.*,
        di.commodity_group,
        di.commodity_group_order,
        dy.decade,
        dy.period_label,
        dy.notable_event,
        dy.is_notable_event_year

    from with_growth_metrics g

    left join {{ ref('dim_item') }} di
        on g.item_code = di.item_code

    left join {{ ref('dim_year') }} dy
        on g.year = dy.year

)

select *
from with_dim_info