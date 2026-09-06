{{
    config(
        materialized = 'view',
        description  = """
            Input : stg_faostat__trade + stg_faostat__production (for IDR)
            Output: Wide format — one row per (area × item × year) with
                    export_qty, export_val, import_qty, import_val,
                    net_trade_qty, net_trade_val, import_dependency_ratio

            Business Rules:
            1. Import Dependency Ratio (IDR) requires production data from
               stg_faostat__production joined on (area_code, item_code, year).
               If production data is unavailable for a country-item-year,
               IDR is NULL (not imputed or estimated).
            2. Net Trade = Export - Import. Negative = net importer.
            3. IDR capped at 200% for display purposes — extreme values indicate
               data quality issues (e.g., transit trade misclassification).
            4. Values remain in original units: tonnes and 1000 USD.
               Do NOT convert 1000 USD to USD here — done in reporting layer.

            Grain: One row per (area_code × item_code × year)

            Problem : null values should fill null in the column not 0
        """
    )
}}

with stg_trade as (

    select *
    from {{ ref('stg_faostat__trade') }}
    where
        is_country = true
        and is_in_project_period = true

),

-- Bring in production data for Import Dependency Ratio calculation
-- We only need production_tonnes here
stg_production_for_idr as (

    select
        area_code,
        item_code,
        year,
        value_standardized as production_tonnes,
        flag_quality_score as quality_score_production

    from {{ ref('stg_faostat__production') }}
    where
        element_category = 'production'
        and is_country = true
        and is_in_project_period = true
        and not is_missing

),

-- PIVOT trade elements from long to wide
trade_pivoted as (

    select
        area_code,
        area_name,
        item_code,
        item_name,
        year,

        -- EXPORT QUANTITY (tonnes)
        max(case when element_category = 'export_quantity'
                 then value_standardized end) as export_qty_tonnes,
        max(case when element_category = 'export_quantity'
                 then flag_code end) as flag_export_qty,
        max(case when element_category = 'export_quantity'
                 then flag_quality_score end) as quality_score_export_qty,

        -- EXPORT VALUE (1000 USD)
        max(case when element_category = 'export_value'
                 then value_standardized end) as export_val_1000usd,
        max(case when element_category = 'export_value'
                 then flag_code end) as flag_export_val,

        -- IMPORT QUANTITY (tonnes)
        max(case when element_category = 'import_quantity'
                 then value_standardized end) as import_qty_tonnes,
        max(case when element_category = 'import_quantity'
                 then flag_code end) as flag_import_qty,
        max(case when element_category = 'import_quantity'
                 then flag_quality_score end) as quality_score_import_qty,

        -- IMPORT VALUE (1000 USD)
        max(case when element_category = 'import_value'
                 then value_standardized end) as import_val_1000usd,
        max(case when element_category = 'import_value'
                 then flag_code end) as flag_import_val

    from stg_trade
    group by
        area_code,
        area_name,
        item_code,
        item_name,
        year
),

-- JOIN with production data for IDR calculation
-- LEFT JOIN: preserve all trade records even without production match
trade_with_production as (

    select
        t.*,
        p.production_tonnes,
        p.quality_score_production

    from trade_pivoted t
    left join stg_production_for_idr p
        on  t.area_code = p.area_code
        and t.item_code = p.item_code
        and t.year = p.year

),

-- DERIVED KPIs
with_kpis as (

    select
        {{ dbt_utils.generate_surrogate_key([
            'area_code', 'item_code', 'year'
        ]) }} as trade_wide_sk,

        *,

        -- NET TRADE QUANTITY (tonnes)
        -- Positive = net exporter | Negative = net importer
        coalesce(export_qty_tonnes, 0) - coalesce(import_qty_tonnes, 0) as net_trade_qty_tonnes,

        -- NET TRADE VALUE (1000 USD)
        coalesce(export_val_1000usd, 0) - coalesce(import_val_1000usd, 0) as net_trade_val_1000usd,

        -- IMPORT DEPENDENCY RATIO (%)
        -- Formula: Import / (Production + Import - Export) × 100
        -- Denominator = Domestic Utilization (total available supply for domestic use)
        --
        -- Business Rule: Cap IDR at 200% to handle data anomalies.
        -- IDR > 100% is mathematically possible when export > production
        -- (e.g., country re-exports imported goods), but > 200% likely
        -- indicates data quality issues.
        --
        -- IDR is NULL when:
        -- - Production data is unavailable (cannot compute denominator)
        -- - Domestic utilization = 0 (division by zero → food security crisis signal)
        round(
            least(
                safe_divide(
                    coalesce(import_qty_tonnes, 0),
                    nullif(
                        coalesce(production_tonnes, 0) +
                        coalesce(import_qty_tonnes, 0) -
                        coalesce(export_qty_tonnes, 0),
                        0
                    )
                ) * 100,
                200.0   -- Cap at 200%
            ),
            2
        ) as import_dependency_ratio_pct,

        -- TRADE COVERAGE RATIO
        -- Export Value / Import Value × 100
        -- > 100 means exports more than pay for imports (trade surplus)
        round(
            safe_divide(
                coalesce(export_val_1000usd, 0),
                nullif(coalesce(import_val_1000usd, 0), 0)
            ) * 100,
            2
        ) as trade_coverage_ratio_pct,

        -- NET EXPORTER FLAG
        case
            when coalesce(export_qty_tonnes, 0) >
                 coalesce(import_qty_tonnes, 0)
            then true
            else false
        end as is_net_exporter,

        -- AVERAGE QUALITY SCORE
        round(
            (
                coalesce(quality_score_export_qty, 0) +
                coalesce(quality_score_import_qty, 0)
            ) / nullif(
                (case when quality_score_export_qty is not null then 1 else 0 end) +
                (case when quality_score_import_qty is not null then 1 else 0 end),
                0
            ),
            2
        ) as quality_score_avg,

        -- DATA AVAILABILITY FLAGS
        case when export_qty_tonnes  is not null then true else false end as has_export_data,
        case when import_qty_tonnes  is not null then true else false end as has_import_data,
        case when production_tonnes  is not null then true else false end as has_production_for_idr

    from trade_with_production

)

select * from with_kpis