{{
    config(
        materialized = 'table',
        description  = """
            Dimension table: Calendar years with period attributes.

            Covers 1991–2022 (full production/trade period).
            FBS period (2010–2022) flagged separately.
            Grain: One row per year.
        """
    )
}}

-- Generate year spine from 1991 to 2022
with year_spine as (

    {{
        dbt_utils.date_spine(
            datepart   = "year",
            start_date = "cast('1991-01-01' as date)",
            end_date   = "cast('2023-01-01' as date)"
        )
    }}

),

years as (

    select
        extract(year from date_year) as year

    from year_spine

),

final as (

    select

        {{ dbt_utils.generate_surrogate_key(['year']) }} as year_key,

        year,

        concat(
            cast(floor(year / 10) * 10 as string),
            's'
        ) as decade,

        case
            when year between 1991 and 2000
                then '1991–2000'

            when year between 2001 and 2010
                then '2001–2010'

            when year between 2011 and 2022
                then '2011–2022'
        end as period_label,

        case
            when year between 2013 and 2022
                then 'Last 10 Years (2013–2022)'

            when year between 2003 and 2012
                then 'Previous 10 Years (2003–2012)'

            else 'Earlier Period'
        end as decade_window,

        case
            when year between {{ var('project_year_start') }}
                         and {{ var('project_year_end') }}
                then true
            else false
        end as is_in_production_period,

        case
            when year between {{ var('project_year_start_fbs') }}
                         and {{ var('project_year_end') }}
                then true
            else false
        end as is_in_fbs_period,

        case
            when year = 2008
                then 'Global Food Price Crisis'

            when year = 2010
                then 'Russian Heat Wave / Export Ban'

            when year = 2011
                then 'Arab Spring / Food Price Spike'

            when year = 2020
                then 'COVID-19 Pandemic'

            when year = 2022
                then 'Russia-Ukraine War / Supply Disruption'

            else null
        end as notable_event,

        case
            when year in (2008, 2010, 2011, 2020, 2022)
                then true
            else false
        end as is_notable_event_year,

        current_timestamp() as _dim_updated_at

    from years

)

select *
from final