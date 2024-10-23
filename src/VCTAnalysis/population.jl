using RecipesBase

export finalPopulationCount, populationTimeSeries

function populationCount(snapshot::PhysiCellSnapshot; include_dead::Bool=false, cell_type_to_name_dict::Dict{Int, String}=Dict{Int, String}())
    data = Dict{String, Int}()
    if include_dead
        cell_df = snapshot.cells
    else
        cell_df = @view snapshot.cells[snapshot.cells.dead .== false, :]
    end
    if isempty(cell_type_to_name_dict)
        cell_type_to_name_dict = getCellTypeToNameDict(snapshot.folder)
    end
    cell_type_names = values(cell_type_to_name_dict)
    for cell_type_name in cell_type_names
        data[cell_type_name] = count(x -> x == cell_type_name, cell_df.cell_type_name)
    end
    return data
end

abstract type AbstractPopulationTimeSeries end

struct SimulationPopulationTimeSeries <: AbstractPopulationTimeSeries
    folder::String
    time::Vector{Real}
    cell_count::Dict{String, Vector{Integer}}
end

function SimulationPopulationTimeSeries(sequence::PhysiCellSequence; include_dead::Bool=false)
    folder = sequence.folder
    time = [snapshot.time for snapshot in sequence.snapshots]
    cell_count = Dict{String, Vector{Integer}}()
    for (i, snapshot) in enumerate(sequence.snapshots)
        population_count = populationCount(snapshot; include_dead=include_dead, cell_type_to_name_dict=sequence.cell_type_to_name_dict)
        for (ID, count) in pairs(population_count)
            if !(string(ID) in keys(cell_count))
                cell_count[ID] = zeros(Int, length(time))
            end
            cell_count[ID][i] = count
        end
    end
    return SimulationPopulationTimeSeries(folder, time, cell_count)
end

function SimulationPopulationTimeSeries(folder::String; include_dead::Bool=false)
    return PhysiCellSequence(folder) |> x -> SimulationPopulationTimeSeries(x; include_dead=include_dead)
end

function SimulationPopulationTimeSeries(simulation_id::Int; include_dead::Bool=false)
    # return "$(data_dir)/outputs/simulations/$(simulation_id)/output" |> x -> SimulationPopulationTimeSeries(x; include_dead=include_dead)
    df = "$(data_dir)/outputs/simulations/$(simulation_id)/output" |> x -> SimulationPopulationTimeSeries(x; include_dead=include_dead)
    println("Finished SimulationPopulationTimeSeries for simulation_id: $simulation_id")
    return df
end

function finalPopulationCount(folder::String; include_dead::Bool=false)
    final_snapshot = PhysiCellSnapshot(folder, :final)
    return populationCount(final_snapshot; include_dead=include_dead)
end

function finalPopulationCount(simulation_id::Int; include_dead::Bool=false)
    return "$(data_dir)/outputs/simulations/$(simulation_id)/output" |> x -> finalPopulationCount(x; include_dead=include_dead)
end

struct MonadPopulationTimeSeries <: AbstractPopulationTimeSeries
    monad_id::Int
    monad_length::Int
    time::Vector{Real}
    cell_count_arrays::Dict{String, Array{Integer,2}}
    cell_count_means::Dict{String, Vector{Real}}
    cell_count_sd::Dict{String, Vector{Real}}
end

function MonadPopulationTimeSeries(monad::Monad; include_dead::Bool=false)
    simulation_ids = getSimulationIDs(monad)
    monad_length = length(simulation_ids)
    time = Real[]
    df_sim = Dict()
    cell_count_arrays = Dict{String, Array{Int,2}}()
    for (i, simulation_id) in enumerate(simulation_ids)
        df_sim = SimulationPopulationTimeSeries(simulation_id; include_dead=include_dead)
        if isempty(time)
            time = df_sim.time
        else
            @assert time == df_sim.time "Simulations $(simulation_ids[1]) and $(simulation_id) in monad $(monad.id) have different times in their time series."
        end
        for name in names(df_sim)
            if name == :time
                continue
            end
            key = string(name)
            if !(key in keys(cell_count_arrays))
                cell_count_arrays[key] = zeros(Int, length(time), monad_length)
            end
            cell_count_arrays[key][:,i] = cell_count_arrays[key]
        end
    end
    cell_count_means = Dict{String, Vector{Real}}()
    cell_count_sd = Dict{String, Vector{Real}}()
    for (key, array) in cell_count_arrays
        cell_count_means[key] = mean(array, dims=2) |> vec
        cell_count_sd[key] = std(array, dims=2) |> vec
    end
    return MonadPopulationTimeSeries(monad.id, monad_length, time, cell_count_arrays, cell_count_means, cell_count_sd)
end

function populationTimeSeries(M::AbstractMonad; include_dead::Bool=false)
    if M isa Monad
        return MonadPopulationTimeSeries(M; include_dead=include_dead)
    else
        return SimulationPopulationTimeSeries(M; include_dead=include_dead)
    end
end

# plot recipes

getMeanCounts(s::SimulationPopulationTimeSeries) = s.cell_count
getMeanCounts(m::MonadPopulationTimeSeries) = m.cell_count_means

@recipe function f(M::AbstractMonad)
    pts = populationTimeSeries(M)
    for (name, counts) in pairs(getMeanCounts(pts))
        @series begin
            label --> name
            x = pts.time
            y = counts
            if typeof(M) == Monad && length(M.simulation_ids) > 1
                ribbon := pts.cell_count_std[name]
            end
            x, y
        end
    end
end