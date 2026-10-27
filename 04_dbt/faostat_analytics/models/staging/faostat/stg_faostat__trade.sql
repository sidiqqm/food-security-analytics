{{
    config(
        materialized = 'view',
        description  = """
            Grain: One row per (area_code × item_code × element_code × year)
            Primary Key: trade_sk (surrogate key)
        """
    )
}}

with source as (

    select * from {{ source('raw_faostat', 'trade_crops_livestock_raw') }}

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
        {{ dbt_utils.generate_surrogate_key([
            'area_code',
            'item_code',
            'element_code',
            'year'
        ]) }} as trade_sk,
        
        *,

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
            when flag_code = 'R' then true
            else false
        end as is_mirror_trade,

        {{ area_type('area_code') }} as area_type,

        case
            when area_code < {{ var('country_area_code_max') }} then true
            else false
        end as is_country,

        case element_code
            when {{ var('element_code_export_qty') }} then 'export_quantity'
            when {{ var('element_code_export_val') }} then 'export_value'
            when {{ var('element_code_import_qty') }} then 'import_quantity'
            when {{ var('element_code_import_val') }} then 'import_value'
            else 'other'
        end as element_category,

        -- Trade direction
        case
            when element_code in (
                {{ var('element_code_export_qty') }},
                {{ var('element_code_export_val') }}
            ) then 'Export'
            when element_code in (
                {{ var('element_code_import_qty') }},
                {{ var('element_code_import_val') }}
            ) then 'Import'
            else 'Other'
        end as trade_direction,

        -- Measurement type
        case
            when element_code in (
                {{ var('element_code_export_qty') }},
                {{ var('element_code_import_qty') }}
            ) then 'Quantity'
            when element_code in (
                {{ var('element_code_export_val') }},
                {{ var('element_code_import_val') }}
            ) then 'Value'
            else 'Other'
        end as measurement_type,

        case
            when element_code in (
                {{ var('element_code_export_qty') }},
                {{ var('element_code_import_qty') }}
            ) then 'tonnes'
            when element_code in (
                {{ var('element_code_export_val') }},
                {{ var('element_code_import_val') }}
            ) then '1000_usd_nominal'
            else unit_original
        end as unit_standardized,

        value_original as value_standardized,
        
        case
            when year between {{ var('project_year_start') }}
                          and {{ var('project_year_end') }}
            then true
            else false
        end as is_in_project_period

    from renamed

)

select * from with_derived