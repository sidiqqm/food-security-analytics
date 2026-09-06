{{
    config(
        materialized = 'view',
        description  = """
            Scope:
            Hanya item Grand Total (item_code = 2901) untuk analisis pada tingkat negara

            Hanya menggunakan negara individual (is_country = true)
            Periode proyek FBS (Food Balance Sheets): 2010–2022

            Metrik Turunan Utama:

            DES Adequacy Ratio: Perbandingan antara nilai DES aktual dengan rekomendasi minimum FAO (2.100 kkal)
            DES Category: Mengklasifikasikan status nutrisi berdasarkan standar atau benchmark internasional
            DES YoY Change: Perubahan Dietary Energy Supply (DES) dari tahun ke tahun (Year-over-Year)

            Grain: Satu baris untuk setiap kombinasi (area_code × year)

            PENTING: Model ini menggunakan Grand Total (item_code = 2901)
            yang merepresentasikan agregasi dari SELURUH kelompok komoditas dalam Food Balance Sheet.

            Jangan menggunakan item komoditas individual untuk analisis DES, karena setiap komoditas hanya 
            merepresentasikan kontribusi sebagian terhadap total energi makanan, bukan total pasokan energi makanan secara keseluruhan.
        """
    )
}}

with stg_fbs as (

    select *
    from {{ ref('stg_faostat__food_balance_sheets') }}
    where
        is_country = true
        and is_in_project_period = true
        and is_grand_total = true       -- item_code = 2901 (Grand Total)

),

-- PIVOT food security elements from long to wide
fbs_pivoted as (

    select
        area_code,
        area_name,
        year,

        -- DIETARY ENERGY SUPPLY (kcal/capita/day)
        max(case when element_category = 'dietary_energy_supply'
                 then value_standardized end) as des_kcal_cap_day,
        max(case when element_category = 'dietary_energy_supply'
                 then flag_code end) as flag_des,
        max(case when element_category = 'dietary_energy_supply'
                 then flag_quality_score end) as quality_score_des,

        -- PROTEIN SUPPLY (g/capita/day)
        max(case when element_category = 'protein_supply'
                 then value_standardized end) as protein_g_cap_day,
        max(case when element_category = 'protein_supply'
                 then flag_code end) as flag_protein,

        -- FAT SUPPLY (g/capita/day)
        max(case when element_category = 'fat_supply'
                 then value_standardized end) as fat_g_cap_day,
        max(case when element_category = 'fat_supply'
                 then flag_code end) as flag_fat,

        -- FOOD SUPPLY QUANTITY (kg/capita/year)
        max(case when element_category = 'food_quantity'
                 then value_standardized end) as food_qty_kg_cap_yr,
        max(case when element_category = 'food_quantity'
                 then flag_code end) as flag_food_qty

    from stg_fbs
    group by
        area_code,
        area_name,
        year

),

-- DERIVED FOOD SECURITY METRICS
with_derived as (

    select
        {{ dbt_utils.generate_surrogate_key([
            'area_code', 'year'
        ]) }} as food_security_wide_sk,

        *,

        -- DES ADEQUACY RATIO
        -- Analytical benchmark: 2,100 kcal/capita/day
        -- Digunakan sebagai ambang batas tetap (fixed threshold) untuk membandingkan DES antarnegara.
        -- Ratio > 1,0 = pasokan makanan memadai pada tingkat populasi.
        -- Ratio < 1,0 = pasokan makanan tidak memadai, sehingga terdapat risiko food insecurity atau kerawanan pangan.
        round(
            safe_divide(des_kcal_cap_day, 2100.0),
            3
        ) as des_adequacy_ratio,

        -- DES ADEQUACY PERCENTAGE
        round(
            safe_divide(des_kcal_cap_day, 2100.0) * 100,
            1
        ) as des_adequacy_pct,

        -- DES CATEGORY
        -- Custom classification benchmark aligned with general FAO/WHO energy requirement ranges
        -- < 1,800: Severely Inadequate (extreme food insecurity)
        -- 1,800 – 2,099: Inadequate (below minimum requirement)
        -- 2,100 – 2,499: Borderline Adequate
        -- 2,500 – 2,999: Adequate
        -- ≥ 3,000: Abundant
        case
            when des_kcal_cap_day is null then 'No Data'
            when des_kcal_cap_day < 1800 then 'Severely Inadequate'
            when des_kcal_cap_day < 2100 then 'Inadequate'
            when des_kcal_cap_day < 2500 then 'Borderline Adequate'
            when des_kcal_cap_day < 3000 then 'Adequate'
            else 'Abundant'
        end as des_category

        case
            when des_kcal_cap_day is null then 0
            when des_kcal_cap_day < 1800 then 1
            when des_kcal_cap_day between 1800 and 2099 then 2
            when des_kcal_cap_day between 2100 and 2499 then 3
            when des_kcal_cap_day between 2500 and 2999 then 4
            when des_kcal_cap_day >= 3000 then 5
        end as des_category_order,

        -- Project-defined analytical protein benchmark: 50 g/capita/day
        round(
            safe_divide(protein_g_cap_day, 50.0) * 100,
            1
        ) as protein_adequacy_pct,

        -- MACRONUTRIENT ENERGY COMPOSITION
        -- Perkiraan persentase kalori DES yang berasal dari:
        -- Protein, Lemak ,Karbohidrat
        -- Lemak menghasilkan 9 kkal per gram
        -- Protein menghasilkan 4 kkal per gram
        -- Sisa energi diasumsikan berasal dari karbohidrat, dengan 4 kkal per gram

        round(
            safe_divide(protein_g_cap_day * 4.0, nullif(des_kcal_cap_day, 0)) * 100,
            1
        ) as pct_kcal_from_protein,

        round(
            safe_divide(fat_g_cap_day * 9.0, nullif(des_kcal_cap_day, 0)) * 100,
            1
        ) as pct_kcal_from_fat,

        round(
            100 -
            safe_divide(protein_g_cap_day * 4.0, nullif(des_kcal_cap_day, 0)) * 100 -
            safe_divide(fat_g_cap_day * 9.0, nullif(des_kcal_cap_day, 0)) * 100,
            1
        ) as pct_kcal_from_carbs,

        -- IS FOOD SECURE (population-level proxy)
        case
            when des_kcal_cap_day >= 2100 then true
            when des_kcal_cap_day is null then null
            else false
        end as is_food_secure

    from fbs_pivoted

)

select * from with_derived