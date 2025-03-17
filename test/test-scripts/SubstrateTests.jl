filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

asts = pcvct.AverageSubstrateTimeSeries(1)
asts = pcvct.AverageSubstrateTimeSeries(Simulation(1))
ests = pcvct.ExtracellularSubstrateTimeSeries(1)
ests = pcvct.ExtracellularSubstrateTimeSeries(Simulation(1))

# misc tests
asts["time"]
substrate_names = keys(asts.substrate_concentrations)
asts[first(substrate_names)]
@test_throws ArgumentError asts["not_a_substrate"]

ests["time"]
cell_types = keys(ests.data)
ests[first(cell_types)]
@test_throws ArgumentError ests["not_a_cell_type"]