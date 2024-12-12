using Statistics

function averageSubstrate(snapshot::PhysiCellSnapshot, substrate_names::Vector{String}=String[])
    loadSubstrates!(snapshot, substrate_names)
    data = Dict{String, Real}()
    weights = snapshot.substrates[!, :volume]
    use_weights = length(unique(weights)) != 1
    if use_weights
        total_weight = sum(weights)
        mean_fn = x -> (x .* weights |> sum) / total_weight
    else
        mean_fn = mean
    end
    for substrate_name in substrate_names
        data[substrate_name] = mean_fn(snapshot.substrates[!, substrate_name])
    end
    return data
end

struct AverageSubstrateTimeSeries
    folder::String
    time::Vector{Real}
    substrate_concentrations::Dict{String, Vector{Real}}
end

function AverageSubstrateTimeSeries(sequence::PhysiCellSequence)
    folder = sequence.folder
    time = [snapshot.time for snapshot in sequence.snapshots]
    substrate_concentrations = Dict{String, Vector{Real}}()
    substrate_names = getSubstrateNames(sequence)
    for substrate_name in substrate_names
        substrate_concentrations[substrate_name] = zeros(Float64, length(time))
    end
    for (i, snapshot) in enumerate(sequence.snapshots)
        snapshot_substrate_concentrations = averageSubstrate(snapshot, substrate_names)
        for substrate_name in keys(snapshot_substrate_concentrations)
            substrate_concentrations[substrate_name][i] = snapshot_substrate_concentrations[substrate_name]
        end
    end
    return AverageSubstrateTimeSeries(folder, time, substrate_concentrations)
end

function AverageSubstrateTimeSeries(folder::String)
    return PhysiCellSequence(folder; include_substrates=true) |> x -> AverageSubstrateTimeSeries(x)
end

function AverageSubstrateTimeSeries(simulation_id::Integer)
    print("Computing average substrate time series for Simulation $simulation_id...")
    simulation_folder = outputFolder("simulation", simulation_id)
    path_to_summary = joinpath(simulation_folder, "summary")
    path_to_file = joinpath(path_to_summary, "average_substrate_time_series.csv")
    if isfile(path_to_file)
        df = CSV.read(path_to_file, DataFrame)
        asts = AverageSubstrateTimeSeries(simulation_folder, df.time, Dict{String, Vector{Real}}(name => df[!, Symbol(name)] for name in names(df) if name != "time"))
    else
        mkpath(path_to_summary)
        asts = joinpath(simulation_folder, "output") |> x -> AverageSubstrateTimeSeries(x)
        df = DataFrame(time=asts.time)
        for (name, concentrations) in pairs(asts.substrate_concentrations)
            df[!, Symbol(name)] = concentrations
        end
        CSV.write(path_to_file, df)
    end
    println("done.")
    return asts
end

function averageExtracellularSubstrate(snapshot::PhysiCellSnapshot; cell_type_to_name_dict::Dict{Int, String}=Dict{Int, String}(), substrate_names::Vector{String}=String[], include_dead::Bool=false)
    loadCells!(snapshot, cell_type_to_name_dict)
    loadSubstrates!(snapshot, substrate_names)
    loadMesh!(snapshot)
    cells = snapshot.cells
    substrates = snapshot.substrates
    mesh = snapshot.mesh

    aes = Dict{String, Dict{String, Real}}() # aes[cell_type_name][substrate_name] = average 
    cells_to_keep = include_dead ? deepcopy(cells) : cells[.!cells.dead, :]
    for cell_type_name in values(cell_type_to_name_dict)
        cell_type_cells = cells_to_keep[cells_to_keep.cell_type_name .== cell_type_name, :]

        voxel_inds = computeVoxelIndices(cell_type_cells, mesh)
        aes[cell_type_name] = Dict{String, Real}()
        for substrate_name in substrate_names
            aes[cell_type_name][substrate_name] = substrates[voxel_inds, substrate_name] |> mean
        end
    end
    return aes
end

function computeVoxelSubscripts(cells::DataFrame, mesh::Dict{String, Vector{Float64}})
    voxel_subs = Vector{Tuple{Int, Int, Int}}()
    x, y, z = cells[!, [:position_1, :position_2, :position_3]] |> eachcol

    nearest_index(c, v) = (c .- v[1]) / (v[2] - v[1]) .|> round .|> Int .|> x -> x.+1
    is = length(mesh["x"]) == 1 ? fill(1, (length(x),)) : nearest_index(x, mesh["x"])
    js = length(mesh["y"]) == 1 ? fill(1, (length(x),)) : nearest_index(y, mesh["y"])
    ks = length(mesh["z"]) == 1 ? fill(1, (length(x),)) : nearest_index(z, mesh["z"])
    voxel_subs = [(i, j, k) for (i, j, k) in zip(is, js, ks)]
    return voxel_subs
end

function computeVoxelIndices(cells::DataFrame, mesh::Dict{String, Vector{Float64}})
    voxel_subs = computeVoxelSubscripts(cells, mesh)
    nx, ny = length(mesh["x"]), length(mesh["y"])
    voxel_inds = [i + nx * (j-1 + ny * (k-1)) for (i, j, k) in voxel_subs]
    return voxel_inds
end

struct ExtracellularSubstrateTimeSeries
    folder::String
    time::Vector{Real}
    data::Dict{String, Dict{String, Vector{Real}}}
end

function ExtracellularSubstrateTimeSeries(sequence::PhysiCellSequence; include_dead::Bool=false)
    folder = sequence.folder
    time = [snapshot.time for snapshot in sequence.snapshots]
    data = Dict{String, Dict{String, Vector{Real}}}()
    cell_type_to_name_dict = sequence.cell_type_to_name_dict
    getCellTypeToNameDict!(cell_type_to_name_dict, sequence.folder)
    substrate_names = sequence.substrate_names
    getSubstrateNames!(substrate_names, sequence.folder)
    for (i, snapshot) in enumerate(sequence.snapshots)
        snapshot_data = averageExtracellularSubstrate(snapshot; cell_type_to_name_dict=cell_type_to_name_dict, substrate_names=substrate_names, include_dead=include_dead)
        for cell_type_name in keys(snapshot_data)
            if !(cell_type_name in keys(data))
                data[cell_type_name] = Dict{String, Vector{Real}}()
            end
            for substrate_name in keys(snapshot_data[cell_type_name])
                if !(substrate_name in keys(data[cell_type_name]))
                    data[cell_type_name][substrate_name] = zeros(Float64, length(time))
                end
                data[cell_type_name][substrate_name][i] = snapshot_data[cell_type_name][substrate_name]
            end
        end
    end
    return ExtracellularSubstrateTimeSeries(folder, time, data)
end

function ExtracellularSubstrateTimeSeries(folder::String; include_dead::Bool=false)
    return PhysiCellSequence(folder; include_cells=true, include_substrates=true, include_mesh=true) |> x -> ExtracellularSubstrateTimeSeries(x; include_dead=include_dead)
end

function ExtracellularSubstrateTimeSeries(simulation_id::Integer; include_dead::Bool=false)
    print("Computing extracellular substrate time series for Simulation $simulation_id...")
    simulation_folder = outputFolder("simulation", simulation_id)
    path_to_summary = joinpath(simulation_folder, "summary")
    path_to_file = joinpath(path_to_summary, "extracellular_substrate_time_series$(include_dead ? "_include_dead" : "").csv")
    if isfile(path_to_file)
        df = CSV.read(path_to_file, DataFrame)
        data = Dict{String, Dict{String, Vector{Real}}}()
        for name in names(df)
            if name == "time"
                continue
            end
            cell_type_name, substrate_name = split(name, " AND ")
            if !(cell_type_name in keys(data))
                data[cell_type_name] = Dict{String, Vector{Real}}()
            end
            data[cell_type_name][substrate_name] = df[!, name]
        end
        ests = ExtracellularSubstrateTimeSeries(simulation_folder, df.time, data)
    else
        mkpath(path_to_summary)
        ests = joinpath(simulation_folder, "output") |> x -> ExtracellularSubstrateTimeSeries(x; include_dead=include_dead)
        df = DataFrame(time=ests.time)
        for (cell_type_name, data) in pairs(ests.data)
            for (substrate_name, concentrations) in pairs(data)
                df[!, Symbol(cell_type_name * " AND " * substrate_name)] = concentrations
            end
        end
        CSV.write(path_to_file, df)
    end
    println("done.")
    return ests
end