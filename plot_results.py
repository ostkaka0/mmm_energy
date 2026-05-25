#!/usr/bin/env python

import argparse
import os
import sys
from pathlib import Path

os.environ.setdefault("MPLCONFIGDIR", "/tmp/matplotlib-energy")

import matplotlib

if not os.environ.get("DISPLAY"):
    matplotlib.use("Agg")

import matplotlib.pyplot as plt


ROOT = Path(__file__).resolve().parent
PLOT_DIR = ROOT / "plots"

COLORS = {
    "Wind": "#3b82f6",
    "PV": "#f59e0b",
    "Gas": "#6b7280",
    "Hydro": "#06b6d4",
    "Battery": "#10b981",
    "Battery_charge": "#047857",
    "Battery_discharge": "#10b981",
    "Imports": "#2563eb",
    "Exports": "#dc2626",
    "Nuclear": "#8b5cf6",
    "Load": "#111827",
}

TIMELINE_COMPONENTS = [
    "Wind",
    "PV",
    "Gas",
    "Hydro",
    "Battery_discharge",
    "Battery_charge",
    "Imports",
    "Exports",
    "Nuclear",
]
TIMELINE_CMAP = plt.get_cmap("tab20")

COUNTRY_LABELS = {
    "de": "Germany",
    "dk": "Denmark",
    "se": "Sweden",
}

SCENARIOS_BY_EXERCISE = {
    1: ["ex1_no_cap_no_storage_no_trade"],
    2: [
        "ex2a_90pct_co2_cap",
        "ex2b_90pct_co2_cap_batteries",
    ],
    3: ["ex3_90pct_co2_cap_batteries_transmission"],
    4: ["ex4_90pct_co2_cap_batteries_transmission_nuclear"],
}


def parse_exercise_list(values):
    if not values:
        return [1, 2, 3, 4]

    exercises = []
    for value in values:
        for item in value.split(","):
            if not item.strip():
                continue
            exercise = int(item)
            if exercise < 1 or exercise > 4:
                raise argparse.ArgumentTypeError("exercise must be between 1 and 4")
            exercises.append(exercise)
    return sorted(set(exercises))


def scenarios_for_exercises(exercises):
    scenarios = []
    seen = set()
    for exercise in exercises:
        for scenario in SCENARIOS_BY_EXERCISE[exercise]:
            if scenario not in seen:
                scenarios.append(scenario)
                seen.add(scenario)
    return scenarios


def parse_country(value):
    country = value.strip().lower()
    if country not in COUNTRY_LABELS:
        raise argparse.ArgumentTypeError("country must be one of: de, dk, se")
    return country


def timeline_color(name):
    if name == "Load":
        return "#6b7280"
    if name == "Net supply":
        return "#111827"
    if name in TIMELINE_COMPONENTS:
        return TIMELINE_CMAP(TIMELINE_COMPONENTS.index(name) * 2)
    return COLORS.get(name, "#111827")


def read_table(path):
    with open(path, "r", encoding="utf-8") as handle:
        header = handle.readline().strip().split()
        rows = [line.strip().split() for line in handle if line.strip()]
    return header, rows


def save_stacked(input_path, output_path, title, ylabel, show=False):
    header, rows = read_table(input_path)
    labels = [row[0] for row in rows]
    series = header[1:]

    fig, ax = plt.subplots(figsize=(9.5, 6.0))
    bottoms = [0.0] * len(labels)
    for i, name in enumerate(series):
        values = [float(row[i + 1]) for row in rows]
        ax.bar(labels, values, bottom=bottoms, label=name, color=COLORS.get(name))
        bottoms = [bottom + value for bottom, value in zip(bottoms, values)]

    ax.set_title(title)
    ax.set_ylabel(ylabel)
    ax.legend(loc="upper left", bbox_to_anchor=(1.01, 1.0))
    ax.grid(axis="y", alpha=0.25)
    fig.tight_layout()
    fig.savefig(output_path)
    if show:
        plt.show()
    plt.close(fig)


def save_country_timeline(input_path, output_path, title, ylabel, show=False):
    header, rows = read_table(input_path)
    columns = {
        name: [float(row[i]) for row in rows]
        for i, name in enumerate(header)
    }
    has_transmission = "_transmission_" in input_path.name
    if has_transmission and ("Imports" not in columns or "Exports" not in columns):
        raise ValueError(
            f"{input_path} is stale: transmission timeline data must include "
            "Imports and Exports. Regenerate plot data with run.jl before rendering."
        )
    zero = [0.0] * len(columns["Hour"])
    net_supply = [
        columns.get("Wind", zero)[i]
        + columns.get("PV", zero)[i]
        + columns.get("Gas", zero)[i]
        + columns.get("Hydro", zero)[i]
        + columns.get("Nuclear", zero)[i]
        + columns.get("Battery_discharge", zero)[i]
        + columns.get("Imports", zero)[i]
        - columns.get("Battery_charge", zero)[i]
        - columns.get("Exports", zero)[i]
        for i in range(len(columns["Hour"]))
    ]

    fig, ax = plt.subplots(figsize=(10.5, 6.0))
    ax.plot(
        columns["Hour"],
        columns["Load"],
        label="Load",
        linewidth=2.3,
        color=timeline_color("Load"),
    )
    ax.plot(
        columns["Hour"],
        net_supply,
        label="Net supply",
        linewidth=2.0,
        linestyle=":",
        color=timeline_color("Net supply"),
    )
    for name in header[1:]:
        if name == "Load":
            continue
        ax.plot(
            columns["Hour"],
            columns[name],
            label=name.replace("_", " "),
            linewidth=1.2,
            color=timeline_color(name),
        )

    ax.set_title(title)
    ax.set_xlabel("Hour")
    ax.set_ylabel(ylabel)
    ax.legend(loc="upper left", bbox_to_anchor=(1.01, 1.0))
    ax.grid(alpha=0.25)
    fig.tight_layout()
    fig.savefig(output_path)
    if show:
        plt.show()
    plt.close(fig)


def save_transmission(input_path, output_path, title, ylabel, show=False):
    _header, rows = read_table(input_path)
    labels = [row[0] for row in rows]
    capacity = [float(row[1]) for row in rows]
    energy = [float(row[2]) for row in rows]

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(9.5, 8.0), sharex=True)
    ax1.bar(labels, capacity, color="#3b82f6")
    ax1.set_title(title)
    ax1.set_ylabel(ylabel)
    ax1.grid(axis="y", alpha=0.25)

    ax2.bar(labels, energy, color="#ef4444")
    ax2.set_ylabel("MWh/year")
    ax2.grid(axis="y", alpha=0.25)
    ax2.tick_params(axis="x", rotation=35)

    fig.tight_layout()
    fig.savefig(output_path)
    if show:
        plt.show()
    plt.close(fig)


def render(kind, input_path, output_path, title, ylabel, show=False):
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if kind == "stacked":
        save_stacked(input_path, output_path, title, ylabel, show)
    elif kind == "country":
        save_country_timeline(input_path, output_path, title, ylabel, show)
    elif kind == "transmission":
        save_transmission(input_path, output_path, title, ylabel, show)
    else:
        raise ValueError(f"unknown plot kind: {kind}")


def scenario_has_data(scenario):
    return (PLOT_DIR / f"{scenario}_capacity.dat").exists()


def plot_scenario(scenario, country, show=False):
    if not scenario_has_data(scenario):
        print(f"Skipping {scenario}: no plot data found.", file=sys.stderr)
        return

    render(
        "stacked",
        PLOT_DIR / f"{scenario}_capacity.dat",
        PLOT_DIR / f"{scenario}_capacity.pdf",
        f"Installed capacity - {scenario}",
        "MW",
        show,
    )
    render(
        "stacked",
        PLOT_DIR / f"{scenario}_production.dat",
        PLOT_DIR / f"{scenario}_production.pdf",
        f"Annual production - {scenario}",
        "MWh/year",
        show,
    )
    timeline_data = PLOT_DIR / f"{scenario}_{country}_147_651.dat"
    if timeline_data.exists():
        render(
            "country",
            timeline_data,
            PLOT_DIR / f"{scenario}_{country}_147_651.pdf",
            f"{COUNTRY_LABELS[country]} generation and load, hours 147-651 - {scenario}",
            "MWh/h",
            show,
        )
    else:
        print(f"Skipping {scenario} {country}: no timeline plot data found.", file=sys.stderr)

    transmission_data = PLOT_DIR / f"{scenario}_transmission.dat"
    if transmission_data.exists():
        render(
            "transmission",
            transmission_data,
            PLOT_DIR / f"{scenario}_transmission.pdf",
            f"Transmission - {scenario}",
            "MW",
            show,
        )


def render_command(argv):
    parser = argparse.ArgumentParser(
        prog="plot_results.py render",
        description="Render one plot from one plot data file.",
    )
    parser.add_argument("kind", choices=["stacked", "country", "transmission"])
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("title")
    parser.add_argument("ylabel")
    parser.add_argument("--show", action="store_true")
    args = parser.parse_args(argv)
    render(args.kind, args.input, args.output, args.title, args.ylabel, args.show)


def exercise_command(argv):
    parser = argparse.ArgumentParser(
        description="Plot assignment exercise outputs.",
    )
    parser.add_argument(
        "--exercise",
        "-e",
        action="append",
        help="Exercise number 1-4. Can be repeated or comma-separated. Defaults to all.",
    )
    parser.add_argument("--show", action="store_true", help="Show plots interactively after saving PDF files.")
    parser.add_argument(
        "--country",
        default="de",
        type=parse_country,
        help="Country for the hourly load/generation plot. One of: de, dk, se. Default: de.",
    )
    args = parser.parse_args(argv)

    exercises = parse_exercise_list(args.exercise)

    for scenario in scenarios_for_exercises(exercises):
        print(f"Rendering plots for {scenario}", flush=True)
        plot_scenario(scenario, args.country, args.show)

    print(f"Plots written to {PLOT_DIR}")


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "render":
        render_command(sys.argv[2:])
    elif len(sys.argv) > 1 and sys.argv[1] in {"stacked", "country", "transmission"}:
        render_command(sys.argv[1:])
    else:
        exercise_command(sys.argv[1:])


if __name__ == "__main__":
    main()
