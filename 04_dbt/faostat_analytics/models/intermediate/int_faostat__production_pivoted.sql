{{
    config(
        materialized = 'view',
        description  = """
            Output: Wide format — one row per (area × item × year)
                    with production_tonnes, area_harvested_ha, yield_kg_ha as columns.

            Scope:
            - Individual countries only (is_country = true)
            - Project period only (is_in_project_period = true)
            - All items (filtering to strategic commodities done in fct_production)
            - Non-missing values preferred; NULL kept where no data available

            Grain: One row per (area_code × item_code × year)

            Business Rules:
            1. If production value exists but yield is missing, yield is NOT imputed.
               Missing data is preserved transparently.
            2. Quality scores are averaged across the three element measures.
               If only one element has data, score reflects that element only.
            3. Rows where ALL THREE elements are missing are excluded to reduce noise.
        """
    )
}}

with source_stg as (
    select *
    from {{ ref('stg_faostat__production') }}
),

stg_with_derived as (
    select
        production_sk,
        area_code,
        item_code,
        element_code,
        year,

        area_name,
        area_code_m49,

        item_name,
        item_code_cpc,

        element_name,

        case element_code
            when {{ var('element_code_area_harvested') }} then 'area_harvested'
            when {{ var('element_code_yield') }} then 'yield'
            when {{ var('element_code_production') }} then 'production'
            else 'other'
        end as element_category,

        unit_original,
        value_original,

        --  Yield di FAOSTAT pakenya hg/ha (hectogram per hectare)
        -- yang dimana satuan yang gak biasa dipake, jadi dikonvert ke kg/ha untuk interpredibiliy
        -- Conversion: 1 hg = 100g = 0.1 kg
        --   hg/ha ÷ 10 = kg/ha
    
        -- Production (t) and Area Harvested (ha): gak dikonvert.
        case
            when element_code = {{ var('element_code_yield') }}
                then value_original / 10.0   -- hg/ha → kg/ha
            else
                value_original               -- t or ha: gak berubah
        end as value_standardized,

        case
            when element_code = {{ var('element_code_area_harvested') }}
                then 'ha'
            when element_code = {{ var('element_code_yield') }}
                then 'kg/ha'                         -- Converted from hg/ha
            when element_code = {{ var('element_code_production') }}
                then 'tonnes'
            else unit_original
        end as unit_standardized,

        flag_code,
        
        {{ flag_label('flag_code') }} as flag_label,

        {{ flag_quality_score('flag_code') }} as flag_quality_score,

        case
            when flag_code in ('', 'Q', 'A', 'S', 'C', 'X') then true
            else false
        end as is_high_quality,

        case
            when flag_code = 'M' then true
            else false
        end as is_missing,

        case
            when flag_code in ('E', 'F', 'I', 'P') then true
            else false
        end as is_estimated,

        {{ area_type('area_code') }} as area_type,

        case
            when area_code < {{ var('country_area_code_max') }} then true
            else false
        end as is_country,

        case
            when year between {{ var('project_year_start') }} and {{ var('project_year_end') }}
            then true
            else false
        end as is_in_project_period,

        _raw_loaded_at,
        _source_file,
        _stg_updated_at

    from source_stg
),

stg_production as (

    select *
    from stg_with_derived
    where
        is_country = true
        and is_in_project_period = true

),

pivoted as (

    select
        area_code,
        area_name,
        item_code,
        item_name,
        year,

        -- PRODUCTION
        max(case when element_category = 'production'
                 then value_standardized end) as production_tonnes,

        max(case when element_category = 'production'
                 then flag_code end) as flag_production,

        max(case when element_category = 'production'
                 then flag_quality_score end) as quality_score_production,

        -- AREA HARVESTED
        max(case when element_category = 'area_harvested'
                 then value_standardized end) as area_harvested_ha,

        max(case when element_category = 'area_harvested'
                 then flag_code end) as flag_area_harvested,

        max(case when element_category = 'area_harvested'
                 then flag_quality_score end) as quality_score_area,

        -- YIELD (already converted to kg/ha in staging)
        max(case when element_category = 'yield'
                 then value_standardized end) as yield_kg_ha,

        max(case when element_category = 'yield'
                 then flag_code end) as flag_yield,

        max(case when element_category = 'yield'
                 then flag_quality_score end) as quality_score_yield

    from stg_production
    group by
        area_code,
        area_name,
        item_code,
        item_name,
        year

),

-- DERIVED METRICS
with_derived as (

    select
        -- SURROGATE KEY (grain: area × item × year)
        {{ dbt_utils.generate_surrogate_key([
            'area_code', 'item_code', 'year'
        ]) }} as production_wide_sk,

        *,

        round(
            (
                coalesce(quality_score_production, 0) +
                coalesce(quality_score_area, 0) +
                coalesce(quality_score_yield, 0)
            ) /
            nullif(
                (case when quality_score_production is not null then 1 else 0 end) +
                (case when quality_score_area is not null then 1 else 0 end) +
                (case when quality_score_yield is not null then 1 else 0 end),
                0
            ),
            2
        ) as quality_score_avg,

        case when production_tonnes is not null then true else false end as has_production,
        case when area_harvested_ha is not null then true else false end as has_area,
        case when yield_kg_ha is not null then true else false end as has_yield,

        (case when production_tonnes is not null then 1 else 0 end) +
        (case when area_harvested_ha is not null then 1 else 0 end) +
        (case when yield_kg_ha is not null then 1 else 0 end) as elements_complete_count,

        round(safe_divide(production_tonnes, area_harvested_ha) * 1000.0, 2) as yield_kg_ha_computed,

        round(
            abs(
                safe_divide(
                    yield_kg_ha -
                        safe_divide(production_tonnes, area_harvested_ha) * 1000.0,
                    nullif(yield_kg_ha, 0)
                )
            ) * 100,
            2
        ) as yield_deviation_pct

    from pivoted

),

final as (

    select *
    from with_derived
    where elements_complete_count > 0

)

select * from final