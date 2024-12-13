using RecipesBase

export finalPopulationCount, populationTimeSeries

function populationCount(snapshot::PhysiCellSnapshot; include_dead::Bool=false, cell_type_to_name_dict::Dict{Int, String}=Dict{Int, String}())
    data = Dict{String, Int}()
    if include_dead
        cell_df = snapshot.cells
    else
        cell_df = @view snapshot.cells[snapshot.cells.dead .== false, :]
    end
    getCellTypeToNameDict!(cell_type_to_name_dict, snapshot)
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
    return PhysiCellSequence(folder; include_cells=true) |> x -> SimulationPopulationTimeSeries(x; include_dead=include_dead)
end

function SimulationPopulationTimeSeries(simulation_id::Integer; include_dead::Bool=false)
    print("Computing SimulationPopulationTimeSeries for Simulation $simulation_id...")
    simulation_folder = outputFolder("simulation", simulation_id)
    path_to_summary = joinpath(simulation_folder, "summary")
    path_to_file = joinpath(path_to_summary, "population_time_series$(include_dead ? "_include_dead" : "").csv")
    if isfile(path_to_file)
        df = CSV.read(path_to_file, DataFrame)
        spts = SimulationPopulationTimeSeries(simulation_folder, df.time, Dict{String, Vector{Integer}}(name => df[!, Symbol(name)] for name in names(df) if name != "time"))
    else
        mkpath(path_to_summary)
        spts = joinpath(simulation_folder, "output") |> x -> SimulationPopulationTimeSeries(x; include_dead=include_dead)
        df = DataFrame(time=spts.time)
        for (name, counts) in pairs(spts.cell_count)
            df[!, Symbol(name)] = counts
        end
        CSV.write(path_to_file, df)
    end
    println("done.")
    return spts
end

SimulationPopulationTimeSeries(simulation::Simulation; include_dead::Bool=false) = SimulationPopulationTimeSeries(simulation.id; include_dead=include_dead)

function finalPopulationCount(folder::String; include_dead::Bool=false)
    final_snapshot = PhysiCellSnapshot(folder, :final; include_cells=true)
    return populationCount(final_snapshot; include_dead=include_dead)
end

function finalPopulationCount(simulation_id::Int; include_dead::Bool=false)
    return joinpath(outputFolder("simulation", simulation_id), "output") |> x -> finalPopulationCount(x; include_dead=include_dead)
end

struct MonadPopulationTimeSeries <: AbstractPopulationTimeSeries
    monad_id::Int
    monad_length::Int
    time::Vector{Real}
    cell_count_arrays::Dict{String, Array{Integer,2}}
    cell_count_means::Dict{String, Vector{Real}}
    cell_count_stds::Dict{String, Vector{Real}}
end

function MonadPopulationTimeSeries(monad::Monad; include_dead::Bool=false)
    simulation_ids = getSimulationIDs(monad)
    monad_length = length(simulation_ids)
    time = Real[]
    cell_count_arrays = Dict{String, Array{Int,2}}()
    for (i, simulation_id) in enumerate(simulation_ids)
        spts = SimulationPopulationTimeSeries(simulation_id; include_dead=include_dead)
        if isempty(time)
            time = spts.time
        else
            @assert time == spts.time "Simulations $(simulation_ids[1]) and $(simulation_id) in monad $(monad.id) have different times in their time series."
        end
        for (name, cell_count) in pairs(spts.cell_count)
            if !(name in keys(cell_count_arrays))
                cell_count_arrays[name] = zeros(Int, length(time), monad_length)
            end
            cell_count_arrays[name][:,i] = cell_count
        end
    end
    cell_count_means = Dict{String, Vector{Real}}()
    cell_count_stds = Dict{String, Vector{Real}}()
    for (name, array) in cell_count_arrays
        cell_count_means[name] = mean(array, dims=2) |> vec
        cell_count_stds[name] = std(array, dims=2) |> vec
    end
    return MonadPopulationTimeSeries(monad.id, monad_length, time, cell_count_arrays, cell_count_means, cell_count_stds)
end

function populationTimeSeries(M::AbstractMonad; include_dead::Bool=false)
    if M isa Simulation
        return SimulationPopulationTimeSeries(M; include_dead=include_dead)
    else
        return MonadPopulationTimeSeries(M; include_dead=include_dead)
    end
end

# plot recipes
getMeanCounts(s::SimulationPopulationTimeSeries) = s.cell_count
getMeanCounts(m::MonadPopulationTimeSeries) = m.cell_count_means

@recipe function f(M::AbstractMonad; include_dead=false, include_cell_types=:all, exclude_cell_types=String[])
    pts = populationTimeSeries(M; include_dead=include_dead)
    # allow for single string input for either of these
    include_cell_types = include_cell_types == :all ? :all : (include_cell_types isa String ? [include_cell_types] : include_cell_types)
    exclude_cell_types = exclude_cell_types isa String ? [exclude_cell_types] : exclude_cell_types
    for (name, counts) in pairs(getMeanCounts(pts))
        skip = include_cell_types != :all && !(name in include_cell_types) # skip this cell type as only a subset was requested and this was not in it
        skip |= name in exclude_cell_types # skip this cell type as it was requested to be excluded
        if skip
            continue 
        end
        @series begin
            label --> name
            x = pts.time
            y = counts
            if typeof(M) == Monad && length(M.simulation_ids) > 1
                ribbon := pts.cell_count_stds[name]
            end
            x, y
        end
    end
end

@recipe function f(sampling::Sampling; include_dead=false, include_cell_types=:all, exclude_cell_types=String[])
    df = pcvct.simulationsTable(sampling)
    monads = []
    title_tuples = []
    for monad_id in sampling.monad_ids
        monad = Monad(monad_id)
        push!(monads, monad)
        sim_id = monad.simulation_ids[1]
        row_ind = findfirst(df[!, :SimID] .== sim_id)
        row = df[row_ind, :]
        title_tuple = [row[name] for name in names(row) if !(name in ["SimID", "ConfigVarID", "RulesVarID"])]
        push!(title_tuples, title_tuple)
    end
    
    order = sortperm(title_tuples)
    title_tuples = title_tuples[order]
    monads = monads[order]

    layout  --> (length(monads), 1) # easy room for improvement here

    for (i, (monad, title_tuple)) in enumerate(zip(monads, title_tuples))
        @series begin
            title --> "(" * join(title_tuple, ", ") * ")"
            subplot := i
            legend := false
            include_dead --> include_dead
            include_cell_types --> include_cell_types
            exclude_cell_types --> exclude_cell_types
            monad
        end
    end
end

"""
    plotbycelltype(T::AbstractTrial, cell_types::Union{String, Vector{String}}=:all)

Plot the population time series of a trial by cell type.

Each cell type gets its own subplot.
Each monad gets its own series within each subplot.
"""
plotbycelltype

@userplot PlotByCellType

struct CellTypeInMonads
    time::Vector{Vector{Real}}
    cell_count_means::Vector{Vector{Real}}
    cell_count_stds::Vector{Vector{Real}}
end

@recipe function f(p::PlotByCellType)
    @assert typeof(p.args[1]) <: AbstractTrial "Expected first argument to be a subtype of AbstractTrial, got $(typeof(p.args[1]))."
    if length(p.args) == 1
        T = p.args[1]
        cell_types = :all
    elseif length(p.args) == 2
        T, cell_types = p.args
    else
        error("Expected 1 or 2 arguments, got $(length(p.args)).")
    end

    if T isa Simulation
        monads = [Monad(T)]
    else
        monads = Monad.(getMonadIDs(T))
    end

    monad_summary = Dict{Int,Any}()
    all_cell_types = Set()
    for monad in monads
        simulation_ids = getSimulationIDs(monad)
        monad_length = length(simulation_ids)
        time = Real[]
        cell_count_arrays = Dict{Any, Array{Int,2}}()
        for (i, simulation_id) in enumerate(simulation_ids)
            spts = SimulationPopulationTimeSeries(simulation_id)
            if isempty(time)
                time = spts.time
            else
                @assert time == spts.time "Simulations $(simulation_ids[1]) and $(simulation_id) in monad $(monad.id) have different times in their time series."
            end
            if cell_types == :all
                for (name, cell_count) in pairs(spts.cell_count)
                    if !(name in keys(cell_count_arrays))
                        cell_count_arrays[name] = zeros(Int, length(time), monad_length)
                    end
                    cell_count_arrays[name][:,i] = cell_count
                end
            else
                if cell_types isa String
                    cell_types = [cell_types]
                end
                for cell_type in cell_types
                    if cell_type isa String
                        cell_type = [cell_type]
                    end
                    if !(cell_type in keys(cell_count_arrays))
                        cell_count_arrays[cell_type] = zeros(Int, length(time), monad_length)
                    end
                    cell_count_arrays[cell_type][:,i] = sum([spts.cell_count[ct] for ct in cell_type])
                end
            end
        end
        cell_count_means = Dict{Any, Vector{Real}}()
        cell_count_stds = Dict{Any, Vector{Real}}()
        for (name, array) in cell_count_arrays
            cell_count_means[name] = mean(array, dims=2) |> vec
            cell_count_stds[name] = std(array, dims=2) |> vec
            push!(all_cell_types, name)
        end
        monad_summary[monad.id] = (time=time, cell_count_means=cell_count_means, cell_count_stds=cell_count_stds)
    end

    layout  --> (length(all_cell_types), 1) # easy room for improvement here

    for (i, cell_type) in enumerate(all_cell_types)
        @series begin
            title --> cell_type
            legend := false
            subplot := i
            x = [monad_summary[monad.id].time for monad in monads]
            y = [monad_summary[monad.id].cell_count_means[cell_type] for monad in monads]
            z = [monad_summary[monad.id].cell_count_stds[cell_type] for monad in monads]
            CellTypeInMonads(x, y, z)
        end
    end
end

@recipe function f(tc::CellTypeInMonads)
    for (x, y, z) in zip(tc.time, tc.cell_count_means, tc.cell_count_stds)
        @series begin
            ribbon := z
            x, y
        end
    end
end