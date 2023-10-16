using SQLite, DataFrames

include("./VCT/VCTExtraction.jl")

home_dir = cd(pwd,homedir())
path_to_data_folder = home_dir * "/pdac-ecm/user_projects/sandbox/data"

db, = VCTExtraction.loadVCT(path_to_data_folder)

df = VCTExtraction.loadCellDataTimeSeries("position");
X = df.position
sim_ids = df.simulation_id
order = sortperm(sim_ids)
X = X[order]
sim_ids = sim_ids[order]

df = DBInterface.execute(db, "SELECT simulation_id,patient_id,cohort_id,variation_id FROM simulations;") |> DataFrame
sort!(df, :simulation_id)

Y = [X[df.variation_id.==i] for i in 0:2]

function totalDistance(P)
    d = 0
    for i in 2:length(P)
        d = d + sqrt(sum((P[i] .- P[i-1]).^2))
    end
    return d

end

distances = [[totalDistance(x) for x in y] for y in Y]

col = Dict(0=>:blue, 1=>:green, 2=>:red)

using Plots
pl = scatter()
for i in eachindex(X)
    x = [X[i][j][1] for j in eachindex(X[i])]
    y = [X[i][j][2] for j in eachindex(X[i])]
    scatter!(pl,x.+randn(length(x)),y.+randn(length(x)), legend = false, color = col[df.variation_id[i]])
end
pl
savefig("cell_paths.png")

pl = histogram()
for d in distances
    histogram!(pl,d)
end
pl


using KernelDensity
pl = plot()
max_dist = maximum([maximum(d) for d in distances])
max_dist *= 2.
U = []
for d in distances
    temp = kde_lscv(d, boundary=(-10,max_dist))
    push!(U,temp)
    plot!(pl,temp.x,temp.density)
end
pl

A = [sum(U[i].density) * (U[i].x[2]-U[i].x[1]) for i in 1:3]