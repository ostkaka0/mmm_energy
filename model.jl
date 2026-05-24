using JuMP

################################################################################
# Scenario types
################################################################################

struct Scenario
    name::String
    allow_batteries::Bool
    allow_transmission::Bool
    allow_nuclear::Bool
    co2_cap_ton::Union{Nothing, Float64}
end

struct ScenarioResult
    scenario::Scenario
    status::TerminationStatusCode
    total_cost_eur::Float64
    total_emissions_ton::Float64
    capacity_mw::Dict{Tuple{Symbol, Symbol}, Float64}
    production_mwh::Dict{Tuple{Symbol, Symbol}, Float64}
    battery_capacity_mw::Dict{Symbol, Float64}
    battery_discharge_mwh::Dict{Symbol, Float64}
    transmission_capacity_mw::Dict{Tuple{Symbol, Symbol}, Float64}
    transmitted_energy_mwh::Dict{Tuple{Symbol, Symbol}, Float64}
    hourly_generation_mwh::Dict{Tuple{Symbol, Symbol}, Vector{Float64}}
    hourly_battery_discharge_mwh::Dict{Symbol, Vector{Float64}}
    hourly_battery_charge_mwh::Dict{Symbol, Vector{Float64}}
    hourly_flow_mwh::Dict{Tuple{Symbol, Symbol}, Vector{Float64}}
end

################################################################################
# Model construction and solution
################################################################################

function active_generation_techs(scenario::Scenario)
    techs = [:Wind, :PV, :Gas, :Hydro]
    scenario.allow_nuclear && push!(techs, :Nuclear)
    return techs
end

fuel_use_mwh(tech::Symbol, generation_mwh) =
    haskey(efficiency, tech) ? generation_mwh / efficiency[tech] : zero(generation_mwh)

function build_model(data::TimeSeriesData, scenario::Scenario)
    hours = eachindex(data.time)
    techs = active_generation_techs(scenario)
    directed_lines = [(from, to) for from in COUNTRIES for to in COUNTRIES if from != to]

    model = Model()
    set_silent(model)

    @variable(model, capacity[c in COUNTRIES, tech in techs] >= 0)
    @variable(model, generation[t in hours, c in COUNTRIES, tech in techs] >= 0)
    @variable(model, battery_capacity[c in COUNTRIES] >= 0)
    @variable(model, battery_charge[t in hours, c in COUNTRIES] >= 0)
    @variable(model, battery_discharge[t in hours, c in COUNTRIES] >= 0)
    @variable(model, battery_storage[t in hours, c in COUNTRIES] >= 0)
    @variable(model, transmission_capacity[line in directed_lines] >= 0)
    @variable(model, transmission_flow[t in hours, line in directed_lines] >= 0)
    @variable(model, hydro_storage[t in hours] >= 0)

    for c in COUNTRIES, tech in techs
        max_cap = max_capacity_mw[(c, tech)]
        isfinite(max_cap) && @constraint(model, capacity[c, tech] <= max_cap)
    end

    if :Hydro in techs
        @constraint(model, capacity[:SE, :Hydro] == max_capacity_mw[(:SE, :Hydro)])
        @constraint(model, capacity[:DK, :Hydro] == 0)
        @constraint(model, capacity[:DE, :Hydro] == 0)
    end

    for t in hours, c in COUNTRIES, tech in techs
        @constraint(model, generation[t, c, tech] <= capacity[c, tech])
    end

    for t in hours, c in COUNTRIES, tech in intersect(techs, VARIABLE_RENEWABLES)
        @constraint(model, generation[t, c, tech] <=
                           data.capacity_factor[(c, tech)][t] * capacity[c, tech])
    end

    @constraint(model, [t in hours], hydro_storage[t] <= HYDRO_RESERVOIR_SIZE_MWH)
    if :Hydro in techs
        @constraint(model, [t in hours],
            hydro_storage[t] ==
            hydro_storage[t == first(hours) ? last(hours) : t - 1] +
            data.hydro_inflow[t] -
            generation[t, :SE, :Hydro]
        )
    else
        @constraint(model, [t in hours], hydro_storage[t] == 0)
    end

    if scenario.allow_batteries
        @constraint(model, [t in hours, c in COUNTRIES], battery_storage[t, c] <= battery_capacity[c])
        @constraint(model, [t in hours, c in COUNTRIES], battery_charge[t, c] <= battery_capacity[c])
        @constraint(model, [t in hours, c in COUNTRIES], battery_discharge[t, c] <= battery_capacity[c])
        @constraint(model, [t in hours, c in COUNTRIES],
            battery_storage[t, c] ==
            battery_storage[t == first(hours) ? last(hours) : t - 1, c] +
            efficiency[:Battery] * battery_charge[t, c] -
            battery_discharge[t, c]
        )
    else
        @constraint(model, [c in COUNTRIES], battery_capacity[c] == 0)
        @constraint(model, [t in hours, c in COUNTRIES], battery_charge[t, c] == 0)
        @constraint(model, [t in hours, c in COUNTRIES], battery_discharge[t, c] == 0)
        @constraint(model, [t in hours, c in COUNTRIES], battery_storage[t, c] == 0)
    end

    if scenario.allow_transmission
        for (a, b) in [(COUNTRIES[i], COUNTRIES[j]) for i in eachindex(COUNTRIES) for j in i+1:length(COUNTRIES)]
            @constraint(model, transmission_capacity[(a, b)] == transmission_capacity[(b, a)])
        end
        @constraint(model, [t in hours, line in directed_lines],
            transmission_flow[t, line] <= transmission_capacity[line])
    else
        @constraint(model, [line in directed_lines], transmission_capacity[line] == 0)
        @constraint(model, [t in hours, line in directed_lines], transmission_flow[t, line] == 0)
    end

    @constraint(model, [t in hours, c in COUNTRIES],
        sum(generation[t, c, tech] for tech in techs) +
        battery_discharge[t, c] +
        sum(efficiency[:Transmission] * transmission_flow[t, (from, c)]
            for from in COUNTRIES if from != c) ==
        data.load[c][t] +
        battery_charge[t, c] +
        sum(transmission_flow[t, (c, to)] for to in COUNTRIES if to != c)
    )

    emissions = @expression(model,
        sum(fuel_use_mwh(tech, generation[t, c, tech]) * emission_factor_ton_per_mwh_fuel[tech]
            for t in hours, c in COUNTRIES, tech in techs)
    )

    if scenario.co2_cap_ton !== nothing
        @constraint(model, emissions <= scenario.co2_cap_ton)
    end

    investment_cost = @expression(model,
        sum(annualized_cost_per_mw(tech) * capacity[c, tech] for c in COUNTRIES, tech in techs) +
        (scenario.allow_batteries ?
            sum(annualized_cost_per_mw(:Battery) * battery_capacity[c] for c in COUNTRIES) : 0.0) +
        (scenario.allow_transmission ?
            0.5 * sum(annualized_cost_per_mw(:Transmission) * transmission_capacity[line]
                      for line in directed_lines) : 0.0)
    )

    variable_cost = @expression(model,
        sum(
            running_cost_eur_per_mwh[tech] * generation[t, c, tech] +
            fuel_cost_eur_per_mwh_fuel[tech] * fuel_use_mwh(tech, generation[t, c, tech])
            for t in hours, c in COUNTRIES, tech in techs
        ) +
        sum(running_cost_eur_per_mwh[:Battery] * battery_discharge[t, c]
            for t in hours, c in COUNTRIES)
    )

    @objective(model, Min, investment_cost + variable_cost)

    return model, (; capacity, generation, battery_capacity, battery_charge, battery_discharge,
                   transmission_capacity, transmission_flow, emissions, techs, directed_lines)
end

function solve_scenario(data::TimeSeriesData, scenario::Scenario, optimizer)
    model, vars = build_model(data, scenario)
    set_optimizer(model, optimizer)
    optimize!(model)

    status = termination_status(model)
    status == OPTIMAL || error("Scenario $(scenario.name) ended with status $(status)")

    hours = eachindex(data.time)
    capacity_mw = Dict((c, tech) => value(vars.capacity[c, tech])
                       for c in COUNTRIES for tech in vars.techs)
    production_mwh = Dict((c, tech) => sum(value(vars.generation[t, c, tech]) for t in hours)
                          for c in COUNTRIES for tech in vars.techs)
    battery_capacity_mw = Dict(c => value(vars.battery_capacity[c]) for c in COUNTRIES)
    battery_discharge_mwh = Dict(c => sum(value(vars.battery_discharge[t, c]) for t in hours)
                                 for c in COUNTRIES)
    transmission_capacity_mw = Dict(line => value(vars.transmission_capacity[line])
                                    for line in vars.directed_lines)
    transmitted_energy_mwh = Dict(line => sum(value(vars.transmission_flow[t, line]) for t in hours)
                                  for line in vars.directed_lines)

    hourly_generation_mwh = Dict((c, tech) => [value(vars.generation[t, c, tech]) for t in hours]
                                 for c in COUNTRIES for tech in vars.techs)
    hourly_battery_discharge_mwh = Dict(c => [value(vars.battery_discharge[t, c]) for t in hours]
                                        for c in COUNTRIES)
    hourly_battery_charge_mwh = Dict(c => [value(vars.battery_charge[t, c]) for t in hours]
                                     for c in COUNTRIES)
    hourly_flow_mwh = Dict(line => [value(vars.transmission_flow[t, line]) for t in hours]
                           for line in vars.directed_lines)

    return ScenarioResult(
        scenario,
        status,
        objective_value(model),
        value(vars.emissions),
        capacity_mw,
        production_mwh,
        battery_capacity_mw,
        battery_discharge_mwh,
        transmission_capacity_mw,
        transmitted_energy_mwh,
        hourly_generation_mwh,
        hourly_battery_discharge_mwh,
        hourly_battery_charge_mwh,
        hourly_flow_mwh,
    )
end
