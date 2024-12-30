filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

# make a few more sims to test deletion
out = run(Monad(1; n_replicates=2))
@test out.trial isa Monad

simulation_id = out.trial.simulation_ids[1]

deleteSimulation(simulation_id)
@test !isdir(joinpath(pcvct.data_dir, "outputs", "simulations", string(simulation_id)))
pcvct.deleteMonad(1:4)
pcvct.deleteSampling(1)
pcvct.deleteTrial(1)

pcvct.deleteSimulationsByStatus(; user_check=false)
pcvct.deleteAllSimulations()
resetDatabase(; force_reset=true)