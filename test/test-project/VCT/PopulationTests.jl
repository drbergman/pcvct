using Plots
filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

plot(Sampling(1))

plotbycelltype(Sampling(1))
plotbycelltype(Sampling(1), "default")