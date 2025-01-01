filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

pcvct.readTrialSamplingIDs(Trial(1))
getSimulationIDs([Simulation(1), Simulation(2)])
pcvct.getTrialMonads(1)
pcvct.getMonadIDs()
pcvct.getMonadIDs(Trial(1))