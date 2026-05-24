#!/usr/bin/env python

import argparse
import os
import subprocess
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
    "Nuclear": "#8b5cf6",
    "Load": "#111827",
}

SCENARIOS_BY_EXERCISE = {
    1: ["ex1_no_cap_no_storage_no_trade"],
    2: [
        "ex1_no_cap_no_storage_no_trade",
        "ex2a_90pct_co2_cap",
        "ex2b_90pct_co2_cap_batteries",
    ],
    3: [
        "ex1_no_cap_no_storage_no_trade",
        "ex2b_90pct_co2_cap_batteries",
        "ex3_90pct_co2_cap_batteries_transmission",
    ],
    4: [
        "ex1_no_cap_no_storage_no_trade",
        "ex2b_90pct_co2_cap_batteries",
        "ex3_90pct_co2_cap_batteries_transmission",
        "ex4_90pct_co2_cap_batteries_transmission_nuclear",
    ],
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


def save_germany(input_path, output_path, title, ylabel, show=False):
    header, rows = read_table(input_path)
    columns = {
        name: [float(row[i]) for row in rows]
        for i, name in enumerate(header)
    }

    fig, ax = plt.subplots(figsize=(10.5, 6.0))
    for name in header[1:]:
        width = 2.3 if name == "Load" else 1.2
        ax.plot(columns["Hour"], columns[name], label=name.replace("_", " "),
                linewidth=width, color=COLORS.get(name))

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
    ax2.set_ylabel("TWh/year")
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
    elif kind == "germany":
        save_germany(input_path, output_path, title, ylabel, show)
    elif kind == "transmission":
        save_transmission(input_path, output_path, title, ylabel, show)
    else:
        raise ValueError(f"unknown plot kind: {kind}")


def run_solver(exercises, data_path, solver):
    cmd = [
        "julia",
        "--project=.",
        str(ROOT / "run.jl"),
        "--data",
        data_path,
        "--solver",
        solver,
    ]
    for exercise in exercises:
        cmd.extend(["--exercise", str(exercise)])
    subprocess.run(cmd, cwd=ROOT, check=True)


def scenario_has_data(scenario):
    return (PLOT_DIR / f"{scenario}_capacity.dat").exists()


def plot_scenario(scenario, show=False):
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
    render(
        "germany",
        PLOT_DIR / f"{scenario}_germany_147_651.dat",
        PLOT_DIR / f"{scenario}_germany_147_651.pdf",
        f"Germany generation and load, hours 147-651 - {scenario}",
        "MWh/h",
        show,
    )

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
    parser.add_argument("kind", choices=["stacked", "germany", "transmission"])
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("title")
    parser.add_argument("ylabel")
    parser.add_argument("--show", action="store_true")
    args = parser.parse_args(argv)
    render(args.kind, args.input, args.output, args.title, args.ylabel, args.show)


def exercise_command(argv):
    parser = argparse.ArgumentParser(
        description="Plot assignment exercise outputs. Use --solve to run Julia first.",
    )
    parser.add_argument(
        "--exercise",
        "-e",
        action="append",
        help="Exercise number 1-4. Can be repeated or comma-separated. Defaults to all.",
    )
    parser.add_argument("--solve", action="store_true", help="Run Julia for the requested exercises before plotting.")
    parser.add_argument("--show", action="store_true", help="Show plots interactively after saving PDF files.")
    parser.add_argument("--data", "-d", default="TimeSeries.csv", help="CSV path passed to Julia when --solve is used.")
    parser.add_argument("--solver", "-s", default="clp", choices=["clp", "gurobi"], help="Solver passed to Julia when --solve is used.")
    args = parser.parse_args(argv)

    exercises = parse_exercise_list(args.exercise)
    if args.solve:
        run_solver(exercises, args.data, args.solver)

    for scenario in scenarios_for_exercises(exercises):
        print(f"Rendering plots for {scenario}", flush=True)
        plot_scenario(scenario, args.show)

    print(f"Plots written to {PLOT_DIR}")


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "render":
        render_command(sys.argv[2:])
    elif len(sys.argv) > 1 and sys.argv[1] in {"stacked", "germany", "transmission"}:
        # Backward-compatible internal form used by older run.jl versions.
        render_command(sys.argv[1:])
    else:
        exercise_command(sys.argv[1:])


if __name__ == "__main__":
    main()
