using Plots
filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

finalPopulationCount(Simulation(1))

plot(Simulation(1))
plot(Sampling(1))

plotbycelltype(Simulation(1))
plotbycelltype(Sampling(1))
plotbycelltype(Sampling(1); include_cell_types="default")

# misc tests
out = Monad(1; n_replicates=3) |> run
pcvct.MonadPopulationTimeSeries(1)
plot(out)
plot(out.trial)
plotbycelltype(out)
plotbycelltype(out.trial)


pcvct.processIncludeCellTypes(["cancer", "immune"])
pcvct.processIncludeCellTypes(["epi", "mes", ["epi", "mes"]])
@test_throws AssertionError pcvct.processIncludeCellTypes(:mes)

pcvct.processExcludeCellTypes("cancer")
@test_throws ArgumentError pcvct.processExcludeCellTypes(:mes)
plot(out; include_cell_types="default", exclude_cell_types="default")

plot(sampling_from_import; include_cell_types=[["fast T cell", "slow T cell", "effector T cell", "exhausted T cell"]])

@test_throws ArgumentError plot(run(Trial(1)))

plotbycelltype(sampling_from_import; include_cell_types="fast T cell", exclude_cell_types="fast T cell")