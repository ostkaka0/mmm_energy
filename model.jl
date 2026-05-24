
function build_model(country)
    m = Model()

    # Capacity per energy sorce(MWh)
    @variable(m, 0 <= x[i=EnergySources] <= max_capacity[country, i])

    annualized_investment_cost = sum(x .* investment_cost ./ lifetime)
    variable_cost = 0 #???
    cost = annualized_investment_cost + variable_cost 
    @objective(m, Min, cost)

    return m, x
end
