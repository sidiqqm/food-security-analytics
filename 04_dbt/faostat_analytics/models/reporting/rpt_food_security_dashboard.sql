{{
    config(
        materialized = 'table',
        description  = """
            Reporting table: Country-level food security indicators with
            regional context. For Power BI Executive and Detail dashboards.

            Grain: One row per (area × year).
            Scope: Individual countries, 2010–2022.
        """
    )
}}

with fct_fs as (

    select *
    from {{ ref('fct_food_security') }}

),

dim_area as (

    select *
    from {{ ref('dim_area') }}

),

dim_year as (

    select *
    from {{ ref('dim_year') }}

),

-- Previous year DES for YoY change calculation
with_lag as (

    select
        f.*,

        lag(f.des_kcal_cap_day, 1) over (
            partition by f.area_code
            order by f.year
        ) as prev_year_des

    from fct_fs f

),

final as (

    select
        f.food_security_sk,
        f.area_code,
        f.year,

        a.area_name,
        a.fao_region,
        a.income_group,
        a.geographic_region,
        a.development_status,
        a.income_group_order,

        dy.decade,
        dy.period_label,
        dy.notable_event,
        dy.is_notable_event_year,

        f.des_kcal_cap_day,
        f.des_adequacy_ratio,
        f.des_adequacy_pct,
        f.des_category,
        f.des_category_order,
        f.is_food_secure,

        round(
            f.des_kcal_cap_day - f.prev_year_des,
            1
        ) as des_yoy_change_kcal,

        round(
            safe_divide(
                f.des_kcal_cap_day - f.prev_year_des,
                nullif(f.prev_year_des, 0)
            ) * 100,
            2
        ) as des_yoy_change_pct,

        f.protein_g_cap_day,
        f.fat_g_cap_day,
        f.food_qty_kg_cap_yr,
        f.protein_adequacy_pct,
        f.pct_kcal_from_protein,
        f.pct_kcal_from_fat,
        f.pct_kcal_from_carbs,

        f.flag_des,
        f.quality_score_des

    from with_lag f

    left join dim_area a
        on f.area_code = a.area_code

    left join dim_year dy
        on f.year_key = dy.year_key

)

select *
from final