{{
    config = 'view',
    description = """
          Transformations applied at this layer:
            1. Column renaming to snake_case
            2. Explicit type casting (INT64, FLOAT64, STRING, TIMESTAMP)
            3. Flag standardization: NULL → empty string (= Official)
            4. Flag quality scoring using macro flag_quality_score()
            5. Human-readable flag labels using macro flag_label()
            6. Area type classification using macro area_type()
            7. Yield unit conversion: hg/ha → kg/ha (divide by 10)
            8. Element category labels for filtering in downstream models
            9. Boolean helper columns: is_country, is_missing, is_high_quality

            Grain: One row per (area_code × item_code × element_code × year)
            Primary Key: production_sk (surrogate key)
    """
}}

with source as (
    select *
    from {{source('raw_faostat', 'production_crops_livestock_raw')}}
),

renamed as (
    select
        {{
            dbt_utils.generate_surrogate_key([
                'Area_Code',
                'Item_Code',
                'Element_Code',
                'Year'
            ])
        }} as production_sk,

        cast(Area_Code as INT64) as area_code,
        cast(Item_Code as INT64) as item_code,        
        cast(Element_Code as INT64) as element_code,        
        cast(Year as INT64) as year,

        cast(Area as STRING) as area_name,
        safe_cast(Area_Code_M49 as INT64) as area_code_m49,

        cast(Item as STRING) as item_name,
        cast(Item_Code_CPC as INT64) as item_code_cpc,

        cast(Element as STRING) as element_name,

        cast(Unit as STRING) as unit_original,
        cast(Value as INT64) as value_original,

        coalesce(trim(cast(Flag as STRING)), '') as flag_code,

        cast(_loaded_at as TIMESTAMP) as _raw_loaded_at,
        cast(_source_file as STRING) as _source_file,
        current_timestamp() as _stg_updated_at
    from source
),

-- with_derived as (
--     select
--         production_sk,
--         area_code,
--         item_code,
--         element_code,
--         year,

--         area_name,
--         area_code_m49,

--         item_name,
--         item_code_cpc,

--         element_name,

--         case element_code
--             when {{ var('element_code_area_harvested') }} then 'area_harvested'
--             when {{ var('element_code_yield') }} then 'yield'
--             when {{ var('element_code_production') }} then 'production'
--             else 'other'
--         end as element_category,

--         unit_original,
--         value_original,

--         --  Yield di FAOSTAT pakenya hg/ha (hectogram per hectare)
--         -- yang dimana satuan yang gak biasa dipake, jadi dikonvert ke kg/ha untuk interpredibiliy
--         -- Conversion: 1 hg = 100g = 0.1 kg
--         --   hg/ha ÷ 10 = kg/ha
    
--         -- Production (t) and Area Harvested (ha): gak dikonvert.
--         case
--             when element_code = {{ var('element_code_yield') }}
--                 then value_original / 10.0   -- hg/ha → kg/ha
--             else
--                 value_original               -- t or ha: gak berubah
--         end as value_standardized,

--         case
--             when element_code = {{ var('element_code_area_harvested') }}
--                 then 'ha'
--             when element_code = {{ var('element_code_yield') }}
--                 then 'kg/ha'                         -- Converted from hg/ha
--             when element_code = {{ var('element_code_production') }}
--                 then 'tonnes'
--             else unit_original
--         end as unit_standardized,

--         flag_code,
        
--         {{ flag_label('flag_code') }} as flag_label,

--         {{ flag_quality_score('flag_code') }} as flag_quality_score,

--         case
--             when flag_code in ('', 'Q', 'A', 'S', 'C', 'X') then true
--             else false
--         end as is_high_quality,

--         case
--             when flag_code = 'M' then true
--             else false
--         end as is_missing,

--         case
--             when flag_code in ('E', 'F', 'I', 'P') then true
--             else false
--         end as is_estimated,

--         {{ area_type('area_code') }} as area_type,

--         case
--             when area_code < {{ var('country_area_code_max') }} then true
--             else false
--         end as is_country,

--         case
--             when year between {{ var('project_year_start') }} and {{ var('project_year_end') }}
--             then true
--             else false
--         end as is_in_project_period

--         _raw_loaded_at,
--         _source_file,
--         _stg_updated_at

--     from renamed

-- )

select * from renamed