{{
    config(
        materialized = 'table',
        description  = """
            Grain: One row per QCL item_code.
        """
    )
}}

with qcl_items as (

    select distinct
        item_code,
        item_name

    from {{ ref('stg_faostat__production') }}

),

with_commodity_info as (

    select
        q.item_code,
        q.item_name,

        -- From seed_commodity_selection
        coalesce(s.commodity_group, 'Other') as commodity_group,
        coalesce(s.strategic_reason, '') as strategic_reason,
        coalesce(s.is_selected, false) as is_strategic_commodity

    from qcl_items q
    left join {{ ref('seed_commodity_selection') }} s
        on q.item_code = s.item_code

),

with_fbs_mapping as (

    select
        *,
        case item_code
            when 15 then 2511   -- Wheat → Wheat and products
            when 27 then 2805   -- Rice paddy → Rice (Milled Equivalent)
            when 56 then 2514   -- Maize → Maize and products
            when 44 then 2513   -- Barley → Barley and products
            when 236 then 2555   -- Soybeans → Soybeans
            when 187 then 2911   -- Pulses → Pulses
            when 116 then 2531   -- Potatoes → Potatoes and products
            when 125 then 2533   -- Sweet potatoes → Sweet potatoes
            when 135 then 2532   -- Cassava → Cassava and products
            when 254 then 2777   -- Palm oil → Palm Oil
            when 156 then 2542   -- Sugar cane → Sugar (Raw Equivalent)
            else null
        end as fbs_item_code,

        case item_code
            when 15 then 'Wheat and products'
            when 27 then 'Rice (Milled Equivalent)'
            when 56 then 'Maize and products'
            when 44 then 'Barley and products'
            when 236 then 'Soybeans'
            when 187 then 'Pulses'
            when 116 then 'Potatoes and products'
            when 125 then 'Sweet potatoes'
            when 135 then 'Cassava and products'
            when 254 then 'Palm Oil'
            when 156 then 'Sugar (Raw Equivalent)'
            else null
        end as fbs_item_name,

        -- Commodity group order for Power BI sorting
        case commodity_group
            when 'Cereals' then 1
            when 'Protein Crops' then 2
            when 'Roots and Tubers' then 3
            when 'Oil Crops' then 4
            when 'Sugar Crops' then 5
            else 9
        end                                                 as commodity_group_order

    from with_commodity_info

),

final as (

    select
        -- ── SURROGATE KEY ──
        {{ dbt_utils.generate_surrogate_key(['item_code']) }}   as item_key,

        -- ── QCL CODES (Primary) ──
        item_code,
        item_name,

        -- ── FBS CODES (For cross-dataset reference) ──
        fbs_item_code,
        fbs_item_name,

        -- ── COMMODITY CLASSIFICATION ──
        commodity_group,
        commodity_group_order,
        strategic_reason,
        is_strategic_commodity,

        -- ── METADATA ──
        current_timestamp()                                     as _dim_updated_at

    from with_fbs_mapping

)

select * from final