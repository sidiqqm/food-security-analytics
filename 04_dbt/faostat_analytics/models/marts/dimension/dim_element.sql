{{
    config(
        materialized = 'table',
        description  = """
            Dimension table: Measurement elements across all FAOSTAT datasets.

            Contains all element codes and their descriptions from:
            - Production (QCL): Area Harvested, Yield, Production
            - Trade (TCL): Export/Import Quantity and Value
            - Food Balance Sheets (FBS): DES, Protein, Fat, Food Supply

            Grain: One row per (dataset_source, element_code).
        """
    )
}}

with element_definitions as (

    select *
    from unnest([
        struct(
            'production' as dataset_source,
            5312 as element_code,
            'Area harvested' as element_name,
            'ha' as unit_standardized,
            'area_harvested' as element_category,
            'Crop' as domain,
            'Agricultural land area actually harvested (not planted).' as description
        ),

        struct(
            'production' as dataset_source,
            5417 as element_code,
            'Yield' as element_name,
            'kg/ha' as unit_standardized,
            'yield' as element_category,
            'Crop' as domain,
            'Standardized from hg/ha. Production per unit of harvested area.' as description
        ),

        struct(
            'production' as dataset_source,
            5510 as element_code,
            'Production' as element_name,
            'tonnes' as unit_standardized,
            'production' as element_category,
            'Crop' as domain,
            'Total agricultural production in metric tonnes.' as description
        ),

        struct(
            'trade' as dataset_source,
            5610 as element_code,
            'Export Quantity' as element_name,
            'tonnes' as unit_standardized,
            'export_quantity' as element_category,
            'Trade' as domain,
            'Total export quantity in metric tonnes.' as description
        ),

        struct(
            'trade' as dataset_source,
            5622 as element_code,
            'Export Value' as element_name,
            '1000 USD' as unit_standardized,
            'export_value' as element_category,
            'Trade' as domain,
            'Total export value in thousands of US dollars (nominal).' as description
        ),

        struct(
            'trade' as dataset_source,
            5910 as element_code,
            'Import Quantity' as element_name,
            'tonnes' as unit_standardized,
            'import_quantity' as element_category,
            'Trade' as domain,
            'Total import quantity in metric tonnes.' as description
        ),

        struct(
            'trade' as dataset_source,
            5922 as element_code,
            'Import Value' as element_name,
            '1000 USD' as unit_standardized,
            'import_value' as element_category,
            'Trade' as domain,
            'Total import value in thousands of US dollars (nominal).' as description
        ),

        struct(
            'fbs' as dataset_source,
            664 as element_code,
            'Food supply (kcal/capita/day)' as element_name,
            'kcal/capita/day' as unit_standardized,
            'dietary_energy_supply' as element_category,
            'Food Security' as domain,
            'Primary KPI. Total dietary energy supply per capita per day.' as description
        ),

        struct(
            'fbs' as dataset_source,
            674 as element_code,
            'Protein supply quantity (g/capita/day)' as element_name,
            'g/capita/day' as unit_standardized,
            'protein_supply' as element_category,
            'Food Security' as domain,
            'Total protein supply per capita per day.' as description
        ),

        struct(
            'fbs' as dataset_source,
            684 as element_code,
            'Fat supply quantity (g/capita/day)' as element_name,
            'g/capita/day' as unit_standardized,
            'fat_supply' as element_category,
            'Food Security' as domain,
            'Total fat supply per capita per day.' as description
        ),

        struct(
            'fbs' as dataset_source,
            5301 as element_code,
            'Food supply quantity (kg/capita/yr)' as element_name,
            'kg/capita/yr' as unit_standardized,
            'food_quantity' as element_category,
            'Food Security' as domain,
            'Total food quantity available per capita per year.' as description
        ),

        struct(
            'fbs' as dataset_source,
            5511 as element_code,
            'Production' as element_name,
            'tonnes' as unit_standardized,
            'production' as element_category,
            'Food Balance' as domain,
            'FBS production (converted from 1000t to tonnes in staging).' as description
        ),

        struct(
            'fbs' as dataset_source,
            5611 as element_code,
            'Import Quantity' as element_name,
            'tonnes' as unit_standardized,
            'import_quantity' as element_category,
            'Food Balance' as domain,
            'FBS import quantity (converted from 1000t in staging).' as description
        ),

        struct(
            'fbs' as dataset_source,
            5911 as element_code,
            'Export Quantity' as element_name,
            'tonnes' as unit_standardized,
            'export_quantity' as element_category,
            'Food Balance' as domain,
            'FBS export quantity (converted from 1000t in staging).' as description
        )

    ])

),

final as (

    select

        {{ dbt_utils.generate_surrogate_key([
            'dataset_source',
            'element_code'
        ]) }} as element_key,

        dataset_source,
        element_code,
        element_name,
        unit_standardized,
        element_category,
        domain,
        description,
        case
            when element_code = 664
                then true
            else false
        end as is_primary_kpi,
        case
            when element_category in (
                'production',
                'area_harvested',
                'export_quantity',
                'import_quantity',
                'food_quantity'
            )
                then 'Volume'

            when element_category = 'yield'
                then 'Ratio'

            when element_category in (
                'export_value',
                'import_value'
            )
                then 'Value'

            when element_category in (
                'dietary_energy_supply',
                'protein_supply',
                'fat_supply'
            )
                then 'Per Capita'

            else 'Other'
        end as measurement_type,

        current_timestamp() as _dim_updated_at

    from element_definitions

)

select *
from final