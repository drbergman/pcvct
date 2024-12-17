filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

simulation = Simulation(Monad(1))

prune_options = PruneOptions(true, true, true, true, true)
n_success = run(simulation; force_recompile=false, prune_options=prune_options)
@test n_success == 1

pcvct.deleteSimulation(simulation.id)