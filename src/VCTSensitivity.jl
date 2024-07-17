

function moatSensitivity(n_points::Int, monad_min_length::Int, folder_names::AbstractSamplingFolders, DV::Vector{DistributedVariation})
    variation_ids, _ = addLHSVariation(n_points, folder_names.config_folder, DV)
    sampling = Sampling(monad_min_length, folder_names, variation_ids, rulesets_variation_ids)
end