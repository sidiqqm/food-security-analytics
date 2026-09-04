"""
=============================================================================
Script 2: Upload FAOSTAT CSV to BigQuery Raw Layer
=============================================================================
Project  : Global Food Security Analytics
Purpose  : Upload 3 validated FAOSTAT CSV files to BigQuery.
           - Creates dataset if not exists
           - Creates tables with explicit schema (no auto-detect)
           - Adds audit columns: _loaded_at, _source_file
           - Logs row counts for reconciliation
Run      : python 02_upload_to_bigquery.py
Requires : google-cloud-bigquery, google-cloud-bigquery-storage, pandas
           Service account JSON in project root
=============================================================================
"""

import os
import sys
import json
import logging
import hashlib
import pandas as pd
import numpy as np
import tempfile
import pyarrow as pa
import pyarrow.parquet as pq
from datetime import datetime, timezone
from pathlib import Path


# DEPENDENCY CHECK

try:
    from google.cloud import bigquery
    from google.oauth2 import service_account
except ImportError:
    print(" google-cloud-bigquery not installed.")
    print("   Run: pip install google-cloud-bigquery google-cloud-bigquery-storage pyarrow")
    sys.exit(1)

# CONFIGURATION

BASE_DIR    = Path(__file__).resolve().parent.parent
ROOT_DIR    = BASE_DIR.parent
SCHEMA_DIR  = BASE_DIR / 'schemas'
OUTPUT_DIR  = BASE_DIR / 'outputs'
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# GCP Configuration — sesuaikan dengan project Anda
GCP_PROJECT_ID  = 'faostat-analytics'         # Ganti dengan GCP Project ID Anda
BQ_DATASET      = 'raw_faostat'
BQ_LOCATION     = 'US'                         # Atau 'asia-southeast1' untuk region Asia

# Path ke service account JSON
SA_KEY_PATH = ROOT_DIR / 'gcp_service_account.json'

# Dataset configurations
DATASETS = {
    'production': {
        'csv_path':    BASE_DIR / 'raw' / 'QCL_Production_Crops_Livestock.csv',
        'table_name':  'production_crops_livestock_raw',
        'schema_path': SCHEMA_DIR / 'schema_production_raw.json',
        'source_file': 'QCL_Production_Crops_Livestock.csv',
    },
    'trade': {
        'csv_path':    BASE_DIR / 'raw' / 'TCL_Trade_Crops_Livestock.csv',
        'table_name':  'trade_crops_livestock_raw',
        'schema_path': SCHEMA_DIR / 'schema_trade_raw.json',
        'source_file': 'TCL_Trade_Crops_Livestock.csv',
    },
    'fbs': {
        'csv_path':    BASE_DIR / 'raw' / 'FBS_Food_Balance_Sheets.csv',
        'table_name':  'food_balance_sheets_raw',
        'schema_path': SCHEMA_DIR / 'schema_fbs_raw.json',
        'source_file': 'FBS_Food_Balance_Sheets.csv',
    },
}

# Upload settings
CHUNK_SIZE    = 100_000     # Rows per upload chunk (untuk dataset besar)
WRITE_MODE    = 'WRITE_TRUNCATE'  # WRITE_TRUNCATE = replace existing data

# LOGGING
log_file = OUTPUT_DIR / 'upload_log.txt'
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s | %(levelname)-8s | %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S',
    handlers=[
        logging.FileHandler(log_file, mode='w'),
        logging.StreamHandler(sys.stdout),
    ]
)
logger = logging.getLogger(__name__)


# BIGQUERY CLIENT SETUP
def get_bq_client() -> bigquery.Client:
    """
    Initialize BigQuery client menggunakan service account.
    
    Jika SA_KEY_PATH tidak ditemukan, coba Application Default Credentials
    (berguna jika running di GCP environment).
    """
    if SA_KEY_PATH.exists():
        credentials = service_account.Credentials.from_service_account_file(
            str(SA_KEY_PATH),
            scopes=['https://www.googleapis.com/auth/cloud-platform']
        )
        client = bigquery.Client(
            project=GCP_PROJECT_ID,
            credentials=credentials,
            location=BQ_LOCATION,
        )
        logger.info(f"  BigQuery client initialized with service account: {SA_KEY_PATH.name}")
    else:
        # Fallback to Application Default Credentials
        # Requires: gcloud auth application-default login
        client = bigquery.Client(project=GCP_PROJECT_ID, location=BQ_LOCATION)
        logger.info("  BigQuery client initialized with Application Default Credentials")

    return client


# DATASET CREATION
def ensure_dataset_exists(client: bigquery.Client) -> None:
    """
    Create BigQuery dataset if it doesn't exist.
    
    Dataset properties:
    - Location: US (untuk konsistensi dengan public datasets)
    - Description: raw layer untuk FAOSTAT data
    - Labels: untuk cost tracking
    """
    dataset_ref  = f"{GCP_PROJECT_ID}.{BQ_DATASET}"
    dataset_obj  = bigquery.Dataset(dataset_ref)

    dataset_obj.location    = BQ_LOCATION
    dataset_obj.description = (
        "Raw Layer — FAOSTAT Global Food Security Analytics. "
        "Contains unmodified copies of FAOSTAT CSV files. "
        "Do not query directly for analysis — use dbt-transformed marts."
    )
    dataset_obj.labels = {
        'project': 'faostat-analytics',
        'layer':   'raw',
        'team':    'data-analytics',
    }

    try:
        client.create_dataset(dataset_obj, exists_ok=True)
        logger.info(f"   Dataset ready: {dataset_ref}")
    except Exception as e:
        logger.error(f"   Failed to create dataset: {e}")
        raise


# DATA PREPARATION
def load_and_prepare_csv(csv_path: Path, source_file: str) -> pd.DataFrame:
    """
    Load CSV dan tambahkan audit columns.
    
    Audit columns (_loaded_at, _source_file) memungkinkan:
    - Tracking kapan data ini diload
    - Identifikasi file sumber jika ada multiple uploads
    - Reproducibility audit
    """
    logger.info(f"  Loading CSV: {csv_path.name}")

    # Detect encoding
    encodings = ['utf-8', 'utf-8-sig', 'latin-1', 'cp1252']
    df = None
    used_encoding = None

    for enc in encodings:
        try:
            df = pd.read_csv(csv_path, encoding=enc, low_memory=False)
            used_encoding = enc
            break
        except UnicodeDecodeError:
            continue

    if df is None:
        raise ValueError(f"Cannot decode {csv_path} with any known encoding")

    logger.info(f"  Encoding: {used_encoding} | Shape: {df.shape[0]:,} × {df.shape[1]}")

    # Strip whitespace from column names
    df.columns = df.columns.str.strip()

    # Standardize column names — ganti spasi dengan underscore untuk BigQuery compatibility
    # BigQuery tidak support spasi dalam nama kolom
    col_rename = {}
    for col in df.columns:
        # Remove parentheses dan special chars, replace space with underscore
        new_col = (
            col
            .replace(' ', '_')
            .replace('(', '')
            .replace(')', '')
            .replace('-', '_')
            .replace('/', '_')
            .replace(',', '')
        )
        col_rename[col] = new_col

    df = df.rename(columns=col_rename)

    # Add audit metadata columns
    load_ts = datetime.now(timezone.utc)
    df['_loaded_at']   = load_ts
    df['_source_file'] = source_file

    # Handle Flag column: NaN Flag = Official data (empty string)
    # Store as empty string to differentiate from actual missing (Flag 'M')
    if 'Flag' in df.columns:
        df['Flag'] = df['Flag'].fillna('').str.strip()

    # Ensure Value is float (FAOSTAT sometimes stores as string with commas)
    if 'Value' in df.columns:
        df['Value'] = pd.to_numeric(df['Value'], errors='coerce')

    # Ensure Year and codes are integer
    for int_col in ['Area_Code', 'Item_Code', 'Element_Code', 'Year_Code', 'Year']:
        if int_col in df.columns:
            df[int_col] = pd.to_numeric(df[int_col], errors='coerce').astype('Int64')

    return df


# SCHEMA LOADING
def load_schema(schema_path: Path) -> list:
    """
    Load BigQuery schema dari JSON file.
    
    Schema didefinisikan secara eksplisit (bukan auto-detect) untuk memastikan
    tipe data yang tepat dan konsisten.
    """
    with open(schema_path, 'r') as f:
        schema_json = json.load(f)

    schema = []
    for field in schema_json:
        schema.append(bigquery.SchemaField(
            name=field['name'],
            field_type=field['type'],
            mode=field.get('mode', 'NULLABLE'),
            description=field.get('description', ''),
        ))

    return schema


def align_df_to_schema(df: pd.DataFrame, schema: list) -> pd.DataFrame:
    """
    Align DataFrame columns ke BigQuery schema.
    
    Menambahkan kolom yang ada di schema tapi tidak di DataFrame sebagai NULL,
    dan membuang kolom yang tidak ada di schema.
    """
    schema_col_names = [field.name for field in schema]

    # Add missing columns as None
    for col in schema_col_names:
        if col not in df.columns:
            df[col] = None

    # Reorder to match schema
    df = df[[col for col in schema_col_names if col in df.columns]]

    return df


# BIGQUERY UPLOAD
def upload_to_bigquery(
    client: bigquery.Client,
    df: pd.DataFrame,
    table_name: str,
    schema: list,
) -> int:
    """
    Upload DataFrame ke BigQuery dengan chunked loading.
    
    Chunked loading diperlukan untuk dataset besar (>100MB) untuk
    menghindari timeout dan memory issues.
    
    Returns: jumlah rows yang berhasil diupload
    """
    table_id = f"{GCP_PROJECT_ID}.{BQ_DATASET}.{table_name}"

    job_config = bigquery.LoadJobConfig(
        schema=schema,
        write_disposition=WRITE_MODE,
        source_format=bigquery.SourceFormat.PARQUET,
    )

    # Convert ke parquet format untuk upload yang lebih efisien
    # Parquet lebih baik daripada CSV untuk BigQuery karena:
    # 1. Type-safe (tidak ada ambiguitas tipe data)
    # 2. Compressed (lebih cepat transfer)
    # 3. Tidak ada masalah encoding

    logger.info(f"  Converting to Parquet format for upload...")

    with tempfile.NamedTemporaryFile(suffix='.parquet', delete=False) as tmp:
        tmp_path = tmp.name

    try:
        # Buat pyarrow schema dari BigQuery schema
        pa_schema_fields = []
        for field in schema:
            bq_to_pa = {
                'INTEGER': pa.int64(),
                'INT64':   pa.int64(),
                'FLOAT64': pa.float64(),
                'FLOAT':   pa.float64(),
                'STRING':  pa.string(),
                'BOOL':    pa.bool_(),
                'TIMESTAMP': pa.timestamp('us', tz='UTC'),
                'DATE':    pa.date32(),
            }
            pa_type = bq_to_pa.get(field.field_type, pa.string())
            pa_schema_fields.append(pa.field(field.name, pa_type, nullable=True))

        pa_schema = pa.schema(pa_schema_fields)

        # Write parquet
        table_pa = pa.Table.from_pandas(df, schema=pa_schema, safe=False)
        pq.write_table(table_pa, tmp_path, compression='snappy')

        logger.info(f"  Uploading {len(df):,} rows to {table_id}...")

        with open(tmp_path, 'rb') as source_file:
            job = client.load_table_from_file(
                source_file,
                table_id,
                job_config=job_config,
            )

        # Wait for job to complete
        job.result()

        if job.errors:
            logger.error(f"   Upload errors: {job.errors}")
            raise Exception(f"BigQuery upload failed: {job.errors}")

        # Verify row count
        table_ref = client.get_table(table_id)
        bq_row_count = table_ref.num_rows

        logger.info(f"   Upload complete: {bq_row_count:,} rows in BigQuery")
        return bq_row_count

    finally:
        os.unlink(tmp_path)  # Cleanup temp file


# =============================================================================
# RECONCILIATION
# =============================================================================

def reconcile_row_counts(
    csv_row_count: int,
    bq_row_count: int,
    dataset_name: str,
) -> dict:
    """
    Verify bahwa jumlah baris di CSV = jumlah baris di BigQuery.
    
    Perbedaan kecil (< 0.01%) bisa terjadi karena header row,
    tapi perbedaan besar menandakan masalah upload.
    """
    diff = abs(csv_row_count - bq_row_count)
    diff_pct = diff / csv_row_count * 100 if csv_row_count > 0 else 100

    status = 'PASS' if diff_pct < 0.01 else ('WARN' if diff_pct < 1.0 else 'FAIL')

    result = {
        'dataset':       dataset_name,
        'csv_rows':      csv_row_count,
        'bq_rows':       bq_row_count,
        'difference':    diff,
        'diff_pct':      round(diff_pct, 4),
        'status':        status,
        'verified_at':   datetime.now(timezone.utc).isoformat(),
    }

    icon = {'PASS': '', 'WARN': '', 'FAIL': ''}[status]
    logger.info(
        f"  {icon} Reconciliation [{status}]: "
        f"CSV={csv_row_count:,} | BQ={bq_row_count:,} | "
        f"Diff={diff:,} ({diff_pct:.4f}%)"
    )

    return result


# =============================================================================
# MAIN
# =============================================================================

def main():
    logger.info("=" * 60)
    logger.info("FAOSTAT → BIGQUERY RAW LAYER UPLOAD")
    logger.info(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    logger.info(f"Target:  {GCP_PROJECT_ID}.{BQ_DATASET}")
    logger.info("=" * 60)

    # Initialize BigQuery client
    logger.info("\n[1/5] Initializing BigQuery connection...")
    try:
        client = get_bq_client()
        # Test connection
        client.list_datasets(max_results=1)
        logger.info(f"   Connected to GCP Project: {GCP_PROJECT_ID}")
    except Exception as e:
        logger.error(f"   BigQuery connection failed: {e}")
        logger.error(
            "  Troubleshooting:"
            "\n  1. Check GCP_PROJECT_ID in script config"
            "\n  2. Verify gcp_service_account.json path and permissions"
            "\n  3. Ensure BigQuery API is enabled in GCP Console"
        )
        sys.exit(1)

    # Ensure dataset exists
    logger.info(f"\n[2/5] Ensuring BigQuery dataset exists: {BQ_DATASET}")
    ensure_dataset_exists(client)

    # Process each dataset
    reconciliation_results = []
    
    for idx, (name, cfg) in enumerate(DATASETS.items(), start=3):
        logger.info(f"\n[{idx}/5] Processing: {name.upper()}")
        logger.info(f"  {'─'*50}")

        try:
            # Load schema
            schema = load_schema(cfg['schema_path'])
            logger.info(f"  Schema loaded: {len(schema)} fields")

            # Load and prepare CSV
            df = load_and_prepare_csv(cfg['csv_path'], cfg['source_file'])
            csv_row_count = len(df)

            # Align to schema
            df = align_df_to_schema(df, schema)

            # Upload
            bq_row_count = upload_to_bigquery(
                client, df, cfg['table_name'], schema
            )

            # Reconcile
            recon = reconcile_row_counts(csv_row_count, bq_row_count, name)
            reconciliation_results.append(recon)

        except FileNotFoundError:
            logger.error(
                f"   CSV not found: {cfg['csv_path']}"
                f"\n     Download from FAOSTAT first, then re-run this script."
            )
            continue
        except Exception as e:
            logger.error(f"   Failed to process {name}: {e}")
            raise

    # Save reconciliation report
    logger.info(f"\n[5/5] Saving reconciliation report...")
    if reconciliation_results:
        recon_df = pd.DataFrame(reconciliation_results)
        recon_path = OUTPUT_DIR / 'row_count_reconciliation.csv'
        recon_df.to_csv(recon_path, index=False)
        logger.info(f"   Reconciliation saved: {recon_path}")

        # Final summary
        logger.info(f"\n{'='*60}")
        logger.info("UPLOAD SUMMARY")
        logger.info(f"{'='*60}")
        all_passed = all(r['status'] == 'PASS' for r in reconciliation_results)
        for r in reconciliation_results:
            icon = {'PASS': '', 'WARN': '', 'FAIL': ''}[r['status']]
            logger.info(
                f"  {icon} {r['dataset'].upper():<15} "
                f"CSV: {r['csv_rows']:>10,} | "
                f"BQ: {r['bq_rows']:>10,}"
            )
        if all_passed:
            logger.info("\n ALL DATASETS SUCCESSFULLY UPLOADED TO BIGQUERY")
            logger.info("   Proceed to Stage 4: dbt Setup & Staging Layer")
        else:
            logger.warning("\n⚠️ Some datasets have reconciliation issues. Review log.")

    logger.info(f"\nUpload log saved: {log_file}")


if __name__ == '__main__':
    main()