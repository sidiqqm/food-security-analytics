{{
    config(
        materialized = 'table',
        description  = """
            Fact table: Agricultural trade flows and Import Dependency Ratio.

            Grain: One row per (area × item × year)
            — individual countries only, project period only (1991–2022).

            Measures:
            - export_qty_tonnes, import_qty_tonnes: trade volumes
            - export_val_1000usd, import_val_1000usd: trade values (nominal USD)
            - net_trade_qty_tonnes: export - import (positive = net exporter)
            - net_trade_val_1000usd: export value - import value
            - import_dependency_ratio_pct: % of domestic supply sourced from imports
            - trade_coverage_ratio_pct: export value / import value × 100

            Important Limitations:
            - Values in 1000 USD are nominal (not inflation-adjusted)
            - IDR requires production data; NULL where production unavailable
            - IDR capped at 200% to handle data anomalies
        """
    )
}}

with int_trade as (

    select *
    from {{ ref('int_faostat__trade_pivoted') }}

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
                't.area_code',
                't.item_code',
                't.year'
            ])
        }} as trade_sk,

        da.area_key,
        di.item_key,
        dy.year_key,

        t.area_code,
        t.item_code,
        t.year,

        t.area_name,
        t.item_name,

        round(t.export_qty_tonnes, 2) as export_qty_tonnes,
        round(t.import_qty_tonnes, 2) as import_qty_tonnes,
        round(t.net_trade_qty_tonnes, 2) as net_trade_qty_tonnes,

        round(t.export_val_1000usd, 2) as export_val_1000usd,
        round(t.import_val_1000usd, 2) as import_val_1000usd,
        round(t.net_trade_val_1000usd, 2) as net_trade_val_1000usd,

        round(t.production_tonnes, 2) as production_tonnes_ref,

        round(t.import_dependency_ratio_pct, 2)
            as import_dependency_ratio_pct,

        round(t.trade_coverage_ratio_pct, 2)
            as trade_coverage_ratio_pct,

        t.is_net_exporter,

        coalesce(
            di.is_strategic_commodity,
            false
        ) as is_strategic_commodity,

        t.has_export_data,
        t.has_import_data,
        t.has_production_for_idr,

        t.flag_export_qty,
        t.flag_import_qty,
        t.quality_score_avg,

        current_timestamp() as _fact_updated_at

    from int_trade t

    left join dim_area da
        on t.area_code = da.area_code

    left join dim_item di
        on t.item_code = di.item_code

    left join dim_year dy
        on t.year = dy.year

)

select *
from final