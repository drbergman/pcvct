filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

# make a few more sims to test deletion
out = run(Monad(1; n_replicates=3))
@test out.trial isa Monad

simulation_id = out.trial.simulation_ids[1]

deleteSimulation(simulation_id)
@test !isdir(joinpath(pcvct.data_dir, "outputs", "simulations", string(simulation_id)))

pcvct.eraseSimulationID(out.trial.simulation_ids[2])

pcvct.deleteMonad(1:4)
pcvct.deleteSampling(1)
pcvct.deleteTrial(1)

input_buffer = IOBuffer("n")
old_stdin = stdin  # Save the original stdin
Base.stdin = input_buffer
pcvct.deleteSimulationsByStatus(["Queued", "Failed"])
Base.stdin = old_stdin

pcvct.deleteSimulationsByStatus(; user_check=false)

pcvct.deleteAllSimulations()
resetDatabase(; force_reset=true)

input_buffer = IOBuffer("y")
old_stdin = stdin  # Save the original stdin
Base.stdin = input_buffer
resetDatabase()
Base.stdin = old_stdin

input_buffer = IOBuffer("n\nn\n")
old_stdin = stdin  # Save the original stdin
Base.stdin = input_buffer
@test_throws ErrorException resetDatabase()
Base.stdin = old_stdin

input_buffer = IOBuffer("n\ny\n")
old_stdin = stdin  # Save the original stdin
Base.stdin = input_buffer
resetDatabase()
Base.stdin = old_stdin