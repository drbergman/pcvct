import Base.run

export createTrial

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

function run(inputs::InputFolders, args...; force_recompile::Bool=false, prune_options::PruneOptions=PruneOptions(), kwargs...)
    trial = createTrial(inputs, args...; kwargs...)
    return run(trial; force_recompile=force_recompile, prune_options=prune_options)
end

function run(reference::AbstractMonad, evs::Union{ElementaryVariation,Vector{<:ElementaryVariation}}; n_replicates::Integer=1,
             use_previous::Bool=true, force_recompile::Bool=false, prune_options::PruneOptions=PruneOptions())
    trial = createTrial(reference, evs; n_replicates=n_replicates, use_previous=use_previous)
    return run(trial; force_recompile=force_recompile, prune_options=prune_options)
end