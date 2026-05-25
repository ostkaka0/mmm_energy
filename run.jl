#!/usr/bin/env julia

import HiGHS
using Printf

include("data.jl")
include("model.jl")

const RESULT_DIR = "results"
const PLOT_DIR = "plots"
const BASELINE_EMISSIONS_FILE = joinpath(RESULT_DIR, "baseline_emissions.txt")
const ALL_OUTPUT_TECHS = [:Wind, :PV, :Gas, :Hydro, :Battery, :Nuclear]

################################################################################
# CLI
################################################################################

struct CliOptions
    data_path::String
    exercises::Vector{Int}
end

function usage()
    return """
    Usage:
      julia --project=. run.jl [--data TimeSeries.csv] [--exercise N ...]

    Options:
      --data PATH, -d PATH       Path to the Canvas time-series CSV.
      --exercise N, -e N         Run exercise 1, 2, 3, or 4. Can be repeated.
                                 Comma-separated lists also work, e.g. -e 1,3.
      --help, -h                 Show this help text.

    If no --exercise flag is given, all exercises are run.
    The optimization solver is HiGHS.
    """
end

function parse_exercise_list(value::String)
    exercises = Int[]
    for item in split(value, ',')
        isempty(strip(item)) && continue
        ex = parse(Int, strip(item))
        1 <= ex <= 4 || error("Exercise must be between 1 and 4, got $(ex)")
        push!(exercises, ex)
    end
    return exercises
end

function parse_cli(args)
    data_path = "TimeSeries.csv"
    exercises = Int[]
    i = 1

    while i <= length(args)
        arg = args[i]
        if arg in ["--help", "-h"]
            println(usage())
            exit(0)
        elseif arg in ["--data", "-d"]
            i == length(args) && error("$(arg) requires a path")
            data_path = args[i + 1]
            i += 2
        elseif startswith(arg, "--data=")
            data_path = split(arg, "=", limit = 2)[2]
            i += 1
        elseif arg in ["--exercise", "-e"]
            i == length(args) && error("$(arg) requires an exercise number")
            append!(exercises, parse_exercise_list(args[i + 1]))
            i += 2
        elseif startswith(arg, "--exercise=")
            append!(exercises, parse_exercise_list(split(arg, "=", limit = 2)[2]))
            i += 1
        else
            error("Unknown argument $(arg)\n$(usage())")
        end
    end

    isempty(exercises) && append!(exercises, 1:4)
    return CliOptions(data_path, sort(unique(exercises)))
end

################################################################################
# Exercise execution
################################################################################

struct ScenarioRun
    scenario::Scenario
    result::Union{ScenarioResult, Nothing}
    status::String
    message::String
end

mutable struct RunContext
    data::TimeSeriesData
    optimizer
    cache::Dict{String, ScenarioRun}
end

function scenario_run(ctx::RunContext, scenario::Scenario)
    if haskey(ctx.cache, scenario.name)
        return ctx.cache[scenario.name]
    end

    println("Solving $(scenario.name)...")
    flush(stdout)
    run = try
        result = solve_scenario(ctx.data, scenario, ctx.optimizer)
        println("Solved $(scenario.name).")
        flush(stdout)
        ScenarioRun(scenario, result, "OPTIMAL", "")
    catch err
        println("Failed $(scenario.name): $(sprint(showerror, err))")
        flush(stdout)
        ScenarioRun(scenario, nothing, "FAILED", sprint(showerror, err))
    end
    ctx.cache[scenario.name] = run
    return run
end

function require_result(run::ScenarioRun, purpose::String)
    run.result !== nothing && return run.result
    error("Cannot $(purpose) because $(run.scenario.name) did not solve: $(run.message)")
end

function exercise1(ctx::RunContext)
    return [scenario_run(ctx, Scenario("ex1_no_cap_no_storage_no_trade", false, false, false, nothing))]
end

function baseline_emissions_ton(ctx::RunContext)
    baseline_name = "ex1_no_cap_no_storage_no_trade"
    if haskey(ctx.cache, baseline_name)
        return require_result(ctx.cache[baseline_name], "compute the 90% CO2 reduction cap").total_emissions_ton
    end

    if isfile(BASELINE_EMISSIONS_FILE)
        return parse(Float64, strip(read(BASELINE_EMISSIONS_FILE, String)))
    end

    error(
        "Cannot compute the 90% CO2 reduction cap because Exercise 1 has not " *
        "been solved in this run and $(BASELINE_EMISSIONS_FILE) does not exist. " *
        "Run `julia --project=. run.jl --exercise 1` first, or request Exercise 1 " *
        "together with this exercise."
    )
end

function co2_cap_for_90pct_reduction(ctx::RunContext)
    return 0.10 * baseline_emissions_ton(ctx)
end

function exercise2(ctx::RunContext)
    cap = co2_cap_for_90pct_reduction(ctx)
    return [
        # TODO: Revisit this scenario with course supervision if it remains
        # infeasible. The strict 90% cap may be too tight before batteries or
        # transmission are available.
        scenario_run(ctx, Scenario("ex2a_90pct_co2_cap", false, false, false, cap)),
        scenario_run(ctx, Scenario("ex2b_90pct_co2_cap_batteries", true, false, false, cap)),
    ]
end

function exercise3(ctx::RunContext)
    cap = co2_cap_for_90pct_reduction(ctx)
    return [
        scenario_run(ctx, Scenario("ex3_90pct_co2_cap_batteries_transmission", true, true, false, cap)),
    ]
end

function exercise4(ctx::RunContext)
    cap = co2_cap_for_90pct_reduction(ctx)
    return [
        scenario_run(ctx, Scenario("ex4_90pct_co2_cap_batteries_transmission_nuclear", true, true, true, cap)),
    ]
end

function run_requested_exercises(ctx::RunContext, exercises::Vector{Int})
    ordered = ScenarioRun[]
    seen = Set{String}()

    for exercise in exercises
        runs =
            exercise == 1 ? exercise1(ctx) :
            exercise == 2 ? exercise2(ctx) :
            exercise == 3 ? exercise3(ctx) :
            exercise == 4 ? exercise4(ctx) :
            error("Unsupported exercise $(exercise)")

        for run in runs
            if !(run.scenario.name in seen)
                push!(ordered, run)
                push!(seen, run.scenario.name)
            end
        end
    end

    return ordered
end

################################################################################
# Result tables
################################################################################

fmt_eur_billion(x) = @sprintf("%.2f", x / 1e9)
fmt_mton(x) = @sprintf("%.2f", x / 1e6)
value_or_zero(dict, key) = get(dict, key, 0.0)
successful_runs(runs) = [run for run in runs if run.result !== nothing]

function write_csv(path, header, rows)
    open(path, "w") do io
        println(io, join(header, ","))
        for row in rows
            println(io, join(row, ","))
        end
    end
end

function capacity_value(result::ScenarioResult, country::Country, tech::Technology)
    tech == :Battery && return result.battery_capacity_mw[country]
    return value_or_zero(result.capacity_mw, (country, tech))
end

function production_value(result::ScenarioResult, country::Country, tech::Technology)
    tech == :Battery && return result.total_battery_discharge_mwh[country]
    return value_or_zero(result.total_production_mwh, (country, tech))
end

function write_result_tables(data::TimeSeriesData, runs::Vector{ScenarioRun})
    mkpath(RESULT_DIR)

    for run in successful_runs(runs)
        if run.scenario.name == "ex1_no_cap_no_storage_no_trade"
            write(BASELINE_EMISSIONS_FILE, string(run.result.total_emissions_ton))
        end
    end

    summary_rows = Any[]
    for run in runs
        if run.result === nothing
            push!(summary_rows, [run.scenario.name, run.status, "", "", "", "", run.message])
        else
            r = run.result
            # total_cost_eur is conceptually EUR/year because investment costs are annualized.
            push!(summary_rows, [r.scenario.name, run.status, r.total_cost_eur,
                                 r.total_cost_eur / 1e9, r.total_emissions_ton,
                                 r.total_emissions_ton / 1e6, ""])
        end
    end
    write_csv(
        joinpath(RESULT_DIR, "summary.csv"),
        ["scenario", "status", "total_cost_EUR_per_year",
         "total_cost_billion_EUR_per_year", "co2_ton_per_year",
         "co2_Mton_per_year", "message"],
        summary_rows,
    )

    capacity_rows = Any[]
    production_rows = Any[]
    for run in successful_runs(runs)
        r = run.result
        for c in COUNTRIES, tech in ALL_OUTPUT_TECHS
            push!(capacity_rows, [r.scenario.name, c, tech, capacity_value(r, c, tech)])
            push!(production_rows, [r.scenario.name, c, tech, production_value(r, c, tech)])
        end
    end
    write_csv(joinpath(RESULT_DIR, "installed_capacity.csv"),
              ["scenario", "country", "technology", "capacity_MW"], capacity_rows)
    write_csv(joinpath(RESULT_DIR, "annual_production.csv"),
              ["scenario", "country", "technology", "production_MWh"], production_rows)

    cf_rows = Any[]
    for c in COUNTRIES, tech in VARIABLE_RENEWABLES
        push!(cf_rows, [c, tech, sum(data.capacity_factor[(c, tech)]) / length(data.time)])
    end
    write_csv(joinpath(RESULT_DIR, "average_capacity_factors.csv"),
              ["country", "technology", "average_capacity_factor"], cf_rows)

    hourly_rows = Any[]
    for run in successful_runs(runs)
        r = run.result
        for (i, hour) in enumerate(data.time)
            147 <= hour <= 651 || continue
            row = Any[r.scenario.name, hour, data.load[:DE][i]]
            for tech in [:Wind, :PV, :Gas, :Hydro, :Nuclear]
                push!(row, haskey(r.hourly_generation_mwh, (:DE, tech)) ?
                          r.hourly_generation_mwh[(:DE, tech)][i] : 0.0)
            end
            push!(row, r.hourly_battery_discharge_mwh[:DE][i])
            push!(row, r.hourly_battery_charge_mwh[:DE][i])
            push!(hourly_rows, row)
        end
    end
    write_csv(
        joinpath(RESULT_DIR, "germany_hours_147_651.csv"),
        ["scenario", "hour", "Load", "Wind", "PV", "Gas", "Hydro", "Nuclear",
         "Battery_discharge", "Battery_charge"],
        hourly_rows,
    )

    transmission_rows = Any[]
    for run in successful_runs(runs)
        r = run.result
        for from in COUNTRIES, to in COUNTRIES
            from == to && continue
            # Transmission energy is measured on the sending side, before the 2% loss.
            push!(transmission_rows, [
                r.scenario.name,
                from,
                to,
                value_or_zero(r.transmission_capacity_mw, (from, to)),
                value_or_zero(r.total_transmitted_energy_sent_mwh, (from, to)),
            ])
        end
    end
    write_csv(
        joinpath(RESULT_DIR, "transmission.csv"),
        ["scenario", "from", "to", "capacity_MW", "sent_energy_MWh"],
        transmission_rows,
    )
end

################################################################################
# Plot data
################################################################################

plot_file(slug, task, ext) = joinpath(PLOT_DIR, "$(slug)_$(task).$(ext)")

function write_matrix_dat(path, result::ScenarioResult, metric)
    open(path, "w") do io
        println(io, "Country Wind PV Gas Hydro Battery Nuclear")
        for c in COUNTRIES
            values = [metric(result, c, tech) for tech in ALL_OUTPUT_TECHS]
            println(io, join([String(c); string.(values)], " "))
        end
    end
end

function write_germany_dat(path, data::TimeSeriesData, result::ScenarioResult)
    open(path, "w") do io
        println(io, "Hour Load Wind PV Gas Hydro Nuclear Battery_discharge")
        for (i, hour) in enumerate(data.time)
            147 <= hour <= 651 || continue
            vals = Any[
                hour,
                data.load[:DE][i],
                haskey(result.hourly_generation_mwh, (:DE, :Wind)) ? result.hourly_generation_mwh[(:DE, :Wind)][i] : 0.0,
                haskey(result.hourly_generation_mwh, (:DE, :PV)) ? result.hourly_generation_mwh[(:DE, :PV)][i] : 0.0,
                haskey(result.hourly_generation_mwh, (:DE, :Gas)) ? result.hourly_generation_mwh[(:DE, :Gas)][i] : 0.0,
                haskey(result.hourly_generation_mwh, (:DE, :Hydro)) ? result.hourly_generation_mwh[(:DE, :Hydro)][i] : 0.0,
                haskey(result.hourly_generation_mwh, (:DE, :Nuclear)) ? result.hourly_generation_mwh[(:DE, :Nuclear)][i] : 0.0,
                result.hourly_battery_discharge_mwh[:DE][i],
            ]
            println(io, join(vals, " "))
        end
    end
end

function write_transmission_dat(path, result::ScenarioResult)
    open(path, "w") do io
        println(io, "Line Capacity_MW Sent_energy_TWh")
        for (from, to) in [(:SE, :DK), (:DK, :SE), (:SE, :DE), (:DE, :SE), (:DK, :DE), (:DE, :DK)]
            label = "$(from)-$(to)"
            capacity = value_or_zero(result.transmission_capacity_mw, (from, to))
            energy = value_or_zero(result.total_transmitted_energy_sent_mwh, (from, to)) / 1e6
            println(io, "$(label) $(capacity) $(energy)")
        end
    end
end

function write_plot_data(data::TimeSeriesData, runs::Vector{ScenarioRun})
    mkpath(PLOT_DIR)

    for run in successful_runs(runs)
        r = run.result
        slug = r.scenario.name
        capacity_dat = plot_file(slug, "capacity", "dat")
        production_dat = plot_file(slug, "production", "dat")
        germany_dat = plot_file(slug, "germany_147_651", "dat")

        write_matrix_dat(capacity_dat, r, capacity_value)
        write_matrix_dat(production_dat, r, production_value)
        write_germany_dat(germany_dat, data, r)

        if r.scenario.allow_transmission
            transmission_dat = plot_file(slug, "transmission", "dat")
            write_transmission_dat(transmission_dat, r)
        end
    end
end

################################################################################
# Report
################################################################################

function result_map(runs::Vector{ScenarioRun})
    return Dict(run.scenario.name => run.result for run in runs if run.result !== nothing)
end

function run_map(runs::Vector{ScenarioRun})
    return Dict(run.scenario.name => run for run in runs)
end

function dominant_techs(result::ScenarioResult)
    rows = [(c, tech, capacity_value(result, c, tech)) for c in COUNTRIES for tech in ALL_OUTPUT_TECHS]
    sort!(rows, by = x -> x[3], rev = true)
    return filter(x -> x[3] > 1.0, rows[1:min(end, 8)])
end

function write_report(data::TimeSeriesData, runs::Vector{ScenarioRun})
    mkpath(RESULT_DIR)
    results = result_map(runs)
    runs_by_name = run_map(runs)
    report_path = joinpath(RESULT_DIR, "report.md")

    open(report_path, "w") do io
        println(io, "# Electricity System Modelling Results")
        println(io)
        println(io, "The model minimizes annualized investment cost plus variable operating and fuel costs for Sweden, Denmark, and Germany over 8760 hourly time steps.")
        println(io)

        println(io, "## Average Capacity Factors")
        for c in COUNTRIES
            @printf(io, "- %s: wind %.1f%%, PV %.1f%%\n",
                    COUNTRY_NAME[c],
                    100 * sum(data.capacity_factor[(c, :Wind)]) / length(data.time),
                    100 * sum(data.capacity_factor[(c, :PV)]) / length(data.time))
        end
        println(io)

        println(io, "## Scenario Summary")
        println(io, "| Scenario | Status | Cost (bn EUR/year) | CO2 (Mton/year) |")
        println(io, "|---|---|---:|---:|")
        for run in runs
            if run.result === nothing
                println(io, "| $(run.scenario.name) | $(run.status) |  |  |")
            else
                r = run.result
                println(io, "| $(r.scenario.name) | $(run.status) | $(fmt_eur_billion(r.total_cost_eur)) | $(fmt_mton(r.total_emissions_ton)) |")
            end
        end
        println(io)

        if haskey(results, "ex1_no_cap_no_storage_no_trade")
            ex1 = results["ex1_no_cap_no_storage_no_trade"]
            println(io, "## Exercise 1")
            println(io, "Without a CO2 cap, batteries, transmission, or nuclear power, the model chooses the cheapest combination of variable renewables, Swedish hydro, and gas backup that can meet every hourly load. Country differences come from local wind/PV capacity factors, renewable capacity limits, demand shape, and Sweden's existing hydro reservoir.")
            println(io)
            println(io, "Largest installed capacities:")
            for (c, tech, cap) in dominant_techs(ex1)
                @printf(io, "- %s %s: %.1f GW\n", c, tech, cap / 1000)
            end
            println(io)
        end

        if haskey(runs_by_name, "ex2a_90pct_co2_cap") || haskey(results, "ex2b_90pct_co2_cap_batteries")
            println(io, "## Exercise 2")
            if haskey(runs_by_name, "ex2a_90pct_co2_cap") && runs_by_name["ex2a_90pct_co2_cap"].result === nothing
                println(io, "Exercise 2a is infeasible for this data set with the strict 90% reduction cap, no batteries, and no transmission. This means the hourly renewable and hydro limits still force more gas generation than the cap permits.")
                println(io)
            end
            if haskey(results, "ex1_no_cap_no_storage_no_trade") && haskey(results, "ex2b_90pct_co2_cap_batteries")
                ex1 = results["ex1_no_cap_no_storage_no_trade"]
                ex2b = results["ex2b_90pct_co2_cap_batteries"]
                cap_reduction = 100 * (1 - ex2b.total_emissions_ton / ex1.total_emissions_ton)
                cost_change = 100 * (ex2b.total_cost_eur / ex1.total_cost_eur - 1)
                @printf(io, "With batteries, the capped system lowers emissions by %.1f%% relative to Exercise 1 and changes total cost by %.1f%%. Batteries are useful because they shift surplus wind/PV generation into hours with lower renewable output, reducing gas generation under the cap.\n", cap_reduction, cost_change)
                println(io)
            end
        end

        if haskey(results, "ex3_90pct_co2_cap_batteries_transmission")
            println(io, "## Exercise 3")
            ex3 = results["ex3_90pct_co2_cap_batteries_transmission"]
            if haskey(results, "ex2b_90pct_co2_cap_batteries")
                ex2b = results["ex2b_90pct_co2_cap_batteries"]
                trans_cost_change = 100 * (ex3.total_cost_eur / ex2b.total_cost_eur - 1)
                @printf(io, "Transmission changes total system cost by %.1f%% relative to Exercise 2b. It lets the model use weather and demand differences between countries, so imports can replace some local backup, storage, or renewable overcapacity where that is cheaper.\n", trans_cost_change)
            else
                println(io, "Transmission lets the model use weather and demand differences between countries, so imports can replace some local backup, storage, or renewable overcapacity where that is cheaper.")
            end
            println(io)
        end

        if haskey(results, "ex4_90pct_co2_cap_batteries_transmission_nuclear")
            println(io, "## Exercise 4")
            ex4 = results["ex4_90pct_co2_cap_batteries_transmission_nuclear"]
            nuclear_capacity = sum(capacity_value(ex4, c, :Nuclear) for c in COUNTRIES)
            if haskey(results, "ex3_90pct_co2_cap_batteries_transmission")
                ex3 = results["ex3_90pct_co2_cap_batteries_transmission"]
                nuclear_cost_change = 100 * (ex4.total_cost_eur / ex3.total_cost_eur - 1)
                @printf(io, "Adding nuclear changes total cost by %.1f%% relative to Exercise 3. The model builds %.1f GW of nuclear capacity.\n", nuclear_cost_change, nuclear_capacity / 1000)
            else
                @printf(io, "The model builds %.1f GW of nuclear capacity.\n", nuclear_capacity / 1000)
            end
            println(io, "Nuclear competes especially with gas backup, renewable overbuild, batteries, and imports because it provides dispatchable low-carbon generation. This result is sensitive to nuclear investment cost, lifetime, discount rate, fuel/running cost, CO2 cap stringency, renewable capacity factors, and renewable build limits.")
            println(io)
        end

        println(io, "## Generated Files")
        println(io, "- `results/summary.csv`: total costs, emissions, and infeasible scenario status.")
        println(io, "- `results/installed_capacity.csv`: capacity by country and technology.")
        println(io, "- `results/annual_production.csv`: annual production by country and technology.")
        println(io, "- `results/average_capacity_factors.csv`: average wind and PV capacity factors.")
        println(io, "- `results/germany_hours_147_651.csv`: Germany hourly load and domestic generation.")
        println(io, "- `results/transmission.csv`: directed transmission capacities and annual flows.")
        println(io, "- `plots/`: plot data files and PDF plots generated by `plot_results.py`.")
    end
end

################################################################################
# Program entry point
################################################################################

function main(args = ARGS)
    options = parse_cli(args)
    isfile(options.data_path) || error("Missing $(options.data_path). Put the Canvas TimeSeries.csv file in this directory or pass its path with --data.")

    data = read_timeseries(options.data_path)
    ctx = RunContext(data, HiGHS.Optimizer, Dict{String, ScenarioRun}())
    runs = run_requested_exercises(ctx, options.exercises)

    write_result_tables(data, runs)
    write_plot_data(data, runs)
    write_report(data, runs)

    println("Solver: highs")
    println("Result tables written to $(RESULT_DIR)/")
    println("Plot data written to $(PLOT_DIR)/")
    exercise_arg = join(options.exercises, ",")
    println("Run `python plot_results.py --exercise $(exercise_arg)` to render PDF plots.")
    println("Requested exercise outputs: $(exercise_arg)")
    for run in runs
        if run.result === nothing
            println(@sprintf("%-48s %-8s %s", run.scenario.name, run.status, run.message))
        else
            r = run.result
            println(@sprintf("%-48s cost %8s bn EUR/year  CO2 %8s Mton/year",
                             r.scenario.name, fmt_eur_billion(r.total_cost_eur),
                             fmt_mton(r.total_emissions_ton)))
        end
    end
end

main()
