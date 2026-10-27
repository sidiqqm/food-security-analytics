"""
Statistical Helper Functions

Reusable statistical functions dengan dokumentasi konteks bisnis.
"""

import warnings
from typing import Dict, Optional, Tuple

import numpy as np
import pandas as pd
from scipy import stats

warnings.filterwarnings('ignore')


# DESCRIPTIVE STATISTICS

def descriptive_stats(
    series: pd.Series,
    label: str = "Variable"
) -> pd.DataFrame:
    """
    Generate comprehensive descriptive statistics.

    Returns DataFrame dengan metrics yang relevan untuk analisis bisnis:
    - Central tendency (mean, median)
    - Dispersion (std, IQR, CV)
    - Shape (skewness, kurtosis)
    - Range (min, max, percentiles)

    Note pada Coefficient of Variation (CV):
    CV = std / mean. Mengukur variabilitas relatif.
    CV > 1.0 = sangat variabel (umum untuk data produksi yang didominasi
    beberapa negara besar).
    """

    clean = series.dropna()
    q1, q3 = clean.quantile([0.25, 0.75])
    iqr = q3 - q1

    return pd.DataFrame({
        'Metric': [
            'Count (non-null)',
            'Missing (%)',
            'Mean',
            'Median',
            'Mode (approx)',
            'Std Dev',
            'IQR',
            'Coeff of Variation (CV)',
            'Min',
            'P5',
            'P25',
            'P75',
            'P95',
            'Max',
            'Skewness',
            'Kurtosis (excess)',
        ],
        'Value': [
            len(clean),
            round(series.isna().mean() * 100, 2),
            round(clean.mean(), 2),
            round(clean.median(), 2),
            round(
                clean.mode().iloc[0]
                if len(clean.mode()) > 0
                else np.nan,
                2
            ),
            round(clean.std(), 2),
            round(iqr, 2),
            round(clean.std() / clean.mean(), 4)
            if clean.mean() != 0
            else np.nan,
            round(clean.min(), 2),
            round(clean.quantile(0.05), 2),
            round(q1, 2),
            round(q3, 2),
            round(clean.quantile(0.95), 2),
            round(clean.max(), 2),
            round(stats.skew(clean), 4),
            round(stats.kurtosis(clean), 4),
        ],
        'Interpretation': [
            f"Sample size: {len(clean):,}",
            "% of values that are missing",
            "Arithmetic average",
            "Middle value — robust to outliers",
            "Most frequent value (bin-based)",
            "Average deviation from mean",
            f"Middle 50% range: [{round(q1, 1)} – {round(q3, 1)}]",
            "std/mean: >1.0 = highly variable",
            "Smallest non-null value",
            "5th percentile",
            "1st quartile",
            "3rd quartile",
            "95th percentile",
            "Largest non-null value",
            ">0 = right-skewed (long right tail)",
            ">0 = heavy tails (leptokurtic)",
        ]
    }).assign(Variable=label)


def detect_outliers_iqr(
    series: pd.Series,
    multiplier: float = 1.5
) -> Tuple[pd.Series, dict]:
    """
    Detect outliers using IQR method.

    Kapan digunakan:
    - Data tidak harus normal
    - Robust terhadap extreme values yang sudah ada
    - Cocok untuk data produksi yang right-skewed seperti FAOSTAT

    Mengapa IQR vs Z-score:
    - Z-score sensitif terhadap outliers itu sendiri (masalah circular)
    - IQR menggunakan quartiles yang robust terhadap extreme values
    - Untuk data FAOSTAT yang highly skewed, IQR jauh lebih tepat

    Args:
        multiplier: 1.5 = mild outlier; 3.0 = extreme outlier (Tukey convention)

    Returns:
        (outlier_mask, stats_dict)
    """

    clean = series.dropna()
    q1 = clean.quantile(0.25)
    q3 = clean.quantile(0.75)
    iqr = q3 - q1

    lower_bound = q1 - multiplier * iqr
    upper_bound = q3 + multiplier * iqr

    outlier_mask = (series < lower_bound) | (series > upper_bound)

    return outlier_mask, {
        'q1': round(q1, 2),
        'q3': round(q3, 2),
        'iqr': round(iqr, 2),
        'lower_bound': round(lower_bound, 2),
        'upper_bound': round(upper_bound, 2),
        'n_outliers': outlier_mask.sum(),
        'pct_outliers': round(outlier_mask.mean() * 100, 2),
    }


# CORRELATION ANALYSIS

def correlation_analysis(
    x: pd.Series,
    y: pd.Series,
    label_x: str = "X",
    label_y: str = "Y"
) -> dict:
    """
    Compute both Pearson and Spearman correlation with business interpretation.

    Pearson vs Spearman — Kapan menggunakan yang mana:

    Pearson (r):
    - Mengukur LINEAR relationship antara dua variabel kontinyu
    - Asumsi: keduanya approximately normal, no significant outliers
    - Interpretasi: arah dan kekuatan hubungan linear
    - Untuk FAOSTAT: TIDAK ideal untuk perbandingan antar negara
      karena distribusi produksi sangat right-skewed

    Spearman (ρ):
    - Mengukur MONOTONIC relationship (tidak harus linear)
    - Non-parametric: tidak asumsi distribusi normal
    - Lebih robust terhadap outliers
    - Untuk FAOSTAT: LEBIH tepat untuk analisis antar negara
      di mana beberapa negara (China, India, USA) sangat dominan
    """

    # Remove pairs where either value is NaN
    df_clean = pd.DataFrame({'x': x, 'y': y}).dropna()
    n = len(df_clean)

    if n < 3:
        return {'error': 'Insufficient data for correlation'}

    # Pearson
    r_pearson, p_pearson = stats.pearsonr(
        df_clean['x'],
        df_clean['y']
    )

    # Spearman
    r_spearman, p_spearman = stats.spearmanr(
        df_clean['x'],
        df_clean['y']
    )

    def interpret_r(r: float) -> str:
        abs_r = abs(r)
        direction = "positive" if r > 0 else "negative"

        if abs_r >= 0.90:
            strength = "very strong"
        elif abs_r >= 0.70:
            strength = "strong"
        elif abs_r >= 0.50:
            strength = "moderate"
        elif abs_r >= 0.30:
            strength = "weak"
        else:
            strength = "very weak / negligible"

        return f"{strength} {direction} correlation"

    def interpret_p(
        p: float,
        alpha: float = 0.05
    ) -> str:
        if p < 0.001:
            return "highly significant (p < 0.001)"
        elif p < 0.01:
            return "very significant (p < 0.01)"
        elif p < 0.05:
            return "significant (p < 0.05)"
        elif p < 0.10:
            return "marginally significant (p < 0.10)"
        else:
            return f"NOT significant (p = {p:.3f})"

    return {
        'n_observations': n,
        'variables': f"{label_x} vs {label_y}",

        # Pearson
        'pearson_r': round(r_pearson, 4),
        'pearson_r_squared': round(r_pearson ** 2, 4),
        'pearson_p_value': round(p_pearson, 6),
        'pearson_significant': p_pearson < 0.05,
        'pearson_interpret': interpret_r(r_pearson),
        'pearson_p_interpret': interpret_p(p_pearson),

        # Spearman
        'spearman_rho': round(r_spearman, 4),
        'spearman_p_value': round(p_spearman, 6),
        'spearman_significant': p_spearman < 0.05,
        'spearman_interpret': interpret_r(r_spearman),
        'spearman_p_interpret': interpret_p(p_spearman),

        # Agreement
        'pearson_spearman_agree': (
            (r_pearson > 0) == (r_spearman > 0)
            and abs(r_pearson - r_spearman) < 0.2
        ),
    }


# CONFIDENCE INTERVALS

def confidence_interval_mean(
    series: pd.Series,
    confidence: float = 0.95
) -> dict:
    """
    Compute confidence interval for population mean.

    Kapan digunakan:
    - Kita ingin mengestimasi rata-rata populasi dari sample
    - Memberikan range dimana rata-rata "sebenarnya" kemungkinan besar berada
    - Lebih informatif daripada point estimate saja

    Asumsi:
    - Untuk n >= 30 (Central Limit Theorem), distribusi sampling mean
      akan mendekati normal meskipun data asli tidak normal
    - Data FAOSTAT dengan 150+ negara umumnya memenuhi syarat ini

    Interpretasi:
    - 95% CI: Jika kita mengambil 100 sample berbeda, 95 dari interval
      yang dihasilkan akan berisi rata-rata populasi yang sebenarnya
    """

    clean = series.dropna()
    n = len(clean)
    mean = clean.mean()
    se = stats.sem(clean)
    alpha = 1 - confidence

    # t-distribution (lebih konservatif daripada z untuk sample kecil)
    t_crit = stats.t.ppf(
        1 - alpha / 2,
        df=n - 1
    )
    margin = t_crit * se

    return {
        'n': n,
        'mean': round(mean, 4),
        'std_error': round(se, 4),
        'confidence': f"{confidence * 100:.0f}%",
        'lower_ci': round(mean - margin, 4),
        'upper_ci': round(mean + margin, 4),
        'margin_error': round(margin, 4),
        't_critical': round(t_crit, 4),
        'interpretation': (
            f"We are {confidence * 100:.0f}% confident the true population mean "
            f"lies between {round(mean - margin, 2)} and "
            f"{round(mean + margin, 2)}."
        )
    }


# HYPOTHESIS TESTING

def independent_ttest(
    group1: pd.Series,
    group2: pd.Series,
    label1: str = "Group 1",
    label2: str = "Group 2",
    alpha: float = 0.05
) -> dict:
    """
    Independent samples T-Test dengan Levene's test untuk equal variance.

    Kapan digunakan:
    - Membandingkan rata-rata DUA kelompok independen
    - Contoh: membandingkan rata-rata produksi periode 1991-2005 vs 2006-2022
    - Contoh: membandingkan DES negara High Income vs Low Income

    Asumsi:
    1. Kedua kelompok independen (tidak berpasangan)
    2. Data approximately normal (atau n > 30 per Central Limit Theorem)
    3. Equal variance (diuji dengan Levene's test)

    Jika equal variance violated → gunakan Welch's T-Test (equal_var=False)
    yang otomatis dilakukan oleh fungsi ini.

    Hipotesis:
    H0: μ1 = μ2 (rata-rata kedua kelompok sama)
    H1: μ1 ≠ μ2 (rata-rata berbeda — two-tailed)
    """

    g1 = group1.dropna()
    g2 = group2.dropna()

    # Levene's test untuk equal variance
    levene_stat, levene_p = stats.levene(g1, g2)
    equal_var = levene_p > 0.05

    # T-test (Welch's jika variance tidak equal)
    t_stat, p_value = stats.ttest_ind(
        g1,
        g2,
        equal_var=equal_var
    )

    # Cohen's d — Effect Size
    pooled_std = np.sqrt(
        (
            (len(g1) - 1) * g1.std()**2
            + (len(g2) - 1) * g2.std()**2
        )
        / (len(g1) + len(g2) - 2)
    )

    cohens_d = (
        (g1.mean() - g2.mean()) / pooled_std
        if pooled_std > 0
        else 0
    )

    def interpret_d(d: float) -> str:
        """Cohen's d interpretation (Cohen 1988)."""

        abs_d = abs(d)

        if abs_d < 0.20:
            return "negligible effect"
        elif abs_d < 0.50:
            return "small effect"
        elif abs_d < 0.80:
            return "medium effect"
        else:
            return "large effect"

    return {
        # Groups
        'group1_label': label1,
        'group2_label': label2,
        'n1': len(g1),
        'n2': len(g2),
        'mean1': round(g1.mean(), 4),
        'mean2': round(g2.mean(), 4),
        'mean_difference': round(g1.mean() - g2.mean(), 4),
        'std1': round(g1.std(), 4),
        'std2': round(g2.std(), 4),

        # Variance test
        'levene_stat': round(levene_stat, 4),
        'levene_p': round(levene_p, 4),
        'equal_variance': equal_var,
        'test_type': (
            "Student's T-Test"
            if equal_var
            else "Welch's T-Test"
        ),

        # T-test results
        't_statistic': round(t_stat, 4),
        'p_value': round(p_value, 6),
        'alpha': alpha,
        'reject_h0': p_value < alpha,
        'significant': p_value < alpha,

        # Effect size
        'cohens_d': round(cohens_d, 4),
        'effect_size': interpret_d(cohens_d),

        # Interpretation
        'conclusion': (
            f"{'REJECT' if p_value < alpha else 'FAIL TO REJECT'} H0. "
            f"The difference between {label1} (mean={g1.mean():.2f}) and "
            f"{label2} (mean={g2.mean():.2f}) is "
            f"{'statistically significant' if p_value < alpha else 'NOT statistically significant'} "
            f"(p={p_value:.4f}, {'< ' if p_value < alpha else '>='} {alpha}). "
            f"Effect size: {interpret_d(cohens_d)} "
            f"(Cohen's d = {cohens_d:.3f})."
        )
    }


def one_way_anova(
    groups: Dict[str, pd.Series],
    alpha: float = 0.05
) -> dict:
    """
    One-Way ANOVA untuk membandingkan > 2 kelompok.

    Kapan digunakan:
    - Membandingkan rata-rata LEBIH DARI DUA kelompok sekaligus
    - Contoh: membandingkan DES rata-rata di 4 kelompok income (High, Upper-mid,
      Lower-mid, Low income)
    - Lebih tepat daripada multiple T-Tests karena menghindari
      inflasi Type I Error (family-wise error rate)

    Asumsi:
    1. Sampel independen
    2. Distribusi mendekati normal per kelompok (atau n besar)
    3. Homogeneity of variance (Levene's test)

    Limitasi untuk FAOSTAT:
    - Jumlah negara per kelompok sangat tidak sama (imbalanced design)
    - Ini menurunkan power ANOVA, tapi tidak membatalkan validitasnya
    - Post-hoc test (Tukey HSD) diperlukan jika ANOVA signifikan

    Hipotesis:
    H0: μ1 = μ2 = μ3 = μ4 (semua group means sama)
    H1: Minimal satu mean berbeda dari yang lain
    """

    clean_groups = {
        k: v.dropna()
        for k, v in groups.items()
    }

    group_arrays = [
        v.values
        for v in clean_groups.values()
    ]

    # ANOVA
    f_stat, p_value = stats.f_oneway(*group_arrays)

    # Levene's test
    levene_stat, levene_p = stats.levene(*group_arrays)

    # Eta-squared (effect size for ANOVA)
    # Formula: SS_between / SS_total
    all_values = np.concatenate(group_arrays)
    grand_mean = all_values.mean()

    ss_between = sum(
        len(g) * (g.mean() - grand_mean)**2
        for g in group_arrays
    )

    ss_total = sum(
        (all_values - grand_mean)**2
    )

    eta_squared = (
        ss_between / ss_total
        if ss_total > 0
        else 0
    )

    def interpret_eta(eta2: float) -> str:
        if eta2 < 0.01:
            return "negligible effect"
        elif eta2 < 0.06:
            return "small effect"
        elif eta2 < 0.14:
            return "medium effect"
        else:
            return "large effect"

    # Group summaries
    group_summaries = {}

    for name, g in clean_groups.items():
        group_summaries[name] = {
            'n': len(g),
            'mean': round(g.mean(), 2),
            'std': round(g.std(), 2),
            'median': round(g.median(), 2),
        }

    return {
        'group_summaries': group_summaries,
        'n_groups': len(groups),
        'total_n': sum(
            len(g)
            for g in clean_groups.values()
        ),

        # Variance homogeneity
        'levene_stat': round(levene_stat, 4),
        'levene_p': round(levene_p, 4),
        'homogeneous_var': levene_p > 0.05,

        # ANOVA results
        'f_statistic': round(f_stat, 4),
        'p_value': round(p_value, 6),
        'alpha': alpha,
        'reject_h0': p_value < alpha,
        'significant': p_value < alpha,

        # Effect size
        'eta_squared': round(eta_squared, 4),
        'effect_size': interpret_eta(eta_squared),

        'conclusion': (
            f"{'REJECT' if p_value < alpha else 'FAIL TO REJECT'} H0 "
            f"(F={f_stat:.3f}, p={p_value:.4f}). "
            f"{'At least one group mean significantly differs.' if p_value < alpha else 'No significant difference between group means.'} "
            f"Effect size: {interpret_eta(eta_squared)} "
            f"(η² = {eta_squared:.4f})."
        )
    }


def chi_square_test(
    contingency_table: pd.DataFrame,
    alpha: float = 0.05
) -> dict:
    """
    Chi-Square Test of Independence untuk variabel kategorikal.

    Kapan digunakan:
    - Menguji apakah dua variabel KATEGORIKAL independen satu sama lain
    - Contoh: Apakah income_group INDEPENDEN dari des_category?
      (Apakah negara Low Income cenderung punya DES Inadequate?)
    - Contoh: Apakah status net_exporter berkaitan dengan development_status?

    Asumsi:
    1. Observasi independen
    2. Expected frequency ≥ 5 untuk setiap cell
       (jika violated, gunakan Fisher's exact atau gabung categories)
    3. Data bersifat nominal atau ordinal yang diperlakukan sebagai nominal

    Hipotesis:
    H0: Kedua variabel independen (tidak ada asosiasi)
    H1: Kedua variabel tidak independen (ada asosiasi)

    Effect Size: Cramer's V
    - 0.10 = small
    - 0.30 = medium
    - 0.50 = large
    """

    chi2_stat, p_value, dof, expected = stats.chi2_contingency(
        contingency_table
    )

    # Check expected frequency assumption
    min_expected = expected.min()
    cells_below_5 = (expected < 5).sum()
    total_cells = expected.size
    assumption_met = min_expected >= 5

    # Cramer's V (normalized chi-square effect size)
    n = contingency_table.values.sum()
    k = min(contingency_table.shape) - 1

    cramers_v = (
        np.sqrt(chi2_stat / (n * k))
        if (n * k) > 0
        else 0
    )

    def interpret_v(v: float) -> str:
        if v < 0.10:
            return "negligible association"
        elif v < 0.30:
            return "small association"
        elif v < 0.50:
            return "medium association"
        else:
            return "large association"

    return {
        'chi2_statistic': round(chi2_stat, 4),
        'degrees_of_freedom': dof,
        'p_value': round(p_value, 6),
        'alpha': alpha,
        'reject_h0': p_value < alpha,
        'significant': p_value < alpha,
        'n_total': int(n),

        # Assumption check
        'min_expected_freq': round(min_expected, 2),
        'cells_below_5': int(cells_below_5),
        'total_cells': int(total_cells),
        'assumption_met': assumption_met,
        'assumption_note': (
            "Expected frequency assumption met (all cells ≥ 5)"
            if assumption_met
            else
            f"{cells_below_5}/{total_cells} cells have expected freq < 5. "
            "Consider combining categories."
        ),

        # Effect size
        'cramers_v': round(cramers_v, 4),
        'effect_size': interpret_v(cramers_v),

        'conclusion': (
            f"{'REJECT' if p_value < alpha else 'FAIL TO REJECT'} H0 "
            f"(χ²={chi2_stat:.3f}, df={dof}, p={p_value:.4f}). "
            f"{'Significant association exists between variables.' if p_value < alpha else 'No significant association between variables.'} "
            f"Association strength: {interpret_v(cramers_v)} "
            f"(Cramer's V = {cramers_v:.4f})."
        )
    }