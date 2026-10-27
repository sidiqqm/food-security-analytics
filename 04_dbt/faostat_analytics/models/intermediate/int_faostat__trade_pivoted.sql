-- 1.  Import Dependency Ratio (IDR) membutuhkan data produksi dari stg_faostat__production yang di-join berdasarkan:
--     area_code, item_code, year
--     Jika data produksi tidak tersedia untuk kombinasi negara–komoditas–tahun tersebut, 
--     maka nilai IDR harus NULL, bukan diimputasi atau diestimasi.
-- 2. Net Trade = Export - Import. Negative = net importer.
-- 3. Nilai IDR yang sangat tinggi dapat mengindikasikan masalah
--     kualitas data (e.g., transit trade misclassification).
-- 4. Nilai tetap menggunakan satuan asli: tonnes and 1000 USD.
--    Jangan mengubah 1000 USD to USD disini — lakukan di reporting layer.
-- Grain: One row per (area_code × item_code × year)
-- Problem : null harus tetap null jangan ubah jadi 0

{{
    config(
        materialized = 'view',
        description  = """
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

-- PIVOT trade from long to wide
trade_pivoted as (

    select
        area_code,
        area_name,
        item_code,
        item_name,
        year,

        max(case when element_category = 'export_quantity'
                 then value_standardized end) as export_qty_tonnes,
        max(case when element_category = 'export_quantity'
                 then flag_code end) as flag_export_qty,
        max(case when element_category = 'export_quantity'
                 then flag_quality_score end) as quality_score_export_qty,

        max(case when element_category = 'export_value'
                 then value_standardized end) as export_val_1000usd,
        max(case when element_category = 'export_value'
                 then flag_code end) as flag_export_val,

        max(case when element_category = 'import_quantity'
                 then value_standardized end) as import_qty_tonnes,
        max(case when element_category = 'import_quantity'
                 then flag_code end) as flag_import_qty,
        max(case when element_category = 'import_quantity'
                 then flag_quality_score end) as quality_score_import_qty,

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

with_kpis as (

    select
        {{ dbt_utils.generate_surrogate_key([
            'area_code', 'item_code', 'year'
        ]) }} as trade_wide_sk,

        *,

        coalesce(export_qty_tonnes, 0) - coalesce(import_qty_tonnes, 0) as net_trade_qty_tonnes,

        coalesce(export_val_1000usd, 0) - coalesce(import_val_1000usd, 0) as net_trade_val_1000usd,

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
                200.0
            ),
            2
        ) as import_dependency_ratio_pct,

        round(
            safe_divide(
                coalesce(export_val_1000usd, 0),
                nullif(coalesce(import_val_1000usd, 0), 0)
            ) * 100,
            2
        ) as trade_coverage_ratio_pct,

        case
            when coalesce(export_qty_tonnes, 0) >
                 coalesce(import_qty_tonnes, 0)
            then true
            else false
        end as is_net_exporter,

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

        case when export_qty_tonnes is not null then true else false end as has_export_data,
        case when import_qty_tonnes is not null then true else false end as has_import_data,
        case when production_tonnes is not null then true else false end as has_production_for_idr

    from trade_with_production

)

select * from with_kpis