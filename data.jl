const COUNTRIES = [:SE, :DK, :DE]
const COUNTRY_NAME = Dict(:SE => "Sweden", :DK => "Denmark", :DE => "Germany")

const Country = Symbol
const Technology = Symbol

################################################################################
# Static assignment data
################################################################################

const GENERATION_TECHS = [:Wind, :PV, :Gas, :Hydro, :Nuclear]
const DISPATCHABLE_TECHS = [:Gas, :Hydro, :Nuclear]
const VARIABLE_RENEWABLES = [:Wind, :PV]

# Unitless annual discount rate used for all technologies.
const DISCOUNT_RATE = 0.05
const HOURS_PER_YEAR = 8760

# Investment costs from the assignment, converted from EUR/kW to EUR/MW.
const investment_cost_eur_per_mw = Dict(
    :Wind => 1_100_000.0,
    :PV => 600_000.0,
    :Gas => 550_000.0,
    :Hydro => 0.0,
    :Battery => 150_000.0,
    :Transmission => 2_500_000.0,
    :Nuclear => 7_700_000.0,
)

# Running costs in EUR/MWh_electricity produced.
const running_cost_eur_per_mwh = Dict(
    :Wind => 0.1,
    :PV => 0.1,
    :Gas => 2.0,
    :Hydro => 0.1,
    :Battery => 0.1,
    :Transmission => 0.0,
    :Nuclear => 4.0,
)

# Fuel costs in EUR/MWh_fuel consumed.
const fuel_cost_eur_per_mwh_fuel = Dict(
    :Wind => 0.0,
    :PV => 0.0,
    :Gas => 22.0,
    :Hydro => 0.0,
    :Battery => 0.0,
    :Transmission => 0.0,
    :Nuclear => 3.2,
)

# Technical lifetime in years.
const lifetime_years = Dict(
    :Wind => 25.0,
    :PV => 25.0,
    :Gas => 30.0,
    :Hydro => 80.0,
    :Battery => 10.0,
    :Transmission => 50.0,
    :Nuclear => 50.0,
)

# Unitless efficiencies. Gas and nuclear are MWh_electricity/MWh_fuel.
# Battery is round-trip efficiency. Transmission is delivered/sent electricity.
const efficiency = Dict(
    :Gas => 0.4,
    :Battery => 0.9,
    :Transmission => 0.98,
    :Nuclear => 0.4,
)

# TODO: Replace with a single const
# Emissions in ton CO2/MWh_fuel consumed.
const emission_factor_ton_per_mwh_fuel = Dict(
    :Wind => 0.0,
    :PV => 0.0,
    :Gas => 0.202,
    :Hydro => 0.0,
    :Nuclear => 0.0,
)

# Maximum installable generation capacity in MW.
# TODO: Remove hydro from non-sweden maybe.
const max_capacity_mw = Dict(
    (:SE, :Wind) => 280_000.0,
    (:DK, :Wind) => 90_000.0,
    (:DE, :Wind) => 180_000.0,
    (:SE, :PV) => 75_000.0,
    (:DK, :PV) => 60_000.0,
    (:DE, :PV) => 460_000.0,
    (:SE, :Gas) => Inf,
    (:DK, :Gas) => Inf,
    (:DE, :Gas) => Inf,
    (:SE, :Hydro) => 14_000.0,
    (:DK, :Hydro) => 0.0,
    (:DE, :Hydro) => 0.0,
    (:SE, :Nuclear) => Inf,
    (:DK, :Nuclear) => Inf,
    (:DE, :Nuclear) => Inf,
)

const HYDRO_RESERVOIR_SIZE_MWH = 33 * 1_000_000.0 # 33 TWh


# Annualized investment cost in EUR/MW/year.
# AC = IC * r / (1 - 1 / (1+r)^lt)
# where
# * AC -- Annualized Cost [EUR/MW/year]
# * IC -- investment cost [EUR/MW]
# * r = 5% -- discount rate [unitless]
# * lt -- lifetime [years]
annualized_cost_per_mw(tech::Technology) =
    investment_cost_eur_per_mw[tech] *
    DISCOUNT_RATE / (1.0 - (1.0 / (1.0 + DISCOUNT_RATE)) ^ lifetime_years[tech])

################################################################################
# Time-series loading
################################################################################

struct TimeSeriesData
    time::Vector{Int}
    load::Dict{Country, Vector{Float64}}
    # Wind_* and PV_* CSV columns, keyed by (country, technology), e.g. (:SE, :Wind).
    capacity_factor::Dict{Tuple{Country, Technology}, Vector{Float64}}
    hydro_inflow::Vector{Float64}
end

function read_timeseries(path::AbstractString)
    lines = readlines(path)
    isempty(lines) && error("$(path) is empty")

    header = split(strip(lines[1]), ',')
    columns = Dict(name => i for (i, name) in enumerate(header))

    required = [
        "time", "Wind_DE", "PV_DE", "Wind_SE", "PV_SE", "Wind_DK", "PV_DK",
        "Load_DE", "Load_DK", "Load_SE", "Hydro_inflow",
    ]
    missing = filter(name -> !haskey(columns, name), required)
    isempty(missing) || error("Missing required columns in $(path): $(join(missing, ", "))")

    n = length(lines) - 1
    time = Vector{Int}(undef, n)
    load = Dict(country => Vector{Float64}(undef, n) for country in COUNTRIES)
    capacity_factor = Dict((country, tech) => Vector{Float64}(undef, n)
                           for country in COUNTRIES for tech in VARIABLE_RENEWABLES)
    hydro_inflow = Vector{Float64}(undef, n)

    for (row, line) in enumerate(lines[2:end])
        values = split(strip(line), ',')
        time[row] = parse(Int, values[columns["time"]])

        for country in COUNTRIES
            suffix = String(country)
            load[country][row] = parse(Float64, values[columns["Load_$(suffix)"]])
            for tech in VARIABLE_RENEWABLES
                capacity_factor[(country, tech)][row] =
                    parse(Float64, values[columns["$(tech)_$(suffix)"]])
            end
        end

        hydro_inflow[row] = parse(Float64, values[columns["Hydro_inflow"]])
    end

    n == HOURS_PER_YEAR || @warn "Expected 8760 hourly rows, got $(n)."
    return TimeSeriesData(time, load, capacity_factor, hydro_inflow)
end
