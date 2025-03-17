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

"""
    AverageSubstrateTimeSeries

A struct to hold the average substrate concentrations over time for a PhysiCell simulation.

# Fields
- `simulation_id::Int`: The ID of the PhysiCell simulation.
- `time::Vector{Real}`: The time points at which the snapshots were taken.
- `substrate_concentrations::Dict{String, Vector{Real}}`: A dictionary mapping substrate names to vectors of their average concentrations over time.

# Example
```julia
asts = AverageSubstrateTimeSeries(1) # Load average substrate time series for Simulation 1
asts.time # Get the time points
asts["time"] # alternative way to get the time points
asts["oxygen"] # Get the oxygen concentration over time
"""
struct AverageSubstrateTimeSeries
    simulation_id::Int
    time::Vector{Real}
    substrate_concentrations::Dict{String, Vector{Real}}
end

function Base.getindex(asts::AverageSubstrateTimeSeries, name::String)
    if name in keys(asts.substrate_concentrations)
        return asts.substrate_concentrations[name]
    elseif name == "time"
        return asts.time
    else
        throw(ArgumentError("Invalid substrate name: $name"))
    end
end

function AverageSubstrateTimeSeries(sequence::PhysiCellSequence)
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
    return AverageSubstrateTimeSeries(sequence.simulation_id, time, substrate_concentrations)
end

function AverageSubstrateTimeSeries(simulation_id::Integer)
    print("Computing average substrate time series for Simulation $simulation_id...")
    simulation_folder = trialFolder("simulation", simulation_id)
    path_to_summary = joinpath(simulation_folder, "summary")
    path_to_file = joinpath(path_to_summary, "average_substrate_time_series.csv")
    if isfile(path_to_file)
        df = CSV.read(path_to_file, DataFrame)
        asts = AverageSubstrateTimeSeries(simulation_id, df.time, Dict{String, Vector{Real}}(name => df[!, Symbol(name)] for name in names(df) if name != "time"))
    else
        sequence = PhysiCellSequence(simulation_id; include_cells=false, include_substrates=true)
        if ismissing(sequence)
            return missing
        end
        mkpath(path_to_summary)
        asts = AverageSubstrateTimeSeries(sequence)
        df = DataFrame(time=asts.time)
        for (name, concentrations) in pairs(asts.substrate_concentrations)
            df[!, Symbol(name)] = concentrations
        end
        CSV.write(path_to_file, df)
    end
    println("done.")
    return asts
end

AverageSubstrateTimeSeries(simulation::Simulation) = AverageSubstrateTimeSeries(simulation.id)

function averageExtracellularSubstrate(snapshot::PhysiCellSnapshot; cell_type_to_name_dict::Dict{Int, String}=Dict{Int, String}(), substrate_names::Vector{String}=String[], include_dead::Bool=false, labels::Vector{String}=String[])
    if ismissing(loadCells!(snapshot, cell_type_to_name_dict, labels))
        return missing
    end
    loadSubstrates!(snapshot, substrate_names)
    loadMesh!(snapshot)
    cells = snapshot.cells
    substrates = snapshot.substrates
    mesh = snapshot.mesh

    aes = Dict{String, Dict{String, Real}}()
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

"""
    ExtracellularSubstrateTimeSeries

A struct to hold the mean extracellular substrate concentrations per cell type over time for a PhysiCell simulation.

# Fields
- `simulation_id::Int`: The ID of the PhysiCell simulation.
- `time::Vector{Real}`: The time points at which the snapshots were taken.
- `data::Dict{String, Dict{String, Vector{Real}}}`: A dictionary mapping cell type names to dictionaries mapping substrate names to vectors of their average concentrations over time.

# Example
```julia
ests = ExtracellularSubstrateTimeSeries(1) # Load extracellular substrate time series for Simulation 1
ests.time # Get the time points
ests["cancer"]["oxygen"] # Get the oxygen concentration over time for the cancer cell type

ests = ExtracellularSubstrateTimeSeries(simulation; include_dead=true) # Load extracellular substrate time series for a Simulation object, including dead cells
ests["time"] # Alternate way to get the time points
ests["cd8"]["IFNg"] # Get the interferon gamma concentration over time for the CD8 cell type
```
"""
struct ExtracellularSubstrateTimeSeries
    simulation_id::Int
    time::Vector{Real}
    data::Dict{String,Dict{String,Vector{Real}}}
end

function Base.getindex(ests::ExtracellularSubstrateTimeSeries, name::String)
    if name in keys(ests.data)
        return ests.data[name]
    elseif name == "time"
        return ests.time
    else
        throw(ArgumentError("Invalid cell type name: $name"))
    end
end

function ExtracellularSubstrateTimeSeries(sequence::PhysiCellSequence; include_dead::Bool=false)
    time = [snapshot.time for snapshot in sequence.snapshots]
    data = Dict{String, Dict{String, Vector{Real}}}()
    cell_type_to_name_dict = sequence.cell_type_to_name_dict
    substrate_names = getSubstrateNames(sequence)
    for (i, snapshot) in enumerate(sequence.snapshots)
        snapshot_data = averageExtracellularSubstrate(snapshot; cell_type_to_name_dict=cell_type_to_name_dict, substrate_names=substrate_names, include_dead=include_dead, labels=sequence.labels)
        for cell_type_name in keys(snapshot_data)
            if !haskey(data, cell_type_name)
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
    return ExtracellularSubstrateTimeSeries(sequence.simulation_id, time, data)
end

function ExtracellularSubstrateTimeSeries(simulation_id::Integer; include_dead::Bool=false)
    print("Computing extracellular substrate time series for Simulation $simulation_id...")
    simulation_folder = trialFolder("simulation", simulation_id)
    path_to_summary = joinpath(simulation_folder, "summary")
    path_to_file = joinpath(path_to_summary, "extracellular_substrate_time_series$(include_dead ? "_include_dead" : "").csv")
    if isfile(path_to_file)
        df = CSV.read(path_to_file, DataFrame)
        data = Dict{String,Dict{String,Vector{Real}}}()
        for name in names(df)
            if name == "time"
                continue
            end
            cell_type_name, substrate_name = split(name, " AND ")
            if !haskey(data, cell_type_name)
                data[cell_type_name] = Dict{String, Vector{Real}}()
            end
            data[cell_type_name][substrate_name] = df[!, name]
        end
        ests = ExtracellularSubstrateTimeSeries(simulation_id, df.time, data)
    else
        sequence = PhysiCellSequence(simulation_id; include_cells=true, include_substrates=true, include_mesh=true)
        if ismissing(sequence)
            return missing
        end
        mkpath(path_to_summary)
        ests = ExtracellularSubstrateTimeSeries(sequence; include_dead=include_dead)
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

ExtracellularSubstrateTimeSeries(simulation::Simulation; kwargs...) = ExtracellularSubstrateTimeSeries(simulation.id; kwargs...)