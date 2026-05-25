
## 2 Assignment
Minimize: total cost = ?
We only have hydro power in sweden, everything else is built  from scratch.
Cost of investment distributed over the economic life-time of those investments

Cost is made up of:
* Annualized investment cost (€/MW)
* Variable cost when to supply electricity (€/MWh)

One whole year will be modelled. We model hour-by-hour.



### 2.1 Model setupp and data
TimeSeries.csv:
* time
* Wind
* PV
* Load: Hourly electricity demand for each region.
* Hydro-inflow 



generation options:
* Wind power
* solar PV
* Gas turbines
* Hydro(sweden only)
where in some scenarios we will also have:
* Batteries
* transmission lines
* nuclear power

Hydro in sweden:
* Assume hydro power in sweden is today 14 GW, and is still in place in 2050.
* Model hydro as one big plant with one reservoir and one turbine.
* Aggregated installed capacity is 14 GW.
* Aggregated hyddro reservoir storage size is 33 TWh.
* Water inflow is spread out over one year.
* Starting water = ending water: "You need to
constrain the reservoir so that you avoid using all the water in the reservoir during the modeled
year and a saving nothing for the coming year"


### AC(Annualized Cost)
AC = IC * r / (1 - 1 / (1+r)^lt)
where
* r = 5% -- discount rate.
* lt -- lifetime
* IC -- investment cost

