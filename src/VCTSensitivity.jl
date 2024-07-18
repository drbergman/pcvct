using Distributions

function moatSensitivity(n_points::Int, monad_min_length::Int, folder_names::AbstractSamplingFolders, DV::Vector{DistributedVariation}; force_recompile::Bool = true, reference_variation_id::Int=0, add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG)
    variation_ids, _ = addLHSVariation(n_points, folder_names.config_folder, DV; reference_variation_id=reference_variation_id, add_noise=add_noise, rng=rng)
    all_perturbed_variation_ids = []
    for variation_id in variation_ids # for each base point in the LHS
        perturbed_variation_ids = []
        for dv in DV # perturb each parameter one Time
            new_variation_id = perturbVariation(dv, variation_id, folder_names.config_folder; reference_variation_id=variation_id)
            push!(perturbed_variation_ids, new_variation_id)
        end
        push!(all_perturbed_variation_ids, perturbed_variation_ids)
    end
    all_variation_ids = vcat(variation_ids, all_perturbed_variation_ids...)
    rulesets_variation_ids = zeros(Int, length(all_variation_ids)) # hard code this for now
    sampling = Sampling(monad_min_length, folder_names, all_variation_ids, rulesets_variation_ids)
    n_ran, n_success = cd(()->runAbstractTrial(sampling; use_previous_sims=true, force_recompile=force_recompile))
end

function perturbVariation(DV::DistributedVariation, variation_id::Int, config_folder::String)
    base_value = getBaseValue(DV, variation_id, config_folder)
    cdf_at_base = cdf(DV.distribution, base_value)
    dcdf = cdf_at_base < 0.5 ? 0.5 : -0.5
    new_value = quantile(DV.distribution, cdf_at_base + dcdf)

    new_ev = ElementaryVariation(DV.xml_path, new_value)

    new_variation_id, _ = addGridVariation(config_folder, new_ev; reference_variation_id=variation_id)
    return new_variation_id
end

function getBaseValue(DV::DistributedVariation, variation_id::Int, config_folder::String)
    column_name = xmlPathToColumnName(DV.xml_path)
    query = constructSelectQuery("variations", "WHERE variation_id=$variation_id;"; selection=column_name)
    variation_value_df = queryToDataFrame(query; db=getConfigDB(config_folder), is_row=true)
    return variation_value_df[!,1]
end
