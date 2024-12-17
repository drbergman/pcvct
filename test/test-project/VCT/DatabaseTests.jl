filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

simulationsTable()
simulation_ids = 1:5
printSimulationsTable(simulation_ids)
pcvct.printConfigVariationsTable(simulation_ids)
pcvct.printRulesetsVariationsTable(simulation_ids)