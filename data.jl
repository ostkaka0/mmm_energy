
# @enum Energy Wind=1 PV=2 Gas=3 Hydro=4 Batteries=5 Transmission=6 Nuclear=7
Wind=1
PV=2
Gas=3
Hydro=4
Batteries=5
Transmission=6
Nuclear=7

# EnergySources = 1:length(instances(Energy))
EnergySources = 1:7

# @enum Country
# se=1 dk=2 de=3
se=1
dk=2
de=3

# Euro/kW
investment_cost = [1100, 600, 500, 0, 150, 2500, 7700]

# Euro/MWh_elec
running_cost = [0.1, 0.1, 2, 0.1, 0.1, 0, 4]

# Euro/MWh_fuel
fuel_cost = [0, 0, 22, 0, 0, 0, 3.2]

# Years
lifetime = [25, 25, 30, 80, 10, 50, 50]

efficiency = [NaN, NaN, 0.4, NaN, 0.9, 0.98, 0.4]

# ton CO₂/MWh_fuel
emission_factor = [0, 0, 0.202, 0, 0, 0, 0]

# Maximum capacity to invest in [GW]
max_capacity_se = [280, 75, Inf, 14, Inf, Inf, Inf]
max_capacity_dk = [90, 60, Inf, 0, Inf, Inf, Inf]
max_capacity_de = [180, 460, Inf, 0, Inf, Inf, Inf]
max_capacity = [max_capacity_se, max_capacity_dk, max_capacity_de]

# @assert(length(instances(Energy)) == length(investment_cost))
# @assert(length(instances(Energy)) == length(running_cost))
# @assert(length(instances(Energy)) == length(fuel_cost))
# @assert(length(instances(Energy)) == length(lifetime))
# @assert(length(instances(Energy)) == length(efficiency))
# @assert(length(instances(Energy)) == length(emission_factor))
# @assert(length(instances(Energy)) == length(max_capacity_se))
# @assert(length(instances(Energy)) == length(max_capacity_dk))
# @assert(length(instances(Energy)) == length(max_capacity_de))
