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
plotbycelltype(Sampling(1), "default")

# misc tests
out = Monad(1; n_replicates=3) |> run
MonadPopulationTimeSeries(1)
plot(out.trial)
plotbycelltype(out.trial)
