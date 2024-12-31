using Plots
filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

plot(Simulation(1))
plot(Sampling(1))

plotbycelltype(Simulation(1))
plotbycelltype(Sampling(1))
plotbycelltype(Sampling(1), "default")

# misc tests
out = Monad(1; n_replicates=3) |> run
plot(out.trial)
plotbycelltype(out.trial)
