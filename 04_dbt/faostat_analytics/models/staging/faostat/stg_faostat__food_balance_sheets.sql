{{
    config(
        materialized = 'view',
        description = """ """
    )
}}

with source as (
    select *
    from {{ source('raw_faostat', 'food_balance_sheets_raw') }}
),

renamed as (
    select
        cast(Area_Code as INT64) as area_code,
        cast(Item_Code as INT64) as item_code,        
        cast(Element_Code as INT64) as element_code,        
        cast(Year as INT64) as year,

        cast(Area as STRING) as area_name,
        safe_cast(Area_Code_M49 as STRING) as area_code_m49,

        cast(Item as STRING) as item_name,

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
        {{
            dbt_utils.generate_surrogate_key([
                'area_code',
                'item_code',
                'element_code',
                'year'
            ])
        }} as fbs_sk,
        
        *,

        {{ flag_label('flag_code') }}               as flag_label,
        {{ flag_quality_score('flag_code') }}       as flag_quality_score,

        case
            when flag_code in ('', 'Q', 'A', 'S', 'C', 'X') then true
            else false
        end as is_high_quality,

        case
            when flag_code = 'M' then true
            else false
        end as is_missing,

        {{ area_type('area_code') }}                as area_type,

        case
            when area_code < {{ var('country_area_code_max') }} then true
            else false
        end as is_country,

        -- FBS has many elements. We classify them into meaningful categories
        -- for downstream filtering.
        case element_code
            when {{ var('element_code_fbs_production') }} then 'production'
            when {{ var('element_code_fbs_import_qty') }} then 'import_quantity'
            when {{ var('element_code_fbs_export_qty') }} then 'export_quantity'
            when {{ var('element_code_fbs_supply_qty') }} then 'domestic_supply'
            when {{ var('element_code_fbs_food_qty') }} then 'food_quantity'
            when {{ var('element_code_fbs_kcal') }} then 'dietary_energy_supply'
            when {{ var('element_code_fbs_protein') }} then 'protein_supply'
            when {{ var('element_code_fbs_fat') }} then 'fat_supply'
            else 'other'
        end as element_category,

        -- PRIMARY KPI FLAG
        -- Marks the most important element for food security analysis.
        case
            when element_code = {{ var('element_code_fbs_kcal') }} then true
            else false
        end as is_dietary_energy_supply,

        -- GRAND TOTAL FLAG
        -- Item 2901 = Grand Total (sum of all commodity groups).
        -- Used for country-level DES analysis.
        case
            when item_code = {{ var('fbs_grand_total_item_code') }} then true
            else false
        end as is_grand_total,

        -- UNIT STANDARDIZATION & VALUE CONVERSION
        --
        -- CRITICAL: FBS production quantities are in 1000 tonnes.
        -- QCL production quantities are in tonnes.
        -- Convert FBS quantity elements to tonnes for cross-dataset consistency.
        --
        -- Elements that need conversion (1000 t → t):
        --   5511 = Production
        --   5611 = Import Quantity
        --   5911 = Export Quantity
        --   5072 = Domestic Supply Quantity
        --   5301 = Food Supply Quantity (NOTE: this is 1000 t total, not per capita)
        --
        -- Elements that do NOT need conversion (already per-capita):
        --   664  = kcal/capita/day
        --   674  = g/capita/day (protein)
        --   684  = g/capita/day (fat)
        --   5301 = kg/capita/yr (food supply per capita) ← depends on element name
        case
            -- Quantity elements (1000 t → t): multiply by 1000
            when element_code in (
                {{ var('element_code_fbs_production') }},
                {{ var('element_code_fbs_import_qty') }},
                {{ var('element_code_fbs_export_qty') }},
                {{ var('element_code_fbs_supply_qty') }}
            ) then value_original * 1000.0

            -- Per-capita elements: no conversion needed
            -- kcal/capita/day, g/capita/day, kg/capita/yr
            else value_original
        end as value_standardized,

        case
            -- Quantity elements: converted to tonnes
            when element_code in (
                {{ var('element_code_fbs_production') }},
                {{ var('element_code_fbs_import_qty') }},
                {{ var('element_code_fbs_export_qty') }},
                {{ var('element_code_fbs_supply_qty') }}
            ) then 'tonnes'

            -- Per-capita elements: keep original units
            when element_code = {{ var('element_code_fbs_kcal') }}
                then 'kcal/capita/day'
            when element_code = {{ var('element_code_fbs_protein') }}
                then 'g/capita/day'
            when element_code = {{ var('element_code_fbs_fat') }}
                then 'g/capita/day'
            when element_code = {{ var('element_code_fbs_food_qty') }}
                then 'kg/capita/yr'
            else
                unit_original
        end as unit_standardized,

        -- PERIOD FLAG
        -- FBS current methodology only meaningful from 2010
        case
            when year between {{ var('project_year_start_fbs') }}
                and {{ var('project_year_end') }}
            then true
            else false
        end as is_in_project_period

    from renamed

)

select * from with_derived
