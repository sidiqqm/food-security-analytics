-- Custom Test: Import Dependency Ratio must be within [-100, 200]
-- Values outside this range indicate data anomalies.
-- IDR is already capped at 200 in intermediate layer.
-- We verify no negative values beyond -100 (extreme exporter case).
-- Test PASSES when this query returns 0 rows.

select
    area_name,
    item_name,
    year,
    import_dependency_ratio_pct,
    export_qty_tonnes,
    import_qty_tonnes,
    production_tonnes_ref

from {{ ref('fct_trade') }}
where
    import_dependency_ratio_pct is not null
    and (
        import_dependency_ratio_pct < -100
        or import_dependency_ratio_pct > 200
    )