{{
    config(
        materialized = 'view',
        description = """
          Transformations applied at this layer:
            1. Column renaming to snake_case
            2. Explicit type casting (INT64, FLOAT64, STRING, TIMESTAMP)
            Primary Key: production_sk (surrogate key)
    """
    )
}}
with source as (

    select * from {{ source('raw_faostat', 'production_crops_livestock_raw') }}

),

renamed as (

    select
        cast(Area_Code as INT64) as area_code,
        cast(Item_Code as INT64) as item_code,
        cast(Element_Code as INT64) as element_code,
        cast(Year as INT64) as year,

        cast(Area as STRING) as area_name,

        cast(Area_Code_M49 as STRING) as area_code_m49,

        cast(Item as STRING) as item_name,
        cast(Item_Code_CPC as STRING) as item_code_cpc,

        cast(Element as STRING) as element_name,

        cast(Unit as STRING) as unit_original,
        cast(Value as FLOAT64) as value_original,

        coalesce(trim(cast(Flag as STRING)), '') as flag_code,

        cast(_loaded_at as TIMESTAMP) as _raw_loaded_at,
        cast(_source_file as STRING) as _source_file,
        current_timestamp() as _stg_updated_at

    from source

),

with_derived as (

    select
        *,
        {{ dbt_utils.generate_surrogate_key([
            'area_code',
            'item_code',
            'element_code',
            'year'
        ]) }} as production_sk,

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

        -- AREA CLASSIFICATION
        -- Always use `where is_country = true` for country-level analysis.

        {{ area_type('area_code') }} as area_type,

        -- Boolean: is this an individual country (not a regional aggregate)?
        case
            when area_code < {{ var('country_area_code_max') }} then true
            else false
        end as is_country,

        -- ELEMENT CLASSIFICATION
        -- Standardized category labels for filtering in downstream models.
        case element_code
            when {{ var('element_code_area_harvested') }} then 'area_harvested'
            when {{ var('element_code_yield') }} then 'yield'
            when {{ var('element_code_production') }} then 'production'
            else 'other'
        end as element_category,

        -- UNIT STANDARDIZATION
        -- Yield di FAOSTAT pake hg/ha (hectogram per hectare) yang dimana satuan yang jarang digunakan
        -- mengubahnya ke kg/ha akan membuat interpretability.

        -- Conversion: 1 hg = 100g = 0.1 kg
        --   hg/ha ÷ 10 = kg/ha

        -- Production (t) and Area Harvested (ha): gak butuh dikonversi.
        case
            when element_code = {{ var('element_code_yield') }}
                then value_original / 10.0   -- hg/ha → kg/ha
            else
                value_original               -- t or ha: no change
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

        case
            when year between {{ var('project_year_start') }}
                          and {{ var('project_year_end') }}
            then true
            else false
        end as is_in_project_period

    from renamed

)

select * from with_derived