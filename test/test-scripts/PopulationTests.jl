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
mpts = pcvct.MonadPopulationTimeSeries(1)
plot(out)
plot(out.trial)
plotbycelltype(out)
plotbycelltype(out.trial)

all_cell_types = ["cancer", "immune", "epi", "mes"]
pcvct.processIncludeCellTypes(["cancer", "immune"], all_cell_types)
pcvct.processIncludeCellTypes(["epi", "mes", ["epi", "mes"]], all_cell_types)
@test_throws ArgumentError pcvct.processIncludeCellTypes(:mes, all_cell_types)
@test_throws ArgumentError pcvct.processIncludeCellTypes(1, all_cell_types)

pcvct.processExcludeCellTypes("cancer")
@test_throws ArgumentError pcvct.processExcludeCellTypes(:mes)
plot(out; include_cell_types="default", exclude_cell_types="default")

plot(sampling_from_import; include_cell_types=[["fast T cell", "slow T cell", "effector T cell", "exhausted T cell"]])

@test_throws ArgumentError plot(run(Trial(1)))

plotbycelltype(sampling_from_import; include_cell_types="fast T cell", exclude_cell_types="fast T cell")

@test ismissing(PhysiCellSnapshot(pruned_simulation_id, :initial))
@test ismissing(finalPopulationCount(pruned_simulation_id))

spts = pcvct.SimulationPopulationTimeSeries(1)
Base.show(stdout, MIME"text/plain"(), spts)
Base.show(stdout, MIME"text/plain"(), mpts)