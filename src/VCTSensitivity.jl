using Distributions, DataFrames, CSV, Sobol

############# Morris One-At-A-Time (MOAT) #############

function moatSensitivity(n_points::Int, monad_min_length::Int, folder_names::AbstractSamplingFolders, AV::Vector{<:AbstractVariation}; force_recompile::Bool = true, reference_variation_id::Int=0, reference_rulesets_variation_id::Int=0, add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG, orthogonalize::Bool=true)
    config_variation_ids, rulesets_variation_ids = addVariations(LHSVariation(n_points; add_noise=add_noise, rng=rng, orthogonalize=orthogonalize), folder_names.config_folder, folder_names.rulesets_collection_folder, AV; reference_variation_id=reference_variation_id, reference_rulesets_variation_id=reference_rulesets_variation_id)
    perturbed_config_variation_ids = repeat(config_variation_ids, 1, length(AV))
    perturbed_rulesets_variation_ids = repeat(rulesets_variation_ids, 1, length(AV))
    for (base_point_ind, (variation_id, rulesets_variation_id)) in enumerate(zip(config_variation_ids, rulesets_variation_ids)) # for each base point in the LHS
        for (par_ind, av) in enumerate(AV) # perturb each parameter one time
            variation_target = variationTarget(av)
            if variation_target == :config
                perturbed_config_variation_ids[base_point_ind, par_ind] = perturbConfigVariation(av, variation_id, folder_names.config_folder)
            elseif variation_target == :rulesets
                perturbed_rulesets_variation_ids[base_point_ind, par_ind] = perturbRulesetsVariation(av, rulesets_variation_id, folder_names.rulesets_collection_folder)
            else
                error("Unknown variation target: $variation_target")
            end
        end
    end
    all_config_variation_ids = hcat(config_variation_ids, perturbed_config_variation_ids)
    all_rulesets_variation_ids = hcat(rulesets_variation_ids, perturbed_rulesets_variation_ids)
    sampling = Sampling(monad_min_length, folder_names, all_config_variation_ids[:], all_rulesets_variation_ids[:])
    recordMOATScheme(sampling, AV, all_config_variation_ids, all_rulesets_variation_ids)
    n_ran, n_success = runAbstractTrial(sampling; use_previous_sims=true, force_recompile=force_recompile)
    return sampling
end

function recordMOATScheme(sampling::Sampling, AV::Vector{<:AbstractVariation}, all_config_variation_ids::Matrix{Int}, all_rulesets_variation_ids::Matrix{Int})
    sampling_id = sampling.id
    path_to_folder = "$(data_dir)/outputs/samplings/$(sampling_id)/"
    mkpath(path_to_folder)
    recordMOATSchemeConfigVariations(AV, all_config_variation_ids, path_to_folder)
    recordMOATSchemeRulesetsVariations(AV, all_rulesets_variation_ids, path_to_folder)
end

function recordMOATSchemeConfigVariations(AV::Vector{<:AbstractVariation}, all_config_variation_ids::Matrix{Int}, path_to_folder::String)
    path_to_csv = "$(path_to_folder)/moat_scheme_variations.csv"
    return recordSensitivityScheme(AV, all_config_variation_ids, path_to_csv)
end

function recordMOATSchemeRulesetsVariations(AV::Vector{DistributedVariation}, all_rulesets_variation_ids::Matrix{Int}, path_to_folder::String)
    path_to_csv = "$(path_to_folder)/moat_scheme_rulesets_variations.csv"
    return recordSensitivityScheme(AV, all_rulesets_variation_ids, path_to_csv)
end

function perturbConfigVariation(av::AbstractVariation, variation_id::Int, folder::String)
    base_value = getConfigBaseValue(variationColumnName(av), variation_id, folder)
    addFn = (ev) -> addGridVariation(folder, ev; reference_variation_id=variation_id)
    return makePerturbation(av, base_value, addFn)
end

function perturbRulesetsVariation(av::AbstractVariation, variation_id::Int, folder::String)
    base_value = getRulesetsBaseValue(variationColumnName(av), variation_id, folder)
    addFn = (ev) -> addGridRulesetsVariation(folder, ev; reference_rulesets_variation_id=variation_id)
    return makePerturbation(av, base_value, addFn)
end

function makePerturbation(av::AbstractVariation, base_value, addFn::Function)
    cdf_at_base = variationCDF(av, base_value)
    dcdf = cdf_at_base < 0.5 ? 0.5 : -0.5
    new_value = getVariationValues(av; cdf=cdf_at_base + dcdf)

    new_ev = ElementaryVariation(getVariationXMLPath(av), [new_value])

    new_variation_id = addFn(new_ev)
    @assert length(new_variation_id) == 1 "Only doing one perturbation at a time"
    return new_variation_id[1]
end

# function perturbVariation(av::AbstractVariation, variation_id::Int, folder_names::AbstractSamplingFolders)
#     base_value, variation_target = getBaseValue(av, variation_id, folder_names)
#     cdf_at_base = cdf(av.distribution, base_value)
#     dcdf = cdf_at_base < 0.5 ? 0.5 : -0.5
#     new_value = quantile(av.distribution, cdf_at_base + dcdf)

#     new_ev = ElementaryVariation(av.xml_path, [new_value])

#     if variation_target == :config
#         new_variation_id = addGridVariation(folder_names.config_folder, new_ev; reference_variation_id=variation_id)
#     elseif variation_target == :rulesets
#         new_variation_id = addGridRulesetsVariation(folder_names.rulesets_collection_folder, new_ev; reference_rulesets_variation_id=variation_id)
#     else
#         error("Unknown variation target: $variation_target")
#     end
#     @assert length(new_variation_id) == 1 "Only doing one perturbation at a time"
#     return new_variation_id[1], variation_target
# end

function getConfigBaseValue(av::AbstractVariation, variation_id::Int, folder::String)
    column_name = variationColumnName(av)
    return getConfigBaseValue(column_name, variation_id, folder)
end

function getConfigBaseValue(column_name::String, variation_id::Int, folder::String)
    query = constructSelectQuery("variations", "WHERE variation_id=$variation_id;"; selection="\"$(column_name)\"")
    variation_value_df = queryToDataFrame(query; db=getConfigDB(folder), is_row=true)
    return variation_value_df[1,1]
end

function getRulesetsBaseValue(av::AbstractVariation, variation_id::Int, folder::String)
    column_name = variationColumnName(av)
    return getRulesetsBaseValue(column_name, variation_id, folder)
end

function getRulesetsBaseValue(column_name::String, variation_id::Int, folder::String)
    query = constructSelectQuery("rulesets_variations", "WHERE rulesets_variation_id=$variation_id;"; selection="\"$(column_name)\"")
    variation_value_df = queryToDataFrame(query; db=getRulesetsCollectionDB(folder), is_row=true)
    return variation_value_df[1,1]
end

function getBaseValue(av::AbstractVariation, variation_id::Int, folder_names::AbstractSamplingFolders)
    variation_target = variationTarget(av)
    if variation_target == :config
        return getConfigBaseValue(av, variation_id, folder_names.config_folder)
    elseif variation_target == :rulesets
        return getRulesetsBaseValue(av, variation_id, folder_names.rulesets_collection_folder)
    else
        error("Unknown variation target: $variation_target")
    end
end

function measureMOATSensitivity(sampling::Sampling, f::Function)
    value_dict = evaluateFunctionOnSampling(sampling, f)
    variation_id_matrix, rulesets_variation_id_matrix = readSensitivityScheme(sampling, readMOATScheme)
    values = zeros(Float64, size(variation_id_matrix))
    for (ind, (variation_id, rulesets_variation_id)) in enumerate(zip(variation_id_matrix, rulesets_variation_id_matrix))
        values[ind] = value_dict[(variation_id, rulesets_variation_id)]
    end
    dvalues = abs.(values[:,2:end] .- values[:,1]) / 0.5 # consider net diff and normalize by the change in cdf (always 0.5 for now)
    dvalue_mean = mean(dvalues, dims=1)
    dvalue_std = std(dvalues, dims=1)
    return dvalue_mean, dvalue_std
end

function readMOATScheme(path_to_folder::String, scheme::String)
    path_to_csv = "$(path_to_folder)/moat_scheme_$(scheme).csv"
    if !isfile(path_to_csv)
        error("No MOAT scheme found at $path_to_csv")
    end
    df = CSV.read(path_to_csv, DataFrame)
    return Matrix(df)
end

############# Sobol sequences and sobol indices #############

function sobolSensitivity(n_points::Int, monad_min_length::Int, folder_names::AbstractSamplingFolders, AV::Vector{<:AbstractVariation}; force_recompile::Bool = true, reference_variation_id::Int=0, reference_rulesets_variation_id::Int=0)
    all_config_variation_ids, all_rulesets_variation_ids = addSobolSensitivityVariation(n_points, folder_names.config_folder, folder_names.rulesets_collection_folder, AV; reference_variation_id=reference_variation_id, reference_rulesets_variation_id=reference_rulesets_variation_id)
    sampling = Sampling(monad_min_length, folder_names, all_config_variation_ids[:], all_rulesets_variation_ids[:])
    recordSobolScheme(sampling, AV, all_config_variation_ids, all_rulesets_variation_ids)
    n_ran, n_success = runAbstractTrial(sampling; use_previous_sims=true, force_recompile=force_recompile)
    return sampling
end

function addSobolSensitivityVariation(n::Integer, config_id::Int, rulesets_collection_id::Int, AV::Vector{<:AbstractVariation}; reference_variation_id::Int=0, reference_rulesets_variation_id::Int=0)
    config_variation_ids, rulesets_variation_ids, cdfs, config_variations, rulesets_variations = addVariations(SobolVariation(n; n_matrices=2), config_id, rulesets_collection_id, AV; reference_variation_id=reference_variation_id, reference_rulesets_variation_id=reference_rulesets_variation_id)
    d_config = length(config_variations)
    d_rulesets = length(rulesets_variations)
    d = d_config + d_rulesets
    config_variation_ids_A = config_variation_ids[:,1]
    rulesets_variation_ids_A = rulesets_variation_ids[:,1]
    A = cdfs[:,1,:] # cdfs is of size (d, 2, n)
    config_variation_ids_B = config_variation_ids[:,2]
    rulesets_variation_ids_B = rulesets_variation_ids[:,2]
    B = cdfs[:,2,:]
    Aᵦ = [copy(A) for _ in 1:d]
    config_variation_ids_Aᵦ = repeat(config_variation_ids_A, 1, d)
    rulesets_variation_ids_Aᵦ = repeat(rulesets_variation_ids_A, 1, d)
    for (i, b_row) in enumerate(eachrow(B))
        Aᵦ[i][i,:] = b_row
        if i <= length(config_variations)
            config_variation_ids_Aᵦ[:,i] = cdfsToVariations(Aᵦ[i][1:length(config_variations),:]', config_variations, prepareVariationFunctions(config_id, config_variations; reference_variation_id=reference_variation_id)...)
        else
            rulesets_variation_ids_Aᵦ[:,i] = cdfsToVariations(Aᵦ[i][length(config_variations)+1:end,:]', rulesets_variations, prepareRulesetsVariationFunctions(rulesets_collection_id; reference_rulesets_variation_id=reference_rulesets_variation_id)...)
        end
    end
    return hcat(config_variation_ids_A, config_variation_ids_B, config_variation_ids_Aᵦ), hcat(rulesets_variation_ids_A, rulesets_variation_ids_B, rulesets_variation_ids_Aᵦ)
end

addSobolSensitivityVariation(n::Integer, config_folder::String, rulesets_collection_folder::String, AV::Vector{<:AbstractVariation}; reference_variation_id::Int=0, reference_rulesets_variation_id::Int=0) = addSobolSensitivityVariation(n, retrieveID("configs", config_folder), retrieveID("rulesets_collections", rulesets_collection_folder), AV; reference_variation_id=reference_variation_id, reference_rulesets_variation_id=reference_rulesets_variation_id)
addSobolSensitivityVariation(n::Integer, config_id::Int, rulesets_collection_id::Int, av::AbstractVariation; reference_variation_id::Int=0, reference_rulesets_variation_id::Int=0) = addSobolSensitivityVariation(n, config_id, rulesets_collection_id, [av]; reference_variation_id=reference_variation_id, reference_rulesets_variation_id=reference_rulesets_variation_id)
addSobolSensitivityVariation(n::Integer, config_folder::String, rulesets_collection_folder::String, av::AbstractVariation; reference_variation_id::Int=0, reference_rulesets_variation_id::Int=0) = addSobolSensitivityVariation(n, retrieveID("configs", config_folder), retrieveID("rulesets_collections", rulesets_collection_folder), [av]; reference_variation_id=reference_variation_id, reference_rulesets_variation_id=reference_rulesets_variation_id)

function recordSobolScheme(sampling::Sampling, DV::Vector{DistributedVariation}, all_config_variation_ids::Matrix{Int}, all_rulesets_variation_ids::Matrix{Int})
    sampling_id = sampling.id
    path_to_folder = "$(data_dir)/outputs/samplings/$(sampling_id)/"
    mkpath(path_to_folder)
    recordSobolSchemeVariations(DV, all_config_variation_ids, path_to_folder)
    recordSobolSchemeRulesetsVariations(DV, all_rulesets_variation_ids, path_to_folder)
end

function recordSobolSchemeVariations(DV::Vector{DistributedVariation}, all_config_variation_ids::Matrix{Int}, path_to_folder::String)
    path_to_csv = "$(path_to_folder)/sobol_scheme_variations.csv"
    return recordSensitivityScheme(DV, all_config_variation_ids, path_to_csv; initial_header_names=["A", "B"])
end

function recordSobolSchemeRulesetsVariations(DV::Vector{DistributedVariation}, all_rulesets_variation_ids::Matrix{Int}, path_to_folder::String)
    path_to_csv = "$(path_to_folder)/sobol_scheme_rulesets_variations.csv"
    return recordSensitivityScheme(DV, all_rulesets_variation_ids, path_to_csv; initial_header_names=["A", "B"])
end

function measureSobolSensitivity(sampling::Sampling, f::Function; si_method::Symbol=:Jansen1999, st_method::Symbol=:Jansen1999)
    value_dict = evaluateFunctionOnSampling(sampling, f)
    variation_id_matrix, rulesets_variation_id_matrix = readSensitivityScheme(sampling, readSobolScheme)
    values = zeros(Float64, size(variation_id_matrix))
    for (ind, (variation_id, rulesets_variation_id)) in enumerate(zip(variation_id_matrix, rulesets_variation_id_matrix))
        values[ind] = value_dict[(variation_id, rulesets_variation_id)]
    end
    d = size(values, 2) - 2
    A_values = @view values[:,1]
    B_values = @view values[:,2]
    Aᵦ_values = [values[:,2+i] for i in 1:d]
    expected_value² = mean(A_values .* B_values) # see Saltelli, 2002 Eq 21
    total_variance = var([A_values; B_values])
    first_order_variances = zeros(Float64, d)
    total_order_variances = zeros(Float64, d)
    for (i, Aᵦ) in enumerate(Aᵦ_values)
        # I found Jansen, 1999 to do best for first order variances on a simple test of f(x,y) = x.^2 + y.^2 + c with a uniform distribution on [0,1] x [0,1] including with noise added
        if si_method == :Sobol1993
            first_order_variances[i] = mean(B_values .* Aᵦ) .- expected_value² # Sobol, 1993
        elseif si_method == :Jansen1999
            first_order_variances[i] = total_variance - 0.5 * mean((B_values .- Aᵦ).^2) # Jansen, 1999
        elseif si_method == :Saltelli2010
            first_order_variances[i] = mean(B_values .* (Aᵦ .- A_values)) # Saltelli, 2010
        end

        # I found Jansen, 1999 to do best for total order variances on a simple test of f(x,y) = x.^2 + y.^2 + c with a uniform distribution on [0,1] x [0,1] including with noise added
        if st_method == :Homma1996
            total_order_variances[i] = total_variance - mean(A_values .* Aᵦ) + expected_value² # Homma, 1996
        elseif st_method == :Sobol2007
            total_order_variances[i] = mean(A_values .* (A_values .- Aᵦ)) # Sobol, 2007
        elseif st_method == :Jansen1999
            total_order_variances[i] = 0.5 * mean((Aᵦ .- A_values).^2) # Jansen, 1999
        end
    end
    
    first_order_indices = first_order_variances ./ total_variance
    total_order_indices = total_order_variances ./ total_variance
    return first_order_indices, total_order_indices
end

function readSobolScheme(path_to_folder::String, scheme::String)
    path_to_csv = "$(path_to_folder)/sobol_scheme_$(scheme).csv"
    if !isfile(path_to_csv)
        error("No Sobol scheme found at $path_to_csv")
    end
    df = CSV.read(path_to_csv, DataFrame)
    return Matrix(df)
end

############# Random Balance Design (RBD) #############

function rbdSensitivity(n_points::Int, monad_min_length::Int, folder_names::AbstractSamplingFolders, AV::Vector{<:AbstractVariation}; force_recompile::Bool = true, reference_variation_id::Int=0, reference_rulesets_variation_id::Int=0, rng::AbstractRNG=Random.GLOBAL_RNG, use_sobol::Bool=true)
    config_variation_ids, rulesets_variation_ids, variations_matrix, rulesets_variations_matrix = addVariations(RBDVariation(n_points, rng, use_sobol), folder_names.config_folder, folder_names.rulesets_collection_folder, AV; reference_variation_id=reference_variation_id, reference_rulesets_variation_id=reference_rulesets_variation_id)
    sampling = Sampling(monad_min_length, folder_names, config_variation_ids[:], rulesets_variation_ids[:])
    recordRBDScheme(sampling, AV, variations_matrix, rulesets_variations_matrix)
    n_ran, n_success = runAbstractTrial(sampling; use_previous_sims=true, force_recompile=force_recompile)
    return sampling
end

function recordRBDScheme(sampling::Sampling, AV::Vector{<:AbstractVariation}, variations_matrix::Matrix{Int}, rulesets_variations_matrix::Matrix{Int})
    d = length(AV)
    sampling_id = sampling.id
    path_to_folder = "$(data_dir)/outputs/samplings/$(sampling_id)/"
    mkpath(path_to_folder)
    recordRBDSchemeVariations(AV, variations_matrix, path_to_folder)
    recordRBDSchemeRulesetsVariations(AV, rulesets_variations_matrix, path_to_folder)
end

function recordRBDSchemeVariations(DV::Vector{DistributedVariation}, all_config_variation_ids::Matrix{Int}, path_to_folder::String)
    path_to_csv = "$(path_to_folder)/rbd_scheme_variations.csv"
    return recordSensitivityScheme(DV, all_config_variation_ids, path_to_csv; initial_header_names=String[])
end

function recordRBDSchemeRulesetsVariations(DV::Vector{DistributedVariation}, all_rulesets_variation_ids::Matrix{Int}, path_to_folder::String)
    path_to_csv = "$(path_to_folder)/rbd_scheme_rulesets_variations.csv"
    return recordSensitivityScheme(DV, all_rulesets_variation_ids, path_to_csv; initial_header_names=String[])
end

############# Generic Helper Functions #############

function recordSensitivityScheme(AV::Vector{<:AbstractVariation}, all_config_variation_ids::Matrix{Int}, path_to_csv::String; initial_header_names::Vector{String}=["base"])
    header_line = [initial_header_names..., [variationColumnName(av) for av in AV]...]
    lines_df = DataFrame(all_config_variation_ids, header_line)
    return CSV.write(path_to_csv, lines_df; writeheader=true)
end

function evaluateFunctionOnSampling(sampling::Sampling, f::Function)
    monad_ids = getSamplingMonads(sampling)
    value_dict = Dict{Tuple{Int, Int}, Float64}()
    for monad_id in monad_ids
        monad = getMonad(monad_id)
        variation_id = monad.variation_id
        rulesets_variation_id = monad.rulesets_variation_id
        simulation_ids = getMonadSimulations(monad_id)
        sim_values = [f(simulation_id) for simulation_id in simulation_ids]
        value = sim_values |> mean
        value_dict[(variation_id, rulesets_variation_id)] = value
    end
    return value_dict
end

function readSensitivityScheme(sampling::Sampling, readFn::Function)
    path_to_folder = "$(data_dir)/outputs/samplings/$(sampling.id)/"
    variation_id_matrix = readFn(path_to_folder, "variations")
    rulesets_variation_id_matrix = readFn(path_to_folder, "rulesets_variations")
    return variation_id_matrix, rulesets_variation_id_matrix
end
    