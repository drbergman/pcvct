filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

simulation = Simulation(Monad(1))
@test simulation isa Simulation

prune_options = PruneOptions(true, true, true, true, true)
out = run(simulation; force_recompile=false, prune_options=prune_options)
@test out.n_success == 1

pcvct.deleteSimulation(simulation.id)
@test !isdir(joinpath(pcvct.data_dir, "outputs", "simulations", string(simulation.id)))