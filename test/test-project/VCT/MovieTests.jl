filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

makeMovie(Simulation(1))
@test isfile(joinpath(pcvct.data_dir, "outputs", "simulations", "1", "output", "out.mp4"))