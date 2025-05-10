filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

pcvct.readConstituentIDs(Trial, 1)
getSimulationIDs([Simulation(1), Simulation(2)])
pcvct.getTrialMonads(1)
getMonadIDs()
getMonadIDs(Trial(1))