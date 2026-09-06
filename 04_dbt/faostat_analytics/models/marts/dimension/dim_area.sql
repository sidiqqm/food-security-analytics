{{
    config(
        materialized = 'table',
        description  = """
            Dimension table: Geographic areas (countries and regional aggregates).

            Sources:
            - stg_faostat__production (to get all areas present in production data)
            - seed_fao_regions (for regional mapping, income group, geographic region)

            Scope: ALL areas including regional aggregates.
            Use is_country = true to filter to individual countries only.

            Slowly Changing Dimension Type 1 (SCD1):
            - No history tracking; current attributes only.
            - Country names and classifications reflect latest available data.

            Grain: One row per area_code (unique area identifier).
        """
    )
}}

with all_areas as (
    select distinct 
        area_code, 
        area_name, 
        area_code_m49, 
        area_type, 
        is_country
    from {{ ref('stg_faostat__production') }}

    union distinct

    select distinct 
        area_code, 
        area_name, 
        area_code_m49, 
        area_type, 
        is_country
    from {{ ref('stg_faostat__trade') }}

    union distinct

    select distinct 
        area_code, 
        area_name, 
        area_code_m49, 
        area_type, 
        is_country
    from {{ ref('stg_faostat__food_balance_sheets') }}
),

with_region_mapping as (

    select
        a.area_code,
        a.area_name,
        a.area_code_m49,
        a.area_type,
        a.is_country,

        coalesce(r.fao_region, 'Not Classified') as fao_region,
        coalesce(r.income_group, 'Not Classified') as income_group,
        coalesce(r.geographic_region, 'Not Classified') as geographic_region

    from all_areas a
    left join {{ ref('seed_fao_regions') }} r
        on a.area_code = r.area_code

),

final as (

    select
        {{ dbt_utils.generate_surrogate_key(['area_code']) }}   as area_key,

        area_code,

        area_name,
        area_code_m49,
        area_type,
        is_country,

        fao_region,
        income_group,
        geographic_region,

        case income_group
            when 'High income' then 4
            when 'Upper middle income' then 3
            when 'Lower middle income' then 2
            when 'Low income' then 1
            else 0
        end as income_group_order,

        case 
            when income_group in ('High income', 'Upper middle income')
                then 'Higher Income'

            when income_group in ('Lower middle income', 'Low income')
                then 'Lower Income'

            else 'Not Classified'
        end as income_group_category,

        current_timestamp() as _dim_updated_at

    from with_region_mapping

)

select * from final