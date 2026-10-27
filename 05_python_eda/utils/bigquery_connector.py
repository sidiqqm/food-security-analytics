"""
BigQuery Data Connector untuk EDA

Mengambil data dari BigQuery Reporting dan Mart layer
yang telah dibangun oleh dbt di Stage 5.
"""

import pandas as pd
from google.cloud import bigquery
from google.oauth2 import service_account
from pathlib import Path
from typing import Optional
import logging

logger = logging.getLogger(__name__)

# KONFIGURASI — sesuaikan dengan GCP project Anda
PROJECT_ID  = 'faostat-analytics'
DATASET_RPT = 'dbt_faostat_dev_reporting'
DATASET_MRT = 'dbt_faostat_dev_marts'
SA_KEY_PATH = Path(__file__).parent.parent.parent / 'gcp_service_account.json'


def get_client() -> bigquery.Client:
    """Initialize BigQuery client."""
    if SA_KEY_PATH.exists():
        creds = service_account.Credentials.from_service_account_file(
            str(SA_KEY_PATH),
            scopes=['https://www.googleapis.com/auth/cloud-platform']
        )
        return bigquery.Client(project=PROJECT_ID, credentials=creds)
    return bigquery.Client(project=PROJECT_ID)


def query_to_df(sql: str, client: Optional[bigquery.Client] = None) -> pd.DataFrame:
    """Execute SQL query and return as DataFrame."""
    if client is None:
        client = get_client()
    return client.query(sql).to_dataframe()


# DATA LOADING FUNCTIONS
def load_global_production_trends(client=None) -> pd.DataFrame:
    """
    Load global production trends dari reporting layer.
    Returns: item × year level aggregates with YoY growth and CAGR.
    """
    sql = f"""
        SELECT
            item_code, item_name, commodity_group,
            year, decade, period_label,
            total_production_tonnes,
            total_production_million_tonnes,
            total_area_harvested_ha,
            avg_yield_kg_ha_weighted,
            country_count_with_data,
            yoy_production_growth_pct,
            cagr_10y_pct,
            notable_event,
            is_notable_event_year
        FROM `{DATASET_RPT}.rpt_global_production_trends`
        ORDER BY item_code, year
    """
    return query_to_df(sql, client)


def load_country_production(
    item_codes: list = None,
    year_start: int = 1991,
    year_end:   int = 2022,
    client=None
) -> pd.DataFrame:
    """
    Load country-level production for specific commodities.
    Default: all strategic commodities, full project period.
    """
    item_filter = ""
    if item_codes:
        codes_str = ', '.join(str(c) for c in item_codes)
        item_filter = f"AND p.item_code IN ({codes_str})"

    sql = f"""
        SELECT
            p.area_code, p.area_name, p.item_code, p.item_name,
            p.year,
            a.fao_region, a.income_group, a.geographic_region,
            a.development_status,
            p.production_tonnes,
            p.production_million_tonnes,
            p.area_harvested_ha,
            p.yield_kg_ha,
            p.quality_score_avg,
            p.is_strategic_commodity
        FROM `{DATASET_MRT}.fct_production` p
        LEFT JOIN `{DATASET_MRT}.dim_area` a
            ON p.area_key = a.area_key
        WHERE
            p.is_strategic_commodity = true
            AND p.has_production     = true
            AND p.year BETWEEN {year_start} AND {year_end}
            {item_filter}
        ORDER BY p.item_code, p.year, p.production_tonnes DESC
    """
    return query_to_df(sql, client)


def load_trade_data(
    item_codes: list = None,
    client=None
) -> pd.DataFrame:
    """Load trade balance data with IDR."""
    item_filter = ""
    if item_codes:
        codes_str = ', '.join(str(c) for c in item_codes)
        item_filter = f"AND item_code IN ({codes_str})"

    sql = f"""
        SELECT
            area_code, area_name, item_code, item_name,
            year, fao_region, income_group, commodity_group,
            export_qty_tonnes, import_qty_tonnes, net_trade_qty_tonnes,
            export_val_1000usd, import_val_1000usd, net_trade_val_1000usd,
            import_dependency_ratio_pct,
            trade_coverage_ratio_pct,
            idr_category,
            is_net_exporter
        FROM `{DATASET_RPT}.rpt_trade_balance`
        WHERE 1=1 {item_filter}
        ORDER BY item_code, year, area_code
    """
    return query_to_df(sql, client)


def load_food_security_data(client=None) -> pd.DataFrame:
    """Load country-level food security / DES data."""
    sql = f"""
        SELECT
            area_code, area_name, year,
            fao_region, income_group, geographic_region, development_status,
            income_group_order, decade, period_label,
            des_kcal_cap_day, des_adequacy_ratio, des_adequacy_pct,
            des_category, des_category_order, is_food_secure,
            des_yoy_change_kcal, des_yoy_change_pct,
            protein_g_cap_day, fat_g_cap_day,
            pct_kcal_from_protein, pct_kcal_from_fat, pct_kcal_from_carbs,
            quality_score_des,
            notable_event, is_notable_event_year
        FROM `{DATASET_RPT}.rpt_food_security_dashboard`
        ORDER BY area_code, year
    """
    return query_to_df(sql, client)
    