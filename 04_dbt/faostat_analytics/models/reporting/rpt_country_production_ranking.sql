{{
    config(
        materialized = 'table',
        description  = """
            Reporting table: Country production rankings per commodity per year.
            Enables Power BI bar chart rankings and drillthrough.

            Grain: One row per (area × item × year).
            Scope: Strategic commodities, individual countries, 1991–2022.
            Includes rank within year × commodity for each country.
        """
    )
}}

with fct_prod as (

    select
        p.production_sk,
        p.area_code,
        p.item_code,
        p.year,
        p.area_name,
        p.item_name,
        p.production_tonnes,
        p.production_million_tonnes,
        p.area_harvested_ha,
        p.yield_kg_ha,
        p.quality_score_avg,
        p.flag_production,
        p.is_strategic_commodity

    from {{ ref('fct_production') }} p

    where
        p.is_strategic_commodity = true
        and p.has_production = true
        and p.production_tonnes > 0

),

with_dim as (

    select
        p.*,
        a.fao_region,
        a.income_group,
        a.geographic_region,
        a.development_status,
        i.commodity_group,
        i.commodity_group_order,
        dy.decade,
        dy.period_label,
        dy.notable_event

    from fct_prod p

    left join {{ ref('dim_area') }} a
        on p.area_code = a.area_code

    left join {{ ref('dim_item') }} i
        on p.item_code = i.item_code

    left join {{ ref('dim_year') }} dy
        on p.year = dy.year

),

with_rankings as (

    select
        *,

        rank() over (
            partition by item_code, year
            order by production_tonnes desc
        ) as global_production_rank,

        rank() over (
            partition by item_code, year, fao_region
            order by production_tonnes desc
        ) as regional_production_rank,

        round(
            safe_divide(
                production_tonnes,
                sum(production_tonnes) over (
                    partition by item_code, year
                )
            ) * 100,
            2
        ) as global_production_share_pct,

        round(
            sum(production_tonnes) over (
                partition by item_code, year
                order by production_tonnes desc
                rows between unbounded preceding and current row
            )
            / nullif(
                sum(production_tonnes) over (
                    partition by item_code, year
                ),
                0
            ) * 100,
            2
        ) as cumulative_production_share_pct,

        case
            when rank() over (
                partition by item_code, year
                order by production_tonnes desc
            ) <= 10
                then true
            else false
        end as is_top_10_producer

    from with_dim

)

select *
from with_rankings