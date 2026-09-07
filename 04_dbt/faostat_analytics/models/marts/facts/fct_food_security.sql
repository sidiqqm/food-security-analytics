{{
    config(
        materialized = 'table',
        description  = """
            Fact table: National food security and dietary adequacy indicators.

            Grain: One row per (area × year)
            — individual countries only, FBS period only (2010–2022).
            Based on FBS Grand Total (item_code 2901) which aggregates all commodities.

            Measures:
            - des_kcal_cap_day: Dietary Energy Supply (primary food security KPI)
            - protein_g_cap_day, fat_g_cap_day: macronutrient supply
            - food_qty_kg_cap_yr: total food quantity per capita per year
            - des_adequacy_ratio: DES vs. FAO 2100 kcal minimum benchmark
            - des_category: categorical food security classification

            Note: No item_key FK because this fact uses Grand Total (all items combined).
            Use fct_production for commodity-level analysis.
        """
    )
}}

with int_fbs as (

    select *
    from {{ ref('int_faostat__food_security_pivoted') }}

),

dim_area as (

    select
        area_code,
        area_key

    from {{ ref('dim_area') }}

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
                'f.area_code',
                'f.year'
            ])
        }} as food_security_sk,

        da.area_key,
        dy.year_key,

        f.area_code,
        f.year,

        f.area_name,

        round(f.des_kcal_cap_day, 1) as des_kcal_cap_day,
        round(f.des_adequacy_ratio, 3) as des_adequacy_ratio,
        round(f.des_adequacy_pct, 1) as des_adequacy_pct,

        f.des_category,
        f.des_category_order,
        f.is_food_secure,

        round(f.protein_g_cap_day, 1) as protein_g_cap_day,
        round(f.fat_g_cap_day, 1) as fat_g_cap_day,
        round(f.food_qty_kg_cap_yr, 1) as food_qty_kg_cap_yr,
        round(f.protein_adequacy_pct, 1) as protein_adequacy_pct,

        round(f.pct_kcal_from_protein, 1) as pct_kcal_from_protein,
        round(f.pct_kcal_from_fat, 1) as pct_kcal_from_fat,
        round(f.pct_kcal_from_carbs, 1) as pct_kcal_from_carbs,

        f.flag_des,
        f.quality_score_des,

        current_timestamp() as _fact_updated_at

    from int_fbs f

    left join dim_area da
        on f.area_code = da.area_code

    left join dim_year dy
        on f.year = dy.year

    where f.des_kcal_cap_day is not null

)

select *
from final