"""
=============================================================================
Script 3: Verify BigQuery Upload & Run Initial SQL Checks
=============================================================================
Project  : Global Food Security Analytics
Purpose  : Post-upload verification via BigQuery SQL queries.
           Confirms data integrity, checks sample rows, and validates
           that raw tables are queryable and complete.
Run      : python 03_verify_upload.py
=============================================================================
"""

import sys
import logging
import pandas as pd
from pathlib import Path
from datetime import datetime

try:
    from google.cloud import bigquery
    from google.oauth2 import service_account
except ImportError:
    print("Run: pip install google-cloud-bigquery")
    sys.exit(1)

# CONFIGURATION

BASE_DIR        = Path(__file__).resolve().parent.parent
ROOT_DIR        = BASE_DIR.parent
SA_KEY_PATH     = ROOT_DIR / 'gcp_service_account.json'
GCP_PROJECT_ID  = 'faostat-analytics'
BQ_DATASET      = 'raw_faostat'
OUTPUT_DIR      = BASE_DIR / 'outputs'

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s | %(levelname)-8s | %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger(__name__)


# VERIFICATION QUERIES
VERIFICATION_QUERIES = {
    'production': {
        'table': 'production_crops_livestock_raw',
        'checks': [
            {
                'name': 'Row Count',
                'sql': """
                    SELECT COUNT(*) as row_count
                    FROM `{project}.{dataset}.production_crops_livestock_raw`
                """,
            },
            {
                'name': 'Year Range',
                'sql': """
                    SELECT MIN(Year) as min_year, MAX(Year) as max_year
                    FROM `{project}.{dataset}.production_crops_livestock_raw`
                """,
            },
            {
                'name': 'Unique Countries',
                'sql': """
                    SELECT COUNT(DISTINCT Area_Code) as country_count
                    FROM `{project}.{dataset}.production_crops_livestock_raw`
                    WHERE Area_Code < 1000
                """,
            },
            {
                'name': 'Flag Distribution',
                'sql': """
                    SELECT 
                        CASE WHEN Flag = '' THEN 'Official (blank)' ELSE Flag END as flag,
                        COUNT(*) as row_count,
                        ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as pct
                    FROM `{project}.{dataset}.production_crops_livestock_raw`
                    GROUP BY Flag
                    ORDER BY row_count DESC
                    LIMIT 10
                """,
            },
            {
                'name': 'Top 5 Producing Countries (Wheat, 2020)',
                'sql': """
                    SELECT 
                        Area,
                        Area_Code,
                        ROUND(Value / 1e6, 2) as production_million_tonnes
                    FROM `{project}.{dataset}.production_crops_livestock_raw`
                    WHERE 
                        Item_Code = 15          -- Wheat
                        AND Element_Code = 5510 -- Production
                        AND Year = 2020
                        AND Area_Code < 1000    -- Individual countries only
                        AND Value IS NOT NULL
                    ORDER BY Value DESC
                    LIMIT 5
                """,
            },
            {
                'name': 'Audit Column Check',
                'sql': """
                    SELECT 
                        MIN(_loaded_at) as first_loaded,
                        MAX(_loaded_at) as last_loaded,
                        COUNT(DISTINCT _source_file) as source_files
                    FROM `{project}.{dataset}.production_crops_livestock_raw`
                """,
            },
        ]
    },
    'trade': {
        'table': 'trade_crops_livestock_raw',
        'checks': [
            {
                'name': 'Row Count',
                'sql': """
                    SELECT COUNT(*) as row_count
                    FROM `{project}.{dataset}.trade_crops_livestock_raw`
                """,
            },
            {
                'name': 'Elements Available',
                'sql': """
                    SELECT Element, Element_Code, COUNT(*) as row_count
                    FROM `{project}.{dataset}.trade_crops_livestock_raw`
                    GROUP BY Element, Element_Code
                    ORDER BY row_count DESC
                """,
            },
            {
                'name': 'Top Wheat Exporters by Value (2020)',
                'sql': """
                    SELECT 
                        Area,
                        ROUND(Value / 1000, 1) as export_value_million_usd
                    FROM `{project}.{dataset}.trade_crops_livestock_raw`
                    WHERE 
                        Item_Code = 15          -- Wheat
                        AND Element = 'Export Value'
                        AND Year = 2020
                        AND Area_Code < 1000
                        AND Value IS NOT NULL
                    ORDER BY Value DESC
                    LIMIT 5
                """,
            },
        ]
    },
    'fbs': {
        'table': 'food_balance_sheets_raw',
        'checks': [
            {
                'name': 'Row Count',
                'sql': """
                    SELECT COUNT(*) as row_count
                    FROM `{project}.{dataset}.food_balance_sheets_raw`
                """,
            },
            {
                'name': 'Year Range (should be 2010-2022)',
                'sql': """
                    SELECT MIN(Year) as min_year, MAX(Year) as max_year
                    FROM `{project}.{dataset}.food_balance_sheets_raw`
                """,
            },
            {
                'name': 'DES Global Average 2022 (sanity check ~2900 kcal)',
                'sql': """
                    SELECT 
                        Area,
                        ROUND(Value, 0) as kcal_per_capita_per_day
                    FROM `{project}.{dataset}.food_balance_sheets_raw`
                    WHERE
                        Area IN ('World', 'Global')
                        AND Item_Code = 2901    -- Grand Total
                        AND Element LIKE '%kcal%'
                        AND Year = 2022
                    LIMIT 3
                """,
            },
        ]
    }
}


# RUN VERIFICATION
def run_verification(client: bigquery.Client) -> None:
    logger.info("=" * 60)
    logger.info("BIGQUERY UPLOAD VERIFICATION")
    logger.info(f"Project: {GCP_PROJECT_ID} | Dataset: {BQ_DATASET}")
    logger.info("=" * 60)

    for dataset_name, config in VERIFICATION_QUERIES.items():
        logger.info(f"\n{'─'*50}")
        logger.info(f"Verifying: {dataset_name.upper()}")
        logger.info(f"Table: {GCP_PROJECT_ID}.{BQ_DATASET}.{config['table']}")
        logger.info(f"{'─'*50}")

        for check in config['checks']:
            sql = check['sql'].format(
                project=GCP_PROJECT_ID,
                dataset=BQ_DATASET
            )

            try:
                df = client.query(sql).to_dataframe()
                logger.info(f"\n  {check['name']}:")
                logger.info(df.to_string(index=False, justify='left'))
            except Exception as e:
                logger.error(f"\n  {check['name']} FAILED: {e}")


def main():
    # Initialize client
    if SA_KEY_PATH.exists():
        credentials = service_account.Credentials.from_service_account_file(
            str(SA_KEY_PATH),
            scopes=['https://www.googleapis.com/auth/cloud-platform']
        )
        client = bigquery.Client(project=GCP_PROJECT_ID, credentials=credentials)
    else:
        client = bigquery.Client(project=GCP_PROJECT_ID)

    run_verification(client)

    logger.info("\n" + "=" * 60)
    logger.info("VERIFICATION COMPLETE")
    logger.info("Next Step: Stage 4 — dbt Setup & Staging Layer")
    logger.info("=" * 60)


if __name__ == '__main__':
    main()