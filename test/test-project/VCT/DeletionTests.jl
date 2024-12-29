filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

deleteSimulation(1)
@test !isdir(joinpath(pcvct.data_dir, "outputs", "simulations", "1"))
pcvct.deleteMonad(1:10)
pcvct.deleteSampling(1)
pcvct.deleteTrial(1)

pcvct.deleteSimulationsByStatus(; user_check=false)
resetDatabase(; force_reset=true)