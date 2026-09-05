{{
    config(
        materialized = 'view',
        description = """ """
    )
}}

with source as (
    select *
    from {{ source('raw_faostat', 'trade_crops_livestock_raw') }}
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
        }} as trade_sk,

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
        cast(Value as FLOAT64) as value_original,

        coalesce(trim(cast(Flag as STRING)), '') as flag_code,

        cast(_loaded_at as TIMESTAMP) as _raw_loaded_at,
        cast(_source_file as STRING) as _source_file,
        current_timestamp() as _stg_updated_at
    from source
)

select * from renamed
