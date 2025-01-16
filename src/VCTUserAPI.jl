import Base.run

export createTrial

"""
    createTrial([method=GridVariation()], inputs::InputFolders, avs::Vector{<:AbstractVariation}=AbstractVariation[];
                n_replicates::Integer=1, use_previous::Bool=true)

Return an object of type `<:AbstractTrial` (simulation, monad, sampling, trial) with the given input folders and elementary variations.

Uses the `avs` and `n_replicates` to determine whether to create a simulation, monad, or sampling.
Despite its name, trials cannot yet be created by this function.
If `n_replicates` is 0, and each variation has a single value, a simulation will be created.

By default, the `method` is `GridVariation()`, which creates a grid of variations from the vector `avs`.
Other methods are: [`LHSVariation`](@ref), [`SobolVariation`](@ref), and [`RBDVariation`](@ref).

Alternate forms (all work with the optional `method` argument in the first position):
Only supplying a single `AbstractVariation`:
```
createTrial(inputs::InputFolders, av::AbstractVariation; n_replicates::Integer=1, use_previous::Bool=true)
```
Using a reference simulation or monad:
```
createTrial(reference::AbstractMonad, avs::Vector{<:AbstractVariation}=AbstractVariation[]; n_replicates::Integer=1,
            use_previous::Bool=true)
```
```
createTrial(reference::AbstractMonad, av::AbstractVariation; n_replicates::Integer=1, use_previous::Bool=true)
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
function createTrial(method::AddVariationMethod, inputs::InputFolders, avs::Vector{<:AbstractVariation}=AbstractVariation[];
    n_replicates::Integer=1, use_previous::Bool=true)
    return _createTrial(method, inputs, VariationIDs(inputs), avs, n_replicates, use_previous)
end

function createTrial(method::AddVariationMethod, inputs::InputFolders, av::AbstractVariation; kwargs...)
    return createTrial(method, inputs, [av]; kwargs...)
end

createTrial(inputs::InputFolders, args...; kwargs...) = createTrial(GridVariation(), inputs, args...; kwargs...)


function createTrial(method::AddVariationMethod, reference::AbstractMonad, avs::Vector{<:AbstractVariation}=AbstractVariation[];
                     n_replicates::Integer=1, use_previous::Bool=true)
    return _createTrial(method, reference.inputs, reference.variation_ids, avs, n_replicates, use_previous)
end

function createTrial(method::AddVariationMethod, reference::AbstractMonad, av::AbstractVariation; kwargs...)
    return createTrial(method, reference, [av]; kwargs...)
end

createTrial(reference::AbstractMonad, args...; kwargs...) = createTrial(GridVariation(), reference, args...; kwargs...)

function _createTrial(method::AddVariationMethod, inputs::InputFolders, reference_variation_ids::VariationIDs,
                      avs::Vector{<:AbstractVariation}, n_replicates::Integer, use_previous::Bool)
                      
    config_variation_ids, rulesets_collection_variation_ids, ic_cell_variation_ids = addVariations(method, inputs, avs, reference_variation_ids)
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
function run(method::AddVariationMethod, args...; force_recompile::Bool=false, 
             prune_options::PruneOptions=PruneOptions(), kwargs...)
    trial = createTrial(method, args...; kwargs...)
    return run(trial; force_recompile=force_recompile, prune_options=prune_options)
end

run(inputs::InputFolders, args...; kwargs...) = run(GridVariation(), inputs, args...; kwargs...)

function run(reference::AbstractMonad, avs::Union{AbstractVariation,Vector{<:AbstractVariation}}; kwargs...)
    return run(GridVariation(), reference, avs; kwargs...)
end
