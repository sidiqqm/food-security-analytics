{{
    config(
        materialized = 'table',
        description  = """
            Reporting table: Trade balance and Import Dependency analysis.
            Pre-aggregated for Power BI Trade and Operational dashboards.

            Grain: One row per (area × item × year) — country level.
            Scope: Strategic commodities, individual countries, 1991–2022.
        """
    )
}}

with fct_trade as (

    select *
    from {{ ref('fct_trade') }}

    where is_strategic_commodity = true

),

dim_area as (

    select *
    from {{ ref('dim_area') }}

),

dim_item as (

    select *
    from {{ ref('dim_item') }}

),

dim_year as (

    select *
    from {{ ref('dim_year') }}

),

final as (

    select
        t.trade_sk,
        t.area_code,
        t.item_code,
        t.year,

        a.area_name,
        a.fao_region,
        a.income_group,
        a.geographic_region,
        a.development_status,

        i.item_name,
        i.commodity_group,

        dy.decade,
        dy.period_label,
        dy.notable_event,

        t.export_qty_tonnes,
        t.import_qty_tonnes,
        t.net_trade_qty_tonnes,
        t.export_val_1000usd,
        t.import_val_1000usd,
        t.net_trade_val_1000usd,

        t.import_dependency_ratio_pct,
        t.trade_coverage_ratio_pct,
        t.production_tonnes_ref,

        case
            when t.import_dependency_ratio_pct is null
                then 'No Data'

            when t.import_dependency_ratio_pct < 0
                then 'Major Exporter'

            when t.import_dependency_ratio_pct between 0 and 24
                then 'Self-Sufficient'

            when t.import_dependency_ratio_pct between 25 and 49
                then 'Modest Import Dependency'

            when t.import_dependency_ratio_pct between 50 and 74
                then 'High Import Dependency'

            when t.import_dependency_ratio_pct >= 75
                then 'Critical Import Dependency'

        end as idr_category,

        t.is_net_exporter,
        t.has_import_data,
        t.has_export_data,
        t.quality_score_avg

    from fct_trade t

    left join dim_area da
        on t.area_key = da.area_key

    left join dim_item i
        on t.item_key = i.item_key

    left join dim_year dy
        on t.year_key = dy.year_key

    left join dim_area a
        on t.area_code = a.area_code

)

select *
from final