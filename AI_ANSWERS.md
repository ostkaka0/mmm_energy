# Answers

This document answers the questions in the assignment based on the current model runs and
generated plot data. Costs are annual system costs. Capacities are installed capacities.

## Model Formulation

The model minimizes annualized investment costs plus variable generation, fuel, storage and
transmission operating costs over one full year with hourly resolution.

Decision variables:

- Installed generation capacity by country and technology: wind, PV, gas, and in Exercise 4
  nuclear. Swedish hydro is fixed at 14 GW.
- Hourly generation by country and technology.
- In battery scenarios: installed battery power/energy capacity, hourly battery charge,
  discharge, and storage level.
- In transmission scenarios: installed line capacity between countries and hourly directed
  transmission flows.

Main input parameters:

- Hourly load for Sweden, Denmark and Germany from `TimeSeries.csv`.
- Hourly wind and PV capacity factors from `TimeSeries.csv`.
- Hourly Swedish hydro inflow from `TimeSeries.csv`.
- Investment cost, running cost, fuel cost, lifetime, efficiency, emission factor and maximum
  installable capacity from the assignment table.
- Discount rate: 5%.

Main constraints:

- Hourly load balance in each country: domestic generation plus battery discharge plus imports
  must equal load plus battery charge plus exports.
- Wind and PV generation cannot exceed installed capacity multiplied by the hourly capacity
  factor.
- Gas and nuclear generation cannot exceed installed capacity.
- Swedish hydro generation cannot exceed 14 GW, and the hydro reservoir follows hourly inflow,
  generation and a cyclic end condition.
- Installed wind, PV and hydro capacities respect the assignment limits.
- Battery storage follows an hourly storage balance, with round-trip efficiency represented in
  charging/discharging, and storage size equal to installed battery power capacity.
- Transmission flows are limited by installed line capacity, and opposite directed lines between
  the same country pair are constrained to have equal capacity.
- Exercises 2-4 include a joint CO2 cap equal to 10% of Exercise 1 emissions.

## Average Capacity Factors

| Country | Wind | PV |
|---|---:|---:|
| Sweden | 41.0% | 10.0% |
| Denmark | 32.0% | 11.4% |
| Germany | 28.5% | 13.3% |

Sweden has the best wind resource, while Germany has the best PV resource. These differences
help explain why the model tends to build more wind in Sweden and more PV in Germany when
transmission and storage make it useful to exploit those resources.

## Exercise 1: No CO2 Cap, No Batteries, No Transmission

Result:

- Total system cost: 37.24 bn EUR/year.
- CO2 emissions: 138.77 Mton/year.

Installed capacities:

| Country | Wind GW | PV GW | Gas GW | Hydro GW |
|---|---:|---:|---:|---:|
| Sweden | 30.64 | 0.00 | 16.31 | 14.00 |
| Denmark | 10.49 | 1.79 | 6.66 | 0.00 |
| Germany | 130.99 | 91.69 | 91.70 | 0.00 |

Annual production:

| Country | Wind TWh | PV TWh | Gas TWh | Hydro TWh |
|---|---:|---:|---:|---:|
| Sweden | 102.47 | 0.00 | 9.86 | 65.00 |
| Denmark | 25.08 | 1.59 | 16.94 | 0.00 |
| Germany | 292.04 | 97.57 | 248.01 | 0.00 |

Technologies that emerge:

- Wind is built in all three countries because it has low operating cost and, especially in
  Sweden, high capacity factors.
- PV is built mainly in Germany and a little in Denmark. It is not built in Sweden in this run
  because the Swedish PV capacity factor is lower and Swedish wind/hydro are more attractive.
- Gas is built in all countries because there is no CO2 cap, and gas provides cheap dispatchable
  capacity during hours when wind and PV are insufficient.
- Hydro is fixed in Sweden and is valuable because it is dispatchable within the reservoir
  constraint.

Differences between countries are mainly explained by renewable capacity factors, demand size,
and the fixed Swedish hydro resource. Germany has the largest demand, so it builds the largest
amount of capacity. Sweden uses hydro and good wind conditions instead of PV.

## Exercise 2: 90% CO2 Reduction Cap

### Exercise 2a: CO2 Cap, No Batteries

The model is infeasible. With a 90% emissions reduction cap, no batteries and no transmission,
the system cannot meet every country's hourly demand using only local wind, PV, hydro and the
small allowed amount of gas emissions. The issue is not total annual renewable energy alone;
it is hourly balancing. There are hours with too little local renewable output, and without storage
or imports the model has no low-carbon way to move electricity from surplus hours or regions
to deficit hours.

### Exercise 2b: CO2 Cap With Batteries

Result:

- Total system cost: 64.08 bn EUR/year.
- CO2 emissions: 13.88 Mton/year.

Installed capacities:

| Country | Wind GW | PV GW | Gas GW | Hydro GW | Battery GW/GWh |
|---|---:|---:|---:|---:|---:|
| Sweden | 47.31 | 0.00 | 8.16 | 14.00 | 78.06 |
| Denmark | 25.42 | 19.09 | 2.69 | 0.00 | 46.64 |
| Germany | 180.00 | 460.00 | 38.27 | 0.00 | 932.73 |

Annual production:

| Country | Wind TWh | PV TWh | Gas TWh | Hydro TWh | Battery discharge TWh |
|---|---:|---:|---:|---:|---:|
| Sweden | 110.24 | 0.00 | 2.51 | 65.00 | 3.81 |
| Denmark | 32.88 | 10.01 | 1.05 | 0.00 | 3.02 |
| Germany | 333.71 | 292.19 | 23.91 | 0.00 | 109.85 |

Compared with Exercise 1:

- Cost increases from 37.24 to 64.08 bn EUR/year because the system has to replace much of
  the cheap gas generation with renewable overbuild and batteries.
- CO2 emissions fall from 138.77 to 13.88 Mton/year, which is the required 90% reduction.
- Wind and PV capacity increase strongly, especially Germany PV and Germany wind.
- Gas capacity remains as backup, but gas production falls sharply because the CO2 cap limits
  how often it can run.
- Battery capacity becomes very large, especially in Germany, because storage is the only new
  flexibility option in this exercise.

## Exercise 3: CO2 Cap, Batteries and Transmission

Result:

- Total system cost: 48.52 bn EUR/year.
- CO2 emissions: 13.88 Mton/year.

Installed capacities:

| Country | Wind GW | PV GW | Gas GW | Hydro GW | Battery GW/GWh |
|---|---:|---:|---:|---:|---:|
| Sweden | 127.19 | 0.00 | 7.26 | 14.00 | 47.42 |
| Denmark | 21.71 | 4.27 | 2.91 | 0.00 | 13.72 |
| Germany | 163.65 | 167.97 | 53.93 | 0.00 | 247.39 |

Annual production:

| Country | Wind TWh | PV TWh | Gas TWh | Hydro TWh | Battery discharge TWh |
|---|---:|---:|---:|---:|---:|
| Sweden | 247.27 | 0.00 | 0.37 | 65.00 | 2.92 |
| Denmark | 36.14 | 3.31 | 0.89 | 0.00 | 1.13 |
| Germany | 326.88 | 158.87 | 26.23 | 0.00 | 28.08 |

Transmission:

| Line | Capacity GW | Energy TWh/year |
|---|---:|---:|
| SE to DK | 3.41 | 5.88 |
| DK to SE | 3.41 | 1.84 |
| SE to DE | 46.33 | 131.60 |
| DE to SE | 46.33 | 0.71 |
| DK to DE | 0.32 | 0.65 |
| DE to DK | 0.32 | 0.13 |

Transmission reduces total system cost from 64.08 to 48.52 bn EUR/year compared with
Exercise 2b. The main reason is that the system can use Sweden's strong wind resource and hydro
flexibility to support Germany and Denmark. This reduces the need for local German PV
overbuild and very large battery capacity. Germany still needs substantial gas capacity for
security in low-renewable hours, but gas production remains limited by the CO2 cap.

The largest transmission build is between Sweden and Germany. The flow is mostly from Sweden
to Germany, showing that Sweden becomes a major exporter in the cost-optimal system.

## Exercise 4: Add Nuclear Power

Result:

- Total system cost: 43.52 bn EUR/year.
- CO2 emissions: 13.88 Mton/year.

Installed capacities:

| Country | Wind GW | PV GW | Gas GW | Hydro GW | Battery GW/GWh | Nuclear GW |
|---|---:|---:|---:|---:|---:|---:|
| Sweden | 51.29 | 0.00 | 13.13 | 14.00 | 2.04 | 0.00 |
| Denmark | 13.47 | 4.44 | 5.03 | 0.00 | 4.69 | 0.16 |
| Germany | 87.51 | 85.24 | 35.02 | 0.00 | 45.40 | 42.50 |

Annual production:

| Country | Wind TWh | PV TWh | Gas TWh | Hydro TWh | Battery discharge TWh | Nuclear TWh |
|---|---:|---:|---:|---:|---:|---:|
| Sweden | 172.84 | 0.00 | 3.05 | 65.00 | 0.44 | 0.00 |
| Denmark | 33.14 | 4.06 | 2.98 | 0.00 | 1.04 | 0.62 |
| Germany | 216.41 | 98.41 | 21.45 | 0.00 | 9.91 | 243.50 |

Transmission:

| Line | Capacity GW | Energy TWh/year |
|---|---:|---:|
| SE to DK | 2.91 | 8.24 |
| DK to SE | 2.91 | 4.66 |
| SE to DE | 14.10 | 63.92 |
| DE to SE | 14.10 | 4.17 |
| DK to DE | 0.17 | 0.64 |
| DE to DK | 0.17 | 0.15 |

Compared with previous exercises:

- Cost falls from 48.52 to 43.52 bn EUR/year compared with Exercise 3.
- Cost is still higher than Exercise 1 because the CO2 cap is still binding.
- CO2 emissions stay at 13.88 Mton/year, so nuclear changes the cost and technology mix rather
  than the emissions target.

Nuclear does emerge. Almost all nuclear capacity is built in Germany, with 42.50 GW installed
and 243.50 TWh/year produced. Denmark gets only a very small amount, and Sweden gets none.

Capacities especially reduced compared with Exercise 3:

- Sweden wind falls from 127.19 to 51.29 GW.
- Germany wind falls from 163.65 to 87.51 GW.
- Germany PV falls from 167.97 to 85.24 GW.
- Germany battery capacity falls from 247.39 to 45.40 GW/GWh.
- Sweden-Germany transmission capacity falls from 46.33 to 14.10 GW.

This happens because nuclear provides low-carbon dispatchable generation. It can produce during
hours when wind and PV output is low, so the system needs less renewable overbuild, less storage,
and less long-distance transmission.

The nuclear result is sensitive to:

- Nuclear investment cost and lifetime.
- Discount rate, because nuclear is capital intensive.
- Nuclear fuel and running costs.
- Renewable investment costs and capacity factors.
- Maximum wind and PV build limits.
- Battery cost and storage duration assumption.
- Transmission cost and loss assumption.
- CO2 cap stringency.
- Whether nuclear is allowed to run flexibly or is constrained by operational limits. The current
  model treats nuclear as dispatchable up to installed capacity.

Country differences:

- Germany builds most nuclear because it has the largest demand and no hydro resource. Nuclear
  is valuable there because it directly replaces a large need for German renewable overbuild,
  batteries and imports.
- Sweden builds no nuclear because it already has hydro flexibility and the best wind capacity
  factor. In the nuclear scenario Sweden still exports wind and hydro-supported electricity.
- Denmark builds only a small amount of nuclear because its demand is smaller, it has wind
  resources, and it can trade with Sweden and Germany.

## Missing or Incomplete Items

- <We need to regenerate or verify the PDF plots for Exercises 3 and 4 after the latest code
  changes if these exact figures will be submitted. The numeric `.dat` files exist, but not all
  final PDFs are currently present for every scenario.>
- <We need to decide whether the very large one-hour battery capacities in Exercise 2b should be
  discussed as a model simplification artifact, because the assignment assumes 1 MW battery
  capacity also gives only 1 MWh of energy storage.>
- <We need to verify whether the supervisor expects the full mathematical formulation in
  notation, or whether this written formulation is sufficient for the presentation.>
