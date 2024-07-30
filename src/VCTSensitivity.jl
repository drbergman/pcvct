using Distributions, DataFrames, CSV, Sobol

############# Morris One-At-A-Time (MOAT) #############

function moatSensitivity(n_points::Int, monad_min_length::Int, folder_names::AbstractSamplingFolders, DV::Vector{DistributedVariation}; force_recompile::Bool = true, reference_variation_id::Int=0, add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG)
    variation_ids = addLHSVariation(n_points, folder_names.config_folder, DV; reference_variation_id=reference_variation_id, add_noise=add_noise, rng=rng)
    rulesets_variation_ids = zeros(Int, length(variation_ids)) # hard code this for now
    perturbed_variation_ids = zeros(Int, (n_points, length(DV)))
    for (base_point_ind, variation_id) in enumerate(variation_ids) # for each base point in the LHS
        for (par_ind, dv) in enumerate(DV) # perturb each parameter one time
            new_variation_id = perturbVariation(dv, variation_id, folder_names.config_folder)
            perturbed_variation_ids[base_point_ind, par_ind] = new_variation_id
        end
    end
    perturbed_rulesets_variation_ids = zeros(Int, size(perturbed_variation_ids)) # hard code this for now
    all_variation_ids = hcat(variation_ids, perturbed_variation_ids)
    all_rulesets_variation_ids = hcat(rulesets_variation_ids, perturbed_rulesets_variation_ids)
    sampling = Sampling(monad_min_length, folder_names, all_variation_ids[:], all_rulesets_variation_ids[:])
    recordMOATScheme(sampling, DV, all_variation_ids, all_rulesets_variation_ids)
    n_ran, n_success = runAbstractTrial(sampling; use_previous_sims=true, force_recompile=force_recompile)
    return sampling
end

function recordMOATScheme(sampling::Sampling, DV::Vector{DistributedVariation}, all_variation_ids::Matrix{Int}, all_rulesets_variation_ids::Matrix{Int})
    sampling_id = sampling.id
    path_to_folder = "$(data_dir)/outputs/samplings/$(sampling_id)/"
    mkpath(path_to_folder)
    recordMOATSchemeVariations(DV, all_variation_ids, path_to_folder)
    recordMOATSchemeRulesetsVariations(DV, all_rulesets_variation_ids, path_to_folder)
end

function recordMOATSchemeVariations(DV::Vector{DistributedVariation}, all_variation_ids::Matrix{Int}, path_to_folder::String)
    path_to_csv = "$(path_to_folder)/moat_scheme_variations.csv"
    return recordSensitivityScheme(DV, all_variation_ids, path_to_csv)
end

function recordMOATSchemeRulesetsVariations(DV::Vector{DistributedVariation}, all_rulesets_variation_ids::Matrix{Int}, path_to_folder::String)
    path_to_csv = "$(path_to_folder)/moat_scheme_rulesets_variations.csv"
    return recordSensitivityScheme(DV, all_rulesets_variation_ids, path_to_csv)
end

function perturbVariation(DV::DistributedVariation, variation_id::Int, config_folder::String)
    base_value = getBaseValue(DV, variation_id, config_folder)
    cdf_at_base = cdf(DV.distribution, base_value)
    dcdf = cdf_at_base < 0.5 ? 0.5 : -0.5
    new_value = quantile(DV.distribution, cdf_at_base + dcdf)

    new_ev = ElementaryVariation(DV.xml_path, [new_value])

    new_variation_id = addGridVariation(config_folder, new_ev; reference_variation_id=variation_id)
    @assert length(new_variation_id) == 1 "Only doing one perturbation at a time"
    return new_variation_id[1]
end

function getBaseValue(DV::DistributedVariation, variation_id::Int, config_folder::String)
    column_name = xmlPathToColumnName(DV.xml_path)
    query = constructSelectQuery("variations", "WHERE variation_id=$variation_id;"; selection="\"$(column_name)\"")
    variation_value_df = queryToDataFrame(query; db=getConfigDB(config_folder), is_row=true)
    return variation_value_df[1,1]
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

function sobolSensitivity(n_points::Int, monad_min_length::Int, folder_names::AbstractSamplingFolders, DV::Vector{DistributedVariation}; force_recompile::Bool = true, reference_variation_id::Int=0)
    all_variation_ids = addSobolSensitivityVariation(n_points, folder_names.config_folder, DV; reference_variation_id=reference_variation_id)
    all_rulesets_variation_ids = zeros(Int, size(all_variation_ids)) # hard code this for now
    sampling = Sampling(monad_min_length, folder_names, all_variation_ids[:], all_rulesets_variation_ids[:])
    recordSobolScheme(sampling, DV, all_variation_ids, all_rulesets_variation_ids)
    n_ran, n_success = runAbstractTrial(sampling; use_previous_sims=true, force_recompile=force_recompile)
    return sampling
end

function addSobolSensitivityVariation(n::Integer, config_id::Int, DV::Vector{DistributedVariation}; reference_variation_id::Int=0)
    variation_ids, icdfs = addSobolVariation(n, config_id, DV; reference_variation_id=reference_variation_id, n_matrices=2)
    d = length(DV)
    icdfs = reshape(icdfs, (d, 2, n))
    A = icdfs[:,1,:]
    variation_ids_A = variation_ids[:,1:d]
    B = icdfs[:,2,:]
    variation_ids_B = variation_ids[:,d+1:end]
    Aᵦ = [copy(A) for _ in 1:d]
    variation_ids_Aᵦ = zeros(Int, n, d)
    for (i, b_row) in enumerate(eachrow(B))
        Aᵦ[i][i,:] = b_row
        variation_ids_Aᵦ[:,i] = icdfsToVariations(n, Aᵦ[i]', DV, fns...) # a vector of all variation_ids grouped as above
    end
    return hcat(variation_ids_A, variation_ids_B, variation_ids_Aᵦ)
end

addSobolSensitivityVariation(n::Integer, config_folder::String, DV::Vector{DistributedVariation}; reference_variation_id::Int=0) = addSobolSensitivityVariation(n, retrieveID("configs", config_folder), DV; reference_variation_id=reference_variation_id)
addSobolSensitivityVariation(n::Integer, config_id::Int, DV::DistributedVariation; reference_variation_id::Int=0) = addSobolSensitivityVariation(n, config_id, [DV]; reference_variation_id=reference_variation_id)
addSobolSensitivityVariation(n::Integer, config_folder::String, DV::DistributedVariation; reference_variation_id::Int=0) = addSobolSensitivityVariation(n, retrieveID("configs", config_folder), [DV]; reference_variation_id=reference_variation_id)

function recordSobolScheme(sampling::Sampling, DV::Vector{DistributedVariation}, all_variation_ids::Matrix{Int}, all_rulesets_variation_ids::Matrix{Int})
    sampling_id = sampling.id
    path_to_folder = "$(data_dir)/outputs/samplings/$(sampling_id)/"
    mkpath(path_to_folder)
    recordSobolSchemeVariations(DV, all_variation_ids, path_to_folder)
    recordSobolSchemeRulesetsVariations(DV, all_rulesets_variation_ids, path_to_folder)
end

function recordSobolSchemeVariations(DV::Vector{DistributedVariation}, all_variation_ids::Matrix{Int}, path_to_folder::String)
    path_to_csv = "$(path_to_folder)/sobol_scheme_variations.csv"
    return recordSensitivityScheme(DV, all_variation_ids, path_to_csv; initial_header_names=["A", "B"])
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

function rbdSensitivity(n_points::Int, monad_min_length::Int, folder_names::AbstractSamplingFolders, DV::Vector{DistributedVariation}; force_recompile::Bool = true, reference_variation_id::Int=0, rng::AbstractRNG=Random.GLOBAL_RNG, use_sobol::Bool=true)
    all_variation_ids, variations_matrix = addRBDVariation(n_points, folder_names.config_folder, DV; reference_variation_id=reference_variation_id, rng=rng, use_sobol=use_sobol)
    all_rulesets_variation_ids = zeros(Int, size(all_variation_ids)) # hard code this for now
    rulesets_variations_matrix = zeros(Int, size(variations_matrix)) # hard code this for now
    sampling = Sampling(monad_min_length, folder_names, all_variation_ids[:], all_rulesets_variation_ids[:])
    recordRBDScheme(sampling, DV, variations_matrix, rulesets_variations_matrix)
    n_ran, n_success = runAbstractTrial(sampling; use_previous_sims=true, force_recompile=force_recompile)
    return sampling
end

function recordRBDScheme(sampling::Sampling, DV::Vector{DistributedVariation}, variations_matrix::Matrix{Int}, rulesets_variations_matrix::Matrix{Int})
    d = length(DV)
    sampling_id = sampling.id
    path_to_folder = "$(data_dir)/outputs/samplings/$(sampling_id)/"
    mkpath(path_to_folder)
    recordRBDSchemeVariations(DV, variations_matrix, path_to_folder)
    recordRBDSchemeRulesetsVariations(DV, rulesets_variations_matrix, path_to_folder)
end

function recordRBDSchemeVariations(DV::Vector{DistributedVariation}, all_variation_ids::Matrix{Int}, path_to_folder::String)
    path_to_csv = "$(path_to_folder)/rbd_scheme_variations.csv"
    return recordSensitivityScheme(DV, all_variation_ids, path_to_csv; initial_header_names=String[])
end

function recordRBDSchemeRulesetsVariations(DV::Vector{DistributedVariation}, all_rulesets_variation_ids::Matrix{Int}, path_to_folder::String)
    path_to_csv = "$(path_to_folder)/rbd_scheme_rulesets_variations.csv"
    return recordSensitivityScheme(DV, all_rulesets_variation_ids, path_to_csv; initial_header_names=String[])
end

############# Generic Helper Functions #############

function recordSensitivityScheme(DV::Vector{DistributedVariation}, all_variation_ids::Matrix{Int}, path_to_csv::String; initial_header_names::Vector{String}=["base"])
    header_line = [initial_header_names..., [xmlPathToColumnName(dv.xml_path) for dv in DV]...]
    lines_df = DataFrame(all_variation_ids, header_line)
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
        println("sim_values = $sim_values")
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
    