filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

if Sys.isapple()
    makeMovie(Simulation(1))
    @test isfile(joinpath(pcvct.data_dir, "outputs", "simulations", "1", "output", "out.mp4"))
    @test makeMovie(1) === false
else
    @test_throws ErrorException makeMovie(Simulation(1))
end