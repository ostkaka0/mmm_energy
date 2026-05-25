using JuMP

################################################################################
# Scenario types
################################################################################

struct Scenario
    name               ::String
    allow_batteries    ::Bool
    allow_transmission ::Bool
    allow_nuclear      ::Bool
    co2_cap_ton        ::Union{Nothing, Float64}
end

struct ScenarioResult
    scenario                          ::Scenario
    status                            ::TerminationStatusCode # Status code returned by JuMP
    total_cost_eur                    ::Float64 # Annualized system cost for the modeled year [EUR/year].
    total_emissions_ton               ::Float64 # Summed over all modeled hours, which is one year.
    capacity_mw                       ::Dict{Tuple{Country, Technology}, Float64}
    total_production_mwh              ::Dict{Tuple{Country, Technology}, Float64}
    battery_capacity_mw               ::Dict{Country, Float64}
    total_battery_discharge_mwh       ::Dict{Country, Float64}
    transmission_capacity_mw          ::Dict{Tuple{Country, Country}, Float64}
    total_transmitted_energy_sent_mwh ::Dict{Tuple{Country, Country}, Float64} # Sent-side energy before transmission losses.
    hourly_generation_mwh             ::Dict{Tuple{Country, Technology}, Vector{Float64}}
    hourly_battery_discharge_mwh      ::Dict{Country, Vector{Float64}}
    hourly_battery_charge_mwh         ::Dict{Country, Vector{Float64}}
    hourly_flow_mwh                   ::Dict{Tuple{Country, Country}, Vector{Float64}} # Sent-side flow before transmission losses.
end

################################################################################
# Model construction and solution
################################################################################

function active_generation_techs(scenario::Scenario)
    techs = [:Wind, :PV, :Gas, :Hydro]
    scenario.allow_nuclear && push!(techs, :Nuclear)
    return techs
end

# Only fuel-consuming generation technologies should have fuel efficiency entries.
fuel_use_mwh(tech::Technology, generation_mwh) =
    haskey(efficiency, tech) ? generation_mwh / efficiency[tech] : zero(generation_mwh)

function build_model(data::TimeSeriesData, scenario::Scenario)
    hours = eachindex(data.time)
    techs = active_generation_techs(scenario)
    # One directed transmission line for each ordered country pair, e.g. SE->DE and DE->SE.
    directed_lines = [(from, to) for from in COUNTRIES for to in COUNTRIES if from != to]
    undirected_lines = [(COUNTRIES[i], COUNTRIES[j])
                        for i in eachindex(COUNTRIES) for j in i+1:length(COUNTRIES)]
    renewable_techs = intersect(techs, VARIABLE_RENEWABLES)

    model = Model()

    @variable(model, capacity[c in COUNTRIES, tech in techs] >= 0)
    @variable(model, generation[t in hours, c in COUNTRIES, tech in techs] >= 0)
    @variable(model, hydro_storage[t in hours] >= 0)

    battery_capacity = nothing
    battery_charge = nothing
    battery_discharge = nothing
    battery_storage = nothing
    if scenario.allow_batteries
        @variable(model, battery_capacity[c in COUNTRIES] >= 0)
        @variable(model, battery_charge[t in hours, c in COUNTRIES] >= 0)
        @variable(model, battery_discharge[t in hours, c in COUNTRIES] >= 0)
        @variable(model, battery_storage[t in hours, c in COUNTRIES] >= 0)
    end

    transmission_capacity = nothing
    transmission_flow = nothing
    if scenario.allow_transmission
        @variable(model, transmission_capacity[line in directed_lines] >= 0)
        @variable(model, transmission_flow[t in hours, line in directed_lines] >= 0)
    end

    # These helpers let the load-balance constraint stay identical across scenarios.
    battery_charge_at(t, c) = scenario.allow_batteries ? battery_charge[t, c] : 0.0
    battery_discharge_at(t, c) = scenario.allow_batteries ? battery_discharge[t, c] : 0.0
    imports_at(t, c) =
        scenario.allow_transmission ?
        sum(efficiency[:Transmission] * transmission_flow[t, (from, c)]
            for from in COUNTRIES if from != c) :
        0.0
    exports_at(t, c) =
        scenario.allow_transmission ?
        sum(transmission_flow[t, (c, to)] for to in COUNTRIES if to != c) :
        0.0

    for c in COUNTRIES, tech in techs
        max_cap = max_capacity_mw[(c, tech)]
        isfinite(max_cap) && @constraint(model, capacity[c, tech] <= max_cap)
    end

    if :Hydro in techs
        # Hydro capacity is fixed assignment data, not an investment decision.
        @constraint(model, [c in COUNTRIES], capacity[c, :Hydro] == max_capacity_mw[(c, :Hydro)])
    end

    for t in hours, c in COUNTRIES, tech in techs
        @constraint(model, generation[t, c, tech] <= capacity[c, tech])
    end

    for t in hours, c in COUNTRIES, tech in renewable_techs
        @constraint(model, generation[t, c, tech] <=
                           data.capacity_factor[(c, tech)][t] * capacity[c, tech])
    end

    @constraint(model, [t in hours], hydro_storage[t] <= HYDRO_RESERVOIR_SIZE_MWH)
    if :Hydro in techs
        @constraint(model, [t in hours],
            # Cyclic reservoir balance: the first hour uses the last hour as previous storage.
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
            # Cyclic balance: the first hour uses the last hour as previous storage.
            battery_storage[t, c] ==
            battery_storage[t == first(hours) ? last(hours) : t - 1, c] +
            efficiency[:Battery] * battery_charge[t, c] -
            battery_discharge[t, c]
        )
    end

    if scenario.allow_transmission
        for (a, b) in undirected_lines
            # Two directed variables represent one physical bidirectional line with equal capacity.
            @constraint(model, transmission_capacity[(a, b)] == transmission_capacity[(b, a)])
        end
        @constraint(model, [t in hours, line in directed_lines],
            transmission_flow[t, line] <= transmission_capacity[line])
    end

    @constraint(model, [t in hours, c in COUNTRIES],
        sum(generation[t, c, tech] for tech in techs) +
        battery_discharge_at(t, c) +
        imports_at(t, c) ==
        data.load[c][t] +
        battery_charge_at(t, c) +
        exports_at(t, c)
    )

    emissions = @expression(model,
        sum(fuel_use_mwh(tech, generation[t, c, tech]) * emission_factor_ton_per_mwh_fuel[tech]
            for t in hours, c in COUNTRIES, tech in techs)
    )

    if scenario.co2_cap_ton !== nothing
        @constraint(model, emissions <= scenario.co2_cap_ton)
    end

    generation_investment_cost = @expression(model,
        sum(annualized_cost_per_mw(tech) * capacity[c, tech] for c in COUNTRIES, tech in techs)
    )
    battery_investment_cost =
        scenario.allow_batteries ?
        @expression(model, sum(annualized_cost_per_mw(:Battery) * battery_capacity[c]
                               for c in COUNTRIES)) :
        0.0
    transmission_investment_cost =
        scenario.allow_transmission ?
        # Divide by 2 because each physical line is represented by two directed capacities.
        @expression(model, 0.5 * sum(annualized_cost_per_mw(:Transmission) *
                                     transmission_capacity[line] for line in directed_lines)) :
        0.0
    investment_cost = @expression(model,
        generation_investment_cost + battery_investment_cost + transmission_investment_cost
    )

    generation_variable_cost = @expression(model,
        sum(
            running_cost_eur_per_mwh[tech] * generation[t, c, tech] +
            fuel_cost_eur_per_mwh_fuel[tech] * fuel_use_mwh(tech, generation[t, c, tech])
            for t in hours, c in COUNTRIES, tech in techs
        )
    )
    battery_variable_cost =
        scenario.allow_batteries ?
        @expression(model, sum(running_cost_eur_per_mwh[:Battery] * battery_discharge[t, c]
                               for t in hours, c in COUNTRIES)) :
        0.0
    variable_cost = @expression(model,
        generation_variable_cost + battery_variable_cost
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
    total_production_mwh = Dict((c, tech) => sum(value(vars.generation[t, c, tech]) for t in hours)
                                for c in COUNTRIES for tech in vars.techs)
    battery_capacity_mw =
        scenario.allow_batteries ?
        Dict(c => value(vars.battery_capacity[c]) for c in COUNTRIES) :
        Dict(c => 0.0 for c in COUNTRIES)
    total_battery_discharge_mwh =
        scenario.allow_batteries ?
        Dict(c => sum(value(vars.battery_discharge[t, c]) for t in hours) for c in COUNTRIES) :
        Dict(c => 0.0 for c in COUNTRIES)
    transmission_capacity_mw =
        scenario.allow_transmission ?
        Dict(line => value(vars.transmission_capacity[line]) for line in vars.directed_lines) :
        Dict{Tuple{Country, Country}, Float64}()
    total_transmitted_energy_sent_mwh =
        scenario.allow_transmission ?
        Dict(line => sum(value(vars.transmission_flow[t, line]) for t in hours) for line in vars.directed_lines) :
        Dict{Tuple{Country, Country}, Float64}()

    hourly_generation_mwh = Dict((c, tech) => [value(vars.generation[t, c, tech]) for t in hours]
                                 for c in COUNTRIES for tech in vars.techs)
    hourly_battery_discharge_mwh =
        scenario.allow_batteries ?
        Dict(c => [value(vars.battery_discharge[t, c]) for t in hours] for c in COUNTRIES) :
        Dict(c => zeros(length(hours)) for c in COUNTRIES)
    hourly_battery_charge_mwh =
        scenario.allow_batteries ?
        Dict(c => [value(vars.battery_charge[t, c]) for t in hours] for c in COUNTRIES) :
        Dict(c => zeros(length(hours)) for c in COUNTRIES)
    hourly_flow_mwh =
        scenario.allow_transmission ?
        Dict(line => [value(vars.transmission_flow[t, line]) for t in hours] for line in vars.directed_lines) :
        Dict{Tuple{Country, Country}, Vector{Float64}}()

    return ScenarioResult(
        scenario,
        status,
        objective_value(model),
        value(vars.emissions),
        capacity_mw,
        total_production_mwh,
        battery_capacity_mw,
        total_battery_discharge_mwh,
        transmission_capacity_mw,
        total_transmitted_energy_sent_mwh,
        hourly_generation_mwh,
        hourly_battery_discharge_mwh,
        hourly_battery_charge_mwh,
        hourly_flow_mwh,
    )
end
