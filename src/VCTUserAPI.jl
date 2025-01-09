import Base.run

export createTrial

"""
    createTrial(inputs::InputFolders, evs::Vector{<:ElementaryVariation}=ElementaryVariation[]; n_replicates::Integer=1,
                use_previous::Bool=true)

Return an object of type `<:AbstractTrial` (simulation, monad, sampling, trial) with the given input folders and elementary variations.

Uses the `evs` and `n_replicates` to determine whether to create a simulation, monad, or sampling.
Despite its name, trials cannot yet be created by this function.
If `n_replicates` is 0, and each variation has a single value, a simulation will be created.

Alternate forms:
Only supplying a single `ElementaryVariation`:
```
createTrial(inputs::InputFolders, ev::ElementaryVariation; n_replicates::Integer=1, use_previous::Bool=true)
```
Using a reference simulation or monad:
```
createTrial(reference::AbstractMonad, evs::Vector{<:ElementaryVariation}=ElementaryVariation[]; n_replicates::Integer=1,
            use_previous::Bool=true)
```
```
createTrial(reference::AbstractMonad, ev::ElementaryVariation; n_replicates::Integer=1, use_previous::Bool=true)
```

# Examples
```
inputs = InputFolders(config_folder, custom_code_folder)
dv_max_time = DiscreteVariation([\"overall\", \"max_time\"], 1440)
dv_apoptosis = DiscreteVariation([pcvct.apoptosisPath(cell_type); "rate"], [1e-6, 1e-5])
simulation = createTrial(inputs, dv_max_time)
monad = createTrial(inputs, dv_max_time; n_replicates=2)
sampling = createTrial(monad, dv_apoptosis; n_replicates=2) # uses the max time defined for monad
```
"""
function createTrial(inputs::InputFolders, evs::Vector{<:ElementaryVariation}=ElementaryVariation[]; n_replicates::Integer=1,
                     use_previous::Bool=true)
    return _createTrial(inputs, VariationIDs(inputs), evs, n_replicates, use_previous)
end

function createTrial(inputs::InputFolders, ev::ElementaryVariation; n_replicates::Integer=1, use_previous::Bool=true)
    return _createTrial(inputs, VariationIDs(inputs), [ev], n_replicates, use_previous)
end

function createTrial(reference::AbstractMonad, evs::Vector{<:ElementaryVariation}=ElementaryVariation[]; n_replicates::Integer=1,
    use_previous::Bool=true)
    return _createTrial(reference.inputs, reference.variation_ids, evs, n_replicates, use_previous)
end

function createTrial(reference::AbstractMonad, ev::ElementaryVariation; n_replicates::Integer=1, use_previous::Bool=true)
    return _createTrial(reference.inputs, reference.variation_ids, [ev], n_replicates, use_previous)
end

function _createTrial(inputs::InputFolders, reference_variation_ids::VariationIDs, evs::Vector{<:ElementaryVariation}, n_replicates::Integer, use_previous::Bool)
    config_variation_ids, rulesets_collection_variation_ids, ic_cell_variation_ids = addVariations(GridVariation(), inputs, evs, reference_variation_ids)
    if length(config_variation_ids) == 1
        variation_ids = VariationIDs(config_variation_ids[1], rulesets_collection_variation_ids[1], ic_cell_variation_ids[1])
        monad = Monad(n_replicates, inputs, variation_ids, use_previous)
        if n_replicates != 1
            return monad
        end
        return Simulation(monad.simulation_ids[end])
    else
        return Sampling(inputs; n_replicates=n_replicates,
                        config_variation_ids=config_variation_ids,
                        rulesets_collection_variation_ids=rulesets_collection_variation_ids,
                        ic_cell_variation_ids=ic_cell_variation_ids,
                        use_previous=use_previous)
    end
end

"""
    run(args...; force_recompile::Bool=false, prune_options::PruneOptions=PruneOptions(), kwargs...)

Run a simulation, monad, sampling, or trial with the same signatures available to [`createTrial`](@ref).
"""
function run(inputs::InputFolders, args...; force_recompile::Bool=false, prune_options::PruneOptions=PruneOptions(), kwargs...)
    trial = createTrial(inputs, args...; kwargs...)
    return run(trial; force_recompile=force_recompile, prune_options=prune_options)
end

function run(reference::AbstractMonad, evs::Union{ElementaryVariation,Vector{<:ElementaryVariation}}; n_replicates::Integer=1,
             use_previous::Bool=true, force_recompile::Bool=false, prune_options::PruneOptions=PruneOptions())
    trial = createTrial(reference, evs; n_replicates=n_replicates, use_previous=use_previous)
    return run(trial; force_recompile=force_recompile, prune_options=prune_options)
end