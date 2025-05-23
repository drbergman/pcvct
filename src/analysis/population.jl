using RecipesBase

export finalPopulationCount

"""
    populationCount(snapshot, cell_type_to_name_dict::Dict{Int,String}=Dict{Int,String}(), labels::Vector{String}=String[]; include_dead::Bool=false)

Return the population count of a snapshot as a dictionary with cell type names as keys and their counts as values.

If the snapshot is missing, it will return missing.
This helps in cases where the files have been deleted, for example by pruning.

# Arguments
- `snapshot::PhysiCellSnapshot`: The snapshot to count the cells in.
- `cell_type_to_name_dict::Dict{Int,String}`: A dictionary mapping cell type IDs to names (default is an empty dictionary). If not provided, it is read from the snapshot files.
- `labels::Vector{String}`: The labels to identify the cell data. If not provided, it is read from the snapshot files.

# Keyword Arguments
- `include_dead::Bool`: Whether to include dead cells in the count. Default is `false`.
"""
function populationCount(snapshot::PhysiCellSnapshot, cell_type_to_name_dict::Dict{Int,String}=Dict{Int,String}(), labels::Vector{String}=String[]; include_dead::Bool=false)
    loadCells!(snapshot, cell_type_to_name_dict, labels)
    data = Dict{String, Int}()
    if include_dead
        cell_df = snapshot.cells
    else
        cell_df = @view snapshot.cells[snapshot.cells.dead .== false, :]
    end
    if isempty(cell_type_to_name_dict)
        cell_type_to_name_dict = getCellTypeToNameDict(snapshot)
    end
    cell_type_names = values(cell_type_to_name_dict)
    for cell_type_name in cell_type_names
        data[cell_type_name] = count(x -> x == cell_type_name, cell_df.cell_type_name)
    end
    return data
end

populationCount(::Missing, args...; kwargs...) = missing

"""
    AbstractPopulationTimeSeries

Abstract type representing a population time series for either a simulation or a monad.
"""
abstract type AbstractPopulationTimeSeries end

"""
    SimulationPopulationTimeSeries <: AbstractPopulationTimeSeries

Holds the data for a simulation's population time series.

If constructed using a `Simulation` or an `Integer` (representing a simulation ID), it will save the time series inside the `simulations/simulation_id/summary/` folder.
It will also look for previously computed time series there to avoid recomputing them.

# Examples
```
spts = SimulationPopulationTimeSeries(1) # first checks if the population time series is already computed and if not, computes it
spts = SimulationPopulationTimeSeries(Simulation(1)) # first checks if the population time series is already computed and if not, computes it
spts = SimulationPopulationTimeSeries(1; include_dead=true) # similar, but counts dead cells as well; the file name has \"_include_dead\" appended
```

# Fields
- `simulation_id::Int`: The ID of the simulation.
- `time::Vector{Real}`: The time points of the population time series.
- `cell_count::Dict{String, Vector{Integer}}`: A dictionary where keys are cell type names and values are vectors of cell counts over time.
"""
struct SimulationPopulationTimeSeries <: AbstractPopulationTimeSeries
    simulation_id::Int
    time::Vector{Real}
    cell_count::Dict{String, Vector{Integer}}
end

function SimulationPopulationTimeSeries(sequence::PhysiCellSequence; include_dead::Bool=false)
    time = [snapshot.time for snapshot in sequence.snapshots]
    cell_count = Dict{String, Vector{Integer}}()
    for (i, snapshot) in enumerate(sequence.snapshots)
        population_count = populationCount(snapshot, sequence.cell_type_to_name_dict, sequence.labels; include_dead=include_dead)
        ismissing(population_count) && continue #! skip if the population count is missing (could happen if the snapshot is empty, which would happen if, e.g., the xml is missing)
        for (ID, count) in pairs(population_count)
            if !(string(ID) in keys(cell_count))
                cell_count[ID] = zeros(Int, length(time))
            end
            cell_count[ID][i] = count
        end
    end
    return SimulationPopulationTimeSeries(sequence.simulation_id, time, cell_count)
end

function SimulationPopulationTimeSeries(simulation_id::Integer; include_dead::Bool=false, verbose::Bool=true)
    verbose ? print("Computing SimulationPopulationTimeSeries for Simulation $simulation_id...") : nothing
    simulation_folder = trialFolder(Simulation, simulation_id)
    path_to_summary = joinpath(simulation_folder, "summary")
    path_to_file = joinpath(path_to_summary, "population_time_series$(include_dead ? "_include_dead" : "").csv")
    if isfile(path_to_file)
        df = CSV.read(path_to_file, DataFrame)
        spts = SimulationPopulationTimeSeries(simulation_id, df.time, Dict{String, Vector{Integer}}(name => df[!, Symbol(name)] for name in names(df) if name != "time"))
    else
        sequence = PhysiCellSequence(simulation_id; include_cells=true)
        if ismissing(sequence)
            return missing
        end
        mkpath(path_to_summary)
        spts = SimulationPopulationTimeSeries(sequence; include_dead=include_dead)
        df = DataFrame(time=spts.time)
        for (name, counts) in pairs(spts.cell_count)
            df[!, Symbol(name)] = counts
        end
        CSV.write(path_to_file, df)
    end
    verbose ? println("done.") : nothing
    return spts
end

SimulationPopulationTimeSeries(simulation::Simulation; kwargs...) = SimulationPopulationTimeSeries(simulation.id; kwargs...)

function Base.getindex(spts::SimulationPopulationTimeSeries, cell_type::String)
    if cell_type in keys(spts.cell_count)
        return spts.cell_count[cell_type]
    elseif cell_type == "time"
        return spts.time
    else
        throw(ArgumentError("Cell type $cell_type not found in the population time series."))
    end
end

function Base.show(io::IO, ::MIME"text/plain", spts::SimulationPopulationTimeSeries)
    println(io, "SimulationPopulationTimeSeries for Simulation $(spts.simulation_id):")
    println(io, "  Time: $(formatTimeRange(spts.time))")
    println(io, "  Cell types: $(join(keys(spts.cell_count), ", "))")
end

"""
    formatTimeRange(v::Vector{Real})

Format a vector of time points into a string representation.

Used only for printing certain classes to the console.
"""
function formatTimeRange(v)
    @assert !isempty(v) "Vector is empty."
    if length(v) == 1
        return "$(v[1])"
    end
    #! Calculate the step size
    step = v[2] - v[1]

    #! Check if all consecutive differences are equal to the step size
    if all(diff(v) .≈ step)
        return "$(v[1]):$step:$(v[end])"
    else
        return "$(v[1])-$(v[end]) (not equally spaced)"
    end
end

"""
    finalPopulationCount(simulation::Simulation[; include_dead::Bool=false])

Return the final population count of a simulation as a dictionary with cell type names as keys and their counts as values.

Also works with the simulation ID:
```
fpc = finalPopulationCount(1)
```

# Example
```
fpc = finalPopulationCount(simulation)
final_default_count = fpc["default"]
```
"""
function finalPopulationCount end

function finalPopulationCount(simulation_id::Int; include_dead::Bool=false)
    final_snapshot = PhysiCellSnapshot(simulation_id, :final; include_cells=true)
    return populationCount(final_snapshot; include_dead=include_dead)
end

function finalPopulationCount(simulation::Simulation; include_dead::Bool=false)
    return finalPopulationCount(simulation.id; include_dead=include_dead)
end

"""
    MonadPopulationTimeSeries <: AbstractPopulationTimeSeries

Holds the data for a monad's population time series.

Note: unlike `SimulationPopulationTimeSeries`, this type does not save the data to a file.

# Examples

```
mpts = MonadPopulationTimeSeries(1)
mpts = MonadPopulationTimeSeries(monad(1))
```

# Fields
- `monad_id::Int`: The ID of the monad.
- `monad_length::Int`: The number of simulations in the monad.
- `time::Vector{Real}`: The time points of the population time series.
- `cell_count::Dict{String, NamedTuple}`: A dictionary where keys are cell type names and values are NamedTuples with fields `:counts`, `:mean`, and `:std`.
"""
struct MonadPopulationTimeSeries <: AbstractPopulationTimeSeries
    monad_id::Int
    monad_length::Int
    time::Vector{Real}
    cell_count::Dict{String,NamedTuple}
end

function MonadPopulationTimeSeries(monad::Monad; include_dead::Bool=false)
    simulation_ids = getSimulationIDs(monad)
    monad_length = length(simulation_ids)
    time = Real[]
    cell_count = Dict{String, NamedTuple}()
    _counts = Dict{String,Any}()
    for (i, simulation_id) in enumerate(simulation_ids)
        spts = SimulationPopulationTimeSeries(simulation_id; include_dead=include_dead)
        if ismissing(spts)
            continue
        end
        if isempty(time)
            time = spts.time
        else
            @assert time == spts.time "Simulations $(simulation_ids[1]) and $(simulation_id) in monad $(monad.id) have different times in their time series."
        end
        for (name, cell_count) in pairs(spts.cell_count)
            if !haskey(_counts, name)
                _counts[name] = [cell_count]
            else
                push!(_counts[name], cell_count)
            end
        end
    end
    _mean = Dict{String, Vector{Real}}()
    _std = Dict{String, Vector{Real}}()
    for (name, vectors) in _counts
        _array = reduce(hcat, vectors)
        _mean[name] = mean(_array, dims=2) |> vec
        _std[name] = std(_array, dims=2) |> vec
        cell_count[name] = [:counts => _array, :mean => _mean[name], :std => _std[name]] |> NamedTuple
    end
    return MonadPopulationTimeSeries(monad.id, monad_length, time, cell_count)
end

MonadPopulationTimeSeries(monad_id::Integer; include_dead::Bool=false) = MonadPopulationTimeSeries(Monad(monad_id); include_dead=include_dead)

function Base.getindex(mpts::MonadPopulationTimeSeries, cell_type::String)
    if cell_type in keys(mpts.cell_count)
        return mpts.cell_count[cell_type]
    elseif cell_type == "time"
        return mpts.time
    else
        throw(ArgumentError("Cell type $cell_type not found in the population time series."))
    end
end

Base.keys(apts::AbstractPopulationTimeSeries; exclude_time::Bool=false) = exclude_time ? keys(apts.cell_count) : ["time"; keys(apts.cell_count) |> collect]

function Base.show(io::IO, ::MIME"text/plain", mpts::MonadPopulationTimeSeries)
    println(io, "MonadPopulationTimeSeries for Monad $(mpts.monad_id):")
    printSimulationIDs(io, Monad(mpts.monad_id))
    println(io, "  Time: $(formatTimeRange(mpts.time))")
    println(io, "  Cell types: $(join(keys(mpts.cell_count), ", "))")
end

"""
    populationTimeSeries(M::AbstractMonad[; include_dead::Bool=false])

Return the population time series of a simulation or a monad.

See `SimulationPopulationTimeSeries` and `MonadPopulationTimeSeries` for more details.
"""
function populationTimeSeries(M::AbstractMonad; include_dead::Bool=false)
    if M isa Simulation
        return SimulationPopulationTimeSeries(M; include_dead=include_dead)
    else
        return MonadPopulationTimeSeries(M; include_dead=include_dead)
    end
end

#! plot recipes
"""
    getMeanCounts(apts::AbstractPopulationTimeSeries)

Return the mean counts of a population time series.
"""
getMeanCounts(s::SimulationPopulationTimeSeries) = s.cell_count
getMeanCounts(m::MonadPopulationTimeSeries) = [k => v.mean for (k, v) in pairs(m.cell_count)] |> Dict

@recipe function f(M::AbstractMonad; include_dead=false, include_cell_types=:all, exclude_cell_types=String[])
    pts = populationTimeSeries(M; include_dead=include_dead)
    #! allow for single string input for either of these
    include_cell_types = processIncludeCellTypes(include_cell_types, keys(pts; exclude_time=true) |> collect)
    exclude_cell_types = processExcludeCellTypes(exclude_cell_types)

    for k in include_cell_types
        if k isa String
            k = [k] #! standardize so that all are vectors
        end
        setdiff!(k, exclude_cell_types) #! remove any cell types that are to be excluded (also removes duplicates)
        if isempty(k)
            continue #! skip if all cell types were excluded
        end
        if length(k) == 1
            name = k[1]
            @series begin
                label --> name
                x = pts.time
                y = getMeanCounts(pts)[name]
                if length(getSimulationIDs(M)) > 1
                    ribbon := pts[name].std
                end
                x, y
            end
        else #! need to basically recalculate since we are combining multiple cell types
            simulation_ids = getSimulationIDs(M)
            sptss = [SimulationPopulationTimeSeries(simulation_id; include_dead=include_dead, verbose=false) for simulation_id in simulation_ids]
            filter!(!ismissing, sptss) #! remove any that failed to load
            sim_sums = [sum([spts[name] for name in k]) for spts in sptss]
            all_counts = reduce(hcat, sim_sums)
            @series begin
                label --> join(k, ", ")
                x = pts.time
                y = mean(all_counts, dims=2) |> vec
                if length(getSimulationIDs(M)) > 1
                    ribbon := std(all_counts, dims=2) |> vec
                end
                x, y
            end
        end
    end
end

@recipe function f(sampling::Sampling; include_dead=false, include_cell_types=:all, exclude_cell_types=String[])
    df = pcvct.simulationsTable(sampling)
    monads = []
    title_tuples = []
    for monad in sampling.monads
        push!(monads, monad)
        sim_id = getSimulationIDs(monad)[1]
        row_ind = findfirst(df[!, :SimID] .== sim_id)
        row = df[row_ind, :]
        title_tuple = [row[name] for name in names(row) if !(name in ["SimID"; shortLocationVariationID.(String, project_locations.varied)])]
        push!(title_tuples, title_tuple)
    end

    order = sortperm(title_tuples)
    title_tuples = title_tuples[order]
    monads = monads[order]

    layout  --> (length(monads), 1) #! easy room for improvement here

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

@recipe function f(::Type{PCVCTOutput}, out::PCVCTOutput)
    if out.trial isa Trial
        throw(ArgumentError("Plotting an entire trial not (yet?) defined. Break it down into at least Samplings first."))
    end
    out.trial
end

"""
    plotbycelltype(T::AbstractTrial; include_dead::Bool=false, include_cell_types=:all, exclude_cell_types=String[])

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

@recipe function f(p::PlotByCellType; include_dead=false, include_cell_types=:all, exclude_cell_types=String[])
    @assert length(p.args) == 1 "Expected exactly 1 argument, got $(length(p.args))."
    if (p.args[1] isa PCVCTOutput)
        T = p.args[1].trial
    else
        T = p.args[1]
    end
    @assert typeof(T) <: AbstractTrial "Expected first argument to be a subtype of AbstractTrial, got $(typeof(p.args[1]))."

    if T isa Simulation
        monads = [Monad(T)]
    else
        monads = Monad.(getMonadIDs(T))
    end

    simulation_id = getSimulationIDs(T) |> first
    all_cell_types = getCellTypeToNameDict(simulation_id) |> values |> collect
    include_cell_types = processIncludeCellTypes(include_cell_types, all_cell_types)
    exclude_cell_types = processExcludeCellTypes(exclude_cell_types)

    monad_summary = Dict{Int,Any}()
    all_cell_types = Set()
    for monad in monads
        simulation_ids = getSimulationIDs(monad)
        monad_length = length(simulation_ids)
        time = Real[]
        cell_count_arrays = Dict{Any, Array{Int,2}}()
        sptss = SimulationPopulationTimeSeries.(simulation_ids; include_dead=include_dead, verbose=false)
        filter!(!ismissing, sptss) #! remove any that failed to load
        for (i, spts) in enumerate(sptss)
            if isempty(time)
                time = spts.time
            else
                @assert time == spts.time "Simulations $(simulation_ids[1]) and $(simulation_id) in monad $(monad.id) have different times in their time series."
            end
            for k in include_cell_types
                if k isa String
                    k = [k] #! standardize so that all are vectors
                end
                setdiff!(k, exclude_cell_types) #! remove any cell types that are to be excluded (also removes duplicates)
                if isempty(k)
                    continue #! skip if all cell types were excluded
                end
                if !haskey(cell_count_arrays, k)
                    cell_count_arrays[k] = zeros(Int, length(time), monad_length)
                end
                @assert [haskey(spts.cell_count, ct) for ct in k] |> all "A cell type in $k not found in simulation $simulation_id which has cell types $(keys(spts.cell_count))."
                cell_count_arrays[k][:,i] = sum([spts.cell_count[ct] for ct in k])
            end
        end
        cell_count_means = Dict{Any, Vector{Real}}()
        cell_count_stds = Dict{Any, Vector{Real}}()
        for (name, array) in pairs(cell_count_arrays)
            cell_count_means[name] = mean(array, dims=2) |> vec
            cell_count_stds[name] = std(array, dims=2) |> vec
            push!(all_cell_types, name)
        end
        monad_summary[monad.id] = (time=time, cell_count_means=cell_count_means, cell_count_stds=cell_count_stds)
    end

    layout  --> (length(all_cell_types), 1) #! easy room for improvement here

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

@recipe function f(ctim::CellTypeInMonads)
    for (x, y, z) in zip(ctim.time, ctim.cell_count_means, ctim.cell_count_stds)
        @series begin
            ribbon := z
            x, y
        end
    end
end