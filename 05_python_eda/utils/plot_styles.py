"""
Matplotlib Style Configuration

"""

import matplotlib as mpl
import matplotlib.pyplot as plt
import numpy as np


# COLOR PALETTE

COLORS = {
    'primary': '#1565C0',       # main series
    'secondary': '#2E7D32',     # comparison series
    'accent': '#E65100',        # highlight / alert
    'neutral': '#546E7A',       # supporting elements
    'light': '#90CAF9',         # fill / area
    'warning': '#F9A825',       # warning / caution
    'background': '#FAFAFA',    # chart background
    'grid': '#ECEFF1',          # grid lines
    'text': '#212121',          # text
}


# Commodity color mapping (consistent across all charts)

COMMODITY_COLORS = {
    'Wheat': '#1565C0',
    'Rice, paddy': '#2E7D32',
    'Maize (corn)': '#E65100',
    'Soybeans': '#6A1B9A',
    'Potatoes': '#F9A825',
    'Cassava': '#00838F',
    'Sugar cane': '#AD1457',
    'Palm oil': '#558B2F',
    'Barley': '#4E342E',
    'Pulses, Total': '#546E7A',
    'Sweet potatoes': '#37474F',
}


# FAO Region color mapping

REGION_COLORS = {
    'Africa': '#E65100',
    'Americas': '#1565C0',
    'Asia': '#2E7D32',
    'Europe': '#6A1B9A',
    'Oceania': '#F9A825',
    'Not Classified': '#90A4AE',
}


# Income group color mapping

INCOME_COLORS = {
    'High income': '#1565C0',
    'Upper middle income': '#2E7D32',
    'Lower middle income': '#F9A825',
    'Low income': '#E65100',
    'Not Classified': '#90A4AE',
}


def set_style():
    """Apply consistent matplotlib styling to all subsequent plots."""

    plt.rcParams.update({
        # Figure
        'figure.facecolor': COLORS['background'],
        'figure.dpi': 150,
        'figure.figsize': (12, 6),

        # Axes
        'axes.facecolor': 'white',
        'axes.edgecolor': '#CFD8DC',
        'axes.linewidth': 0.8,
        'axes.grid': True,
        'axes.axisbelow': True,
        'axes.labelcolor': COLORS['text'],
        'axes.titlesize': 13,
        'axes.titleweight': 'bold',
        'axes.titlepad': 12,
        'axes.labelsize': 11,
        'axes.spines.top': False,
        'axes.spines.right': False,

        # Grid
        'grid.color': COLORS['grid'],
        'grid.linewidth': 0.8,
        'grid.alpha': 0.8,

        # Text
        'text.color': COLORS['text'],
        'font.family': ['DejaVu Sans', 'Arial', 'sans-serif'],
        'font.size': 10,

        # Lines
        'lines.linewidth': 2.0,
        'lines.markersize': 5,

        # Legend
        'legend.framealpha': 0.9,
        'legend.edgecolor': '#CFD8DC',
        'legend.fontsize': 9,

        # Ticks
        'xtick.color': COLORS['neutral'],
        'ytick.color': COLORS['neutral'],
        'xtick.labelsize': 9,
        'ytick.labelsize': 9,
    })


def add_notable_events(ax, df_col_year, events_dict: dict):
    """
    Add vertical reference lines for notable events (2008, 2020, etc.)
    on a time-series chart.
    """

    for year, label in events_dict.items():
        ax.axvline(
            x=year,
            color=COLORS['accent'],
            linestyle='--',
            linewidth=1.0,
            alpha=0.6
        )

        ax.text(
            year + 0.2,
            ax.get_ylim()[1] * 0.95,
            label,
            rotation=90,
            fontsize=7,
            color=COLORS['accent'],
            verticalalignment='top',
            alpha=0.8
        )


def save_figure(
    fig,
    filename: str,
    output_dir: str = 'outputs/figures'
):
    """Save figure with consistent settings."""

    import os

    os.makedirs(output_dir, exist_ok=True)

    path = f"{output_dir}/{filename}.png"

    fig.savefig(
        path,
        dpi=300,
        bbox_inches='tight',
        facecolor=COLORS['background']
    )

    print(f"Saved: {path}")

    return path