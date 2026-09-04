"""
Validate 3 FAOSTAT CSV files before BigQuery upload. Catches encoding issues, structural problems, and obvious data
           quality issues BEFORE they become pipeline failures.
"""

import os
import sys
import json
import hashlib
import logging
import pandas as pd
import numpy as np
from datetime import datetime
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent.parent

CONFIG = {
    'production': {
        'path': BASE_DIR / 'raw' / 'QCL_Production_Crops_Livestock.csv',
        'expected_columns': [
            'Area Code', 'Area', 'Item Code', 'Item',
            'Element Code', 'Element', 'Year Code', 'Year',
            'Unit', 'Value', 'Flag'
        ],
        'expected_elements': ['Production', 'Area harvested', 'Yield'],
        'expected_units':    ['t', 'ha', 'hg/ha'],
        'year_min': 1961,
        'year_max': 2022,
        'min_rows': 1_000_000,
        'max_negative_pct': 0.01,
    },
    'trade': {
        'path': BASE_DIR / 'raw' / 'TCL_Trade_Crops_Livestock.csv',
        'expected_columns': [
            'Area Code', 'Area', 'Item Code', 'Item',
            'Element Code', 'Element', 'Year Code', 'Year',
            'Unit', 'Value', 'Flag'
        ],
        'expected_elements': [
            'Export Quantity', 'Export Value',
            'Import Quantity', 'Import Value'
        ],
        'expected_units':    ['t', '1000 USD'],
        'year_min': 1986,
        'year_max': 2022,
        'min_rows': 500_000,
        'max_negative_pct': 0.01,
    },
    'fbs': {
        'path': BASE_DIR / 'raw' / 'FBS_Food_Balance_Sheets.csv',
        'expected_columns': [
            'Area Code', 'Area', 'Item Code', 'Item',
            'Element Code', 'Element', 'Year Code', 'Year',
            'Unit', 'Value', 'Flag'
        ],
        'expected_elements': [
            'Food supply (kcal/capita/day)',
            'Protein supply quantity (g/capita/day)',
            'Fat supply quantity (g/capita/day)',
        ],
        'expected_units':    ['kcal/capita/day', 'g/capita/day', 'kg/capita/yr', '1000 t'],
        'year_min': 2010,
        'year_max': 2022,
        'min_rows': 50_000,
        'max_negative_pct': 0.05,
    },
}

OUTPUT_DIR = BASE_DIR / 'outputs'
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)


# LOGGING SETUP

log_file = OUTPUT_DIR / 'validation_report.txt'
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


# VALIDATION FUNCTIONS

class ValidationResult:
    """Container untuk hasil validasi setiap dataset."""
    def __init__(self, dataset_name: str):
        self.dataset_name = dataset_name
        self.checks = []
        self.passed = 0
        self.failed = 0
        self.warnings = 0

    def add(self, check_name: str, status: str, detail: str):
        """
        status: 'PASS', 'FAIL', 'WARN'
        """
        self.checks.append({
            'check': check_name,
            'status': status,
            'detail': detail,
        })
        if status == 'PASS':
            self.passed += 1
        elif status == 'FAIL':
            self.failed += 1
        elif status == 'WARN':
            self.warnings += 1

    def summary(self) -> str:
        total = self.passed + self.failed + self.warnings
        return (
            f"{self.dataset_name}: "
            f"{self.passed}/{total} passed | "
            f"{self.failed} failed | "
            f"{self.warnings} warnings"
        )

    @property
    def is_valid(self) -> bool:
        return self.failed == 0


def check_file_exists(path: Path, result: ValidationResult) -> bool:
    """Check 1: File exists and is not empty."""
    if not path.exists():
        result.add(
            'FILE_EXISTS',
            'FAIL',
            f"File not found: {path}. Run FAOSTAT download first."
        )
        return False

    size_mb = path.stat().st_size / (1024 * 1024)
    if size_mb < 0.1:
        result.add(
            'FILE_SIZE',
            'FAIL',
            f"File too small: {size_mb:.2f} MB. Possibly empty or corrupt."
        )
        return False

    result.add(
        'FILE_EXISTS',
        'PASS',
        f"File found: {path.name} ({size_mb:.1f} MB)"
    )
    return True


def check_encoding(path: Path, result: ValidationResult) -> tuple:
    """
    Check 2: Determine file encoding.
    
    FAOSTAT files menggunakan berbagai encoding. Kita coba dari yang
    paling umum ke paling tidak umum.
    """
    encodings = ['utf-8', 'utf-8-sig', 'latin-1', 'cp1252']
    
    for enc in encodings:
        try:
            # Baca hanya 10,000 baris pertama untuk cek encoding
            df_sample = pd.read_csv(path, encoding=enc, nrows=10_000, low_memory=False)
            result.add(
                'ENCODING',
                'PASS',
                f"Successfully decoded with: {enc}"
            )
            return enc, df_sample
        except UnicodeDecodeError:
            continue
        except Exception as e:
            result.add('ENCODING', 'FAIL', f"Unexpected error: {str(e)}")
            return None, pd.DataFrame()

    result.add(
        'ENCODING',
        'FAIL',
        f"Cannot decode file with any known encoding: {encodings}"
    )
    return None, pd.DataFrame()


def load_full_dataset(path: Path, encoding: str) -> pd.DataFrame:
    """Load full dataset dengan encoding yang telah terverifikasi."""
    try:
        df = pd.read_csv(path, encoding=encoding, low_memory=False)
        # Standardize column names: strip whitespace
        df.columns = df.columns.str.strip()
        return df
    except Exception as e:
        logger.error(f"Failed to load full dataset: {e}")
        return pd.DataFrame()


def check_columns(
    df: pd.DataFrame,
    expected_cols: list,
    result: ValidationResult
) -> None:
    """Check 3: Required columns present."""
    actual_cols = set(df.columns)
    
    # Strip whitespace from column names
    actual_cols_clean = {c.strip() for c in actual_cols}
    expected_set = set(expected_cols)
    
    missing = expected_set - actual_cols_clean
    extra   = actual_cols_clean - expected_set - {'Note', 'Area Code (M49)', 'Item Code (CPC)'}

    if not missing:
        result.add(
            'COLUMNS_PRESENT',
            'PASS',
            f"All {len(expected_cols)} required columns present. "
            f"Extra columns (allowed): {list(extra)}"
        )
    else:
        result.add(
            'COLUMNS_PRESENT',
            'FAIL',
            f"Missing required columns: {list(missing)}"
        )


def check_row_count(
    df: pd.DataFrame,
    min_rows: int,
    result: ValidationResult
) -> None:
    """Check 4: Minimum row count."""
    actual = len(df)
    if actual >= min_rows:
        result.add(
            'ROW_COUNT',
            'PASS',
            f"Row count: {actual:,} (minimum expected: {min_rows:,})"
        )
    else:
        result.add(
            'ROW_COUNT',
            'FAIL',
            f"Row count too low: {actual:,} (minimum expected: {min_rows:,}). "
            f"Dataset may be incomplete — re-download from FAOSTAT."
        )


def check_primary_key_uniqueness(df: pd.DataFrame, result: ValidationResult) -> None:
    """
    Check 5: Primary key uniqueness.
    
    Setiap kombinasi (Area Code, Item Code, Element Code, Year) harus unik.
    Duplicate menandakan masalah serius dalam file sumber.
    """
    pk_candidates = ['Area Code', 'Item Code', 'Element Code', 'Year']
    pk_cols = [c for c in pk_candidates if c in df.columns]

    if len(pk_cols) < 3:
        result.add(
            'PK_UNIQUENESS',
            'WARN',
            f"Cannot verify PK — missing columns: {set(pk_candidates) - set(pk_cols)}"
        )
        return

    total = len(df)
    unique = df[pk_cols].drop_duplicates().shape[0]
    dups   = total - unique

    if dups == 0:
        result.add(
            'PK_UNIQUENESS',
            'PASS',
            f"Primary key is unique across {unique:,} rows"
        )
    else:
        result.add(
            'PK_UNIQUENESS',
            'FAIL',
            f"{dups:,} duplicate primary keys found out of {total:,} rows "
            f"({dups/total*100:.2f}%). This will cause double-counting."
        )


def check_year_range(
    df: pd.DataFrame,
    year_min: int,
    year_max: int,
    result: ValidationResult
) -> None:
    """Check 6: Year range sanity."""
    if 'Year' not in df.columns:
        result.add('YEAR_RANGE', 'WARN', "'Year' column not found")
        return

    actual_min = df['Year'].min()
    actual_max = df['Year'].max()

    if actual_min <= year_min and actual_max >= year_max:
        result.add(
            'YEAR_RANGE',
            'PASS',
            f"Year range: {actual_min}–{actual_max} "
            f"(covers required {year_min}–{year_max})"
        )
    else:
        result.add(
            'YEAR_RANGE',
            'WARN',
            f"Year range: {actual_min}–{actual_max}. "
            f"Expected to at least cover {year_min}–{year_max}. "
            f"Check download settings."
        )


def check_elements_present(
    df: pd.DataFrame,
    expected_elements: list,
    result: ValidationResult
) -> None:
    """Check 7: Expected elements present in dataset."""
    if 'Element' not in df.columns:
        result.add('ELEMENTS', 'WARN', "'Element' column not found")
        return

    actual_elements = set(df['Element'].unique())
    missing = []
    
    for el in expected_elements:
        # Fuzzy match — FAOSTAT kadang menambahkan keterangan dalam kurung
        found = any(el.lower() in ae.lower() for ae in actual_elements)
        if not found:
            missing.append(el)

    if not missing:
        result.add(
            'ELEMENTS_PRESENT',
            'PASS',
            f"All {len(expected_elements)} expected elements found"
        )
    else:
        result.add(
            'ELEMENTS_PRESENT',
            'WARN',
            f"Elements not found: {missing}. "
            f"Verify download settings include these elements."
        )


def check_negative_values(
    df: pd.DataFrame,
    max_neg_pct: float,
    result: ValidationResult
) -> None:
    """
    Check 8: Negative value proportion.
    
    Untuk Production, nilai negatif tidak mungkin secara fisik.
    Untuk Trade, nilai negatif juga tidak seharusnya ada.
    Toleransi kecil diberikan untuk handling edge cases.
    """
    if 'Value' not in df.columns:
        result.add('NEGATIVE_VALUES', 'WARN', "'Value' column not found")
        return

    total_non_null = df['Value'].notna().sum()
    if total_non_null == 0:
        result.add('NEGATIVE_VALUES', 'WARN', "No non-null values found")
        return

    neg_count = (df['Value'] < 0).sum()
    neg_pct   = neg_count / total_non_null

    if neg_pct <= max_neg_pct:
        result.add(
            'NEGATIVE_VALUES',
            'PASS',
            f"Negative values: {neg_count:,} ({neg_pct*100:.3f}%) — within tolerance"
        )
    else:
        result.add(
            'NEGATIVE_VALUES',
            'FAIL',
            f"Excessive negative values: {neg_count:,} ({neg_pct*100:.2f}%) "
            f"— exceeds {max_neg_pct*100}% tolerance. Investigate source data."
        )


def check_flag_distribution(df: pd.DataFrame, result: ValidationResult) -> None:
    """
    Check 9: Flag distribution sanity.
    
    Flag 'M' (Missing) adalah normal untuk FAOSTAT, tapi jika > 50%
    maka data coverage terlalu rendah untuk analisis yang reliable.
    """
    if 'Flag' not in df.columns:
        result.add('FLAG_DIST', 'WARN', "'Flag' column not found")
        return

    # Standardize: NaN dan '' keduanya berarti Official
    flag_series = df['Flag'].fillna('').str.strip().str.upper()

    flag_dist = flag_series.value_counts(normalize=True) * 100
    missing_pct = flag_dist.get('M', 0.0)
    official_pct = flag_dist.get('', 0.0)  # Empty string = Official

    detail = (
        f"Official (blank): {official_pct:.1f}% | "
        f"Missing (M): {missing_pct:.1f}% | "
        f"Other flags: {100 - official_pct - missing_pct:.1f}%"
    )

    if missing_pct > 50:
        result.add('FLAG_DIST', 'FAIL', f"Too many missing values: {detail}")
    elif missing_pct > 30:
        result.add('FLAG_DIST', 'WARN', f"High missing rate: {detail}")
    else:
        result.add('FLAG_DIST', 'PASS', detail)


def check_area_code_types(df: pd.DataFrame, result: ValidationResult) -> None:
    """
    Check 10: Regional aggregate detection.
    
    Memverifikasi bahwa dataset berisi campuran data negara (area_code < 1000)
    dan agregat regional (area_code >= 1000), sebagaimana diharapkan dari
    FAOSTAT "Select All Countries" download.
    """
    if 'Area Code' not in df.columns:
        result.add('AREA_TYPES', 'WARN', "'Area Code' column not found")
        return

    area_codes = pd.to_numeric(df['Area Code'], errors='coerce')
    countries = (area_codes < 1000).sum()
    aggregates = (area_codes >= 1000).sum()

    if countries > 0 and aggregates > 0:
        result.add(
            'AREA_TYPES',
            'PASS',
            f"Country rows: {countries:,} | "
            f"Aggregate rows: {aggregates:,}. "
            f"Filter area_code >= 1000 in dbt staging to prevent double-counting."
        )
    elif aggregates == 0:
        result.add(
            'AREA_TYPES',
            'WARN',
            f"No regional aggregates found ({countries:,} country rows only). "
            f"This is acceptable if you filtered during download."
        )
    else:
        result.add(
            'AREA_TYPES',
            'FAIL',
            f"No individual country data found. Re-download with 'All Countries' selected."
        )


def compute_file_hash(path: Path) -> str:
    """
    Compute MD5 hash untuk file integrity verification.
    Hash ini dicatat untuk memastikan file tidak berubah antara
    validasi dan upload.
    """
    hasher = hashlib.md5()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(8192), b''):
            hasher.update(chunk)
    return hasher.hexdigest()


# =============================================================================
# MAIN VALIDATION RUNNER
# =============================================================================

def validate_dataset(name: str, cfg: dict) -> ValidationResult:
    """Run all validation checks for one dataset."""
    result = ValidationResult(name)
    path   = cfg['path']

    logger.info(f"\n{'='*60}")
    logger.info(f"VALIDATING: {name.upper()}")
    logger.info(f"File: {path}")
    logger.info(f"{'='*60}")

    # Check 1: File exists
    if not check_file_exists(path, result):
        logger.warning(f"  ⛔ Skipping remaining checks — file not found")
        return result

    # File hash for audit
    md5 = compute_file_hash(path)
    logger.info(f"  MD5 Hash: {md5}")

    # Check 2: Encoding
    encoding, df_sample = check_encoding(path, result)
    if encoding is None:
        return result

    # Load full dataset
    df = load_full_dataset(path, encoding)
    if df.empty:
        result.add('LOAD', 'FAIL', "Failed to load dataset")
        return result

    # Check 3: Columns
    check_columns(df, cfg['expected_columns'], result)

    # Check 4: Row count
    check_row_count(df, cfg['min_rows'], result)

    # Check 5: PK uniqueness
    check_primary_key_uniqueness(df, result)

    # Check 6: Year range
    check_year_range(df, cfg['year_min'], cfg['year_max'], result)

    # Check 7: Elements
    check_elements_present(df, cfg['expected_elements'], result)

    # Check 8: Negative values
    check_negative_values(df, cfg['max_negative_pct'], result)

    # Check 9: Flag distribution
    check_flag_distribution(df, result)

    # Check 10: Area types
    check_area_code_types(df, result)

    # Log results
    logger.info(f"\n  Validation Results for {name.upper()}:")
    for check in result.checks:
        icon = {'PASS': '', 'FAIL': '', 'WARN': ''}.get(check['status'], '?')
        logger.info(f"  {icon} [{check['status']:<4}] {check['check']}: {check['detail']}")

    return result


def main():
    logger.info("=" * 60)
    logger.info("FAOSTAT CSV VALIDATION REPORT")
    logger.info(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    logger.info("=" * 60)

    all_results = {}
    for name, cfg in CONFIG.items():
        result = validate_dataset(name, cfg)
        all_results[name] = result

    # Final summary
    logger.info(f"\n{'='*60}")
    logger.info("VALIDATION SUMMARY")
    logger.info(f"{'='*60}")

    all_valid = True
    for name, result in all_results.items():
        icon = ' READY' if result.is_valid else ' ISSUES FOUND'
        logger.info(f"  {icon} — {result.summary()}")
        if not result.is_valid:
            all_valid = False

    if all_valid:
        logger.info(
            "\n ALL DATASETS PASSED VALIDATION\n"
            "   Safe to proceed with BigQuery upload."
        )
    else:
        logger.error(
            "\n❌ VALIDATION FAILED\n"
            "   Fix issues above before uploading to BigQuery."
        )
        sys.exit(1)

    logger.info(f"\nValidation report saved: {log_file}")


if __name__ == '__main__':
    main()