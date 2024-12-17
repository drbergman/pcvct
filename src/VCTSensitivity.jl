using Distributions, DataFrames, CSV, Sobol, FFTW
import GlobalSensitivity # do not bring in their definition of Sobol as it conflicts with the Sobol module

export sensitivitySampling, MOAT, Sobolʼ, RBD

abstract type GSAMethod end
abstract type GSASampling end

getMonadIDDataFrame(gsa_sampling::GSASampling) = gsa_sampling.monad_ids_df

function methodString(gsa_sampling::GSASampling)
    method = typeof(gsa_sampling) |> string |> lowercase
    method = split(method, ".")[end] # remove module name that comes with the type, e.g. main.vctmodule.moatsampling -> moatsampling
    return endswith(method, "sampling") ? method[1:end-8] : method
end

function sensitivitySampling(args...; functions::Vector{<:Function}=Function[], kwargs...)
    gsa_sampling = _runSensitivitySampling(args...; kwargs...)
    sensitivityResults!(gsa_sampling, functions)
    return gsa_sampling
end

function sensitivityResults!(gsa_sampling::GSASampling, functions::Vector{<:Function})
    calculateGSA!(gsa_sampling, functions)
    recordSensitivityScheme(gsa_sampling)
end

############# Morris One-At-A-Time (MOAT) #############

struct MOAT <: GSAMethod
    lhs_variation::LHSVariation
end

MOAT() = MOAT(LHSVariation(15)) # default to 15 points
MOAT(n::Int; kwargs...) = MOAT(LHSVariation(n; kwargs...))

struct MOATSampling <: GSASampling
    sampling::Sampling
    monad_ids_df::DataFrame
    results::Dict{Function, GlobalSensitivity.MorrisResult}
end

MOATSampling(sampling::Sampling, monad_ids_df::DataFrame) = MOATSampling(sampling, monad_ids_df, Dict{Function, GlobalSensitivity.MorrisResult}())

_runSensitivitySampling(method::MOAT, args...; kwargs...) = moatSensitivity(method, args...; kwargs...)

function moatSensitivity(method::MOAT, monad_min_length::Int, folder_names::AbstractSamplingFolders, AV::Vector{<:AbstractVariation}; reference_config_variation_id::Int=0, reference_rulesets_variation_id::Int=0, reference_ic_cell_variation_id::Int=folder_names.ic_cell_folder=="" ? -1 : 0, ignore_indices::Vector{Int}=Int[], force_recompile::Bool=true, prune_options::PruneOptions=PruneOptions())
    if !isempty(ignore_indices)
        error("MOAT does not support ignoring indices...yet? Only Sobolʼ does for now.")
    end
    config_variation_ids, rulesets_variation_ids, ic_cell_variation_ids = addVariations(method.lhs_variation, folder_names.config_folder, folder_names.rulesets_collection_folder, folder_names.ic_cell_folder, AV; reference_config_variation_id=reference_config_variation_id, reference_rulesets_variation_id=reference_rulesets_variation_id, reference_ic_cell_variation_id=reference_ic_cell_variation_id)
    perturbed_config_variation_ids = repeat(config_variation_ids, 1, length(AV))
    perturbed_rulesets_variation_ids = repeat(rulesets_variation_ids, 1, length(AV))
    perturbed_ic_cell_variation_ids = repeat(ic_cell_variation_ids, 1, length(AV))
    for (base_point_ind, (config_variation_id, rulesets_variation_id, ic_cell_variation_id)) in enumerate(zip(config_variation_ids, rulesets_variation_ids, ic_cell_variation_ids)) # for each base point in the LHS
        for (par_ind, av) in enumerate(AV) # perturb each parameter one time
            variation_target = variationTarget(av)
            if variation_target == :config
                perturbed_config_variation_ids[base_point_ind, par_ind] = perturbConfigVariation(av, config_variation_id, folder_names.config_folder)
            elseif variation_target == :rulesets
                perturbed_rulesets_variation_ids[base_point_ind, par_ind] = perturbRulesetsVariation(av, rulesets_variation_id, folder_names.rulesets_collection_folder)
            elseif variation_target == :ic_cell
                perturbed_ic_cell_variation_ids[base_point_ind, par_ind] = perturbICCellVariation(av, ic_cell_variation_id, folder_names.ic_cell_folder)
            else
                error("Unknown variation target: $variation_target")
            end
        end
    end
    all_config_variation_ids = hcat(config_variation_ids, perturbed_config_variation_ids)
    all_rulesets_variation_ids = hcat(rulesets_variation_ids, perturbed_rulesets_variation_ids)
    all_ic_cell_variation_ids = hcat(ic_cell_variation_ids, perturbed_ic_cell_variation_ids)
    monad_dict, monad_ids = variationsToMonads(folder_names, all_config_variation_ids, all_rulesets_variation_ids, all_ic_cell_variation_ids)
    header_line = ["base", [columnName(av) for av in AV]...]
    monad_ids_df = DataFrame(monad_ids, header_line)
    sampling = Sampling(monad_min_length, monad_dict |> values |> collect)
    n_success = run(sampling; force_recompile=force_recompile, prune_options=PruneOptions())
    return MOATSampling(sampling, monad_ids_df)
end

function moatSensitivity(n_points::Int, monad_min_length::Int, folder_names::AbstractSamplingFolders, AV::Vector{<:AbstractVariation}; add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG, orthogonalize::Bool=true, kwargs...)
    lhs_variation = LHSVariation(n_points; add_noise=add_noise, rng=rng, orthogonalize=orthogonalize)
    return moatSensitivity(lhs_variation, monad_min_length, folder_names, AV; kwargs...)
end

function perturbConfigVariation(av::AbstractVariation, config_variation_id::Int, folder::String)
    base_value = getConfigBaseValue(columnName(av), config_variation_id, folder)
    addFn = (discrete_variation) -> gridToDB([discrete_variation], prepareConfigVariationFunctions(retrieveID("configs", folder), [discrete_variation]; reference_config_variation_id=config_variation_id)...)
    return makePerturbation(av, base_value, addFn)
end

function perturbRulesetsVariation(av::AbstractVariation, rulesets_variation_id::Int, folder::String)
    base_value = getRulesetsBaseValue(columnName(av), rulesets_variation_id, folder)
    addFn = (discrete_variation) -> gridToDB([discrete_variation], prepareRulesetsVariationFunctions(retrieveID("rulesets_collections", folder); reference_rulesets_variation_id=rulesets_variation_id)...)
    return makePerturbation(av, base_value, addFn)
end

function perturbICCellVariation(av::AbstractVariation, ic_cell_variation_id::Int, folder::String)
    base_value = getICCellBaseValue(columnName(av), ic_cell_variation_id, folder)
    addFn = (discrete_variation) -> gridToDB([discrete_variation], prepareICCellVariationFunctions(retrieveID("ic_cells", folder); reference_ic_cell_variation_id=ic_cell_variation_id)...)
    return makePerturbation(av, base_value, addFn)
end

function makePerturbation(av::AbstractVariation, base_value::Real, addFn::Function)
    cdf_at_base = cdf(av, base_value)
    dcdf = cdf_at_base < 0.5 ? 0.5 : -0.5
    new_value = _values(av, cdf_at_base + dcdf) # note, this is a vector of values

    discrete_variation = DiscreteVariation(xmlPath(av), new_value)

    new_variation_id = addFn(discrete_variation)
    @assert length(new_variation_id) == 1 "Only doing one perturbation at a time."
    return new_variation_id[1]
end

function getConfigBaseValue(av::AbstractVariation, config_variation_id::Int, folder::String)
    column_name = columnName(av)
    return getConfigBaseValue(column_name, config_variation_id, folder)
end

function getConfigBaseValue(column_name::String, config_variation_id::Int, folder::String)
    query = constructSelectQuery("config_variations", "WHERE config_variation_id=$config_variation_id;"; selection="\"$(column_name)\"")
    variation_value_df = queryToDataFrame(query; db=configDB(folder), is_row=true)
    return variation_value_df[1,1]
end

function getRulesetsBaseValue(av::AbstractVariation, rulesets_variation_id::Int, folder::String)
    column_name = columnName(av)
    return getRulesetsBaseValue(column_name, rulesets_variation_id, folder)
end

function getRulesetsBaseValue(column_name::String, rulesets_variation_id::Int, folder::String)
    query = constructSelectQuery("rulesets_variations", "WHERE rulesets_variation_id=$rulesets_variation_id;"; selection="\"$(column_name)\"")
    variation_value_df = queryToDataFrame(query; db=rulesetsCollectionDB(folder), is_row=true)
    return variation_value_df[1,1]
end

function getICCellBaseValue(av::AbstractVariation, ic_cell_variation_id::Int, folder::String)
    column_name = columnName(av)
    return getICCellBaseValue(column_name, ic_cell_variation_id, folder)
end

function getICCellBaseValue(column_name::String, ic_cell_variation_id::Int, folder::String)
    query = constructSelectQuery("ic_cell_variations", "WHERE ic_cell_variation_id=$ic_cell_variation_id;"; selection="\"$(column_name)\"")
    variation_value_df = queryToDataFrame(query; db=icCellDB(folder), is_row=true)
    return variation_value_df[1,1]
end

function getBaseValue(av::AbstractVariation, variation_id::Int, folder_names::AbstractSamplingFolders)
    variation_target = variationTarget(av)
    if variation_target == :config
        return getConfigBaseValue(av, variation_id, folder_names.config_folder)
    elseif variation_target == :rulesets
        return getRulesetsBaseValue(av, variation_id, folder_names.rulesets_collection_folder)
    elseif variation_target == :ic_cell
        return getICCellBaseValue(av, variation_id, folder_names.ic_cell_folder)
    else
        error("Unknown variation target: $variation_target")
    end
end

function calculateGSA!(moat_sampling::MOATSampling, functions::Vector{<:Function})
    for f in functions
        calculateGSA!(moat_sampling, f)
    end
    return
end

function calculateGSA!(moat_sampling::MOATSampling, f::Function)
    if f in keys(moat_sampling.results)
        return
    end
    values = evaluateFunctionOnSampling(moat_sampling, f)
    effects = 2 * (values[:,2:end] .- values[:,1]) # all diffs in the design matrix are 0.5
    means = mean(effects, dims=1)
    means_star = mean(abs.(effects), dims=1)
    variances = var(effects, dims=1)
    moat_sampling.results[f] = GlobalSensitivity.MorrisResult(means, means_star, variances, effects)
    return
end

############# Sobolʼ sequences and sobol indices #############

struct Sobolʼ <: GSAMethod # the prime symbol is used to avoid conflict with the Sobol module
    sobol_variation::SobolVariation
    sobol_index_methods::NamedTuple{(:first_order, :total_order), Tuple{Symbol, Symbol}}
end

Sobolʼ(n::Int; sobol_index_methods::NamedTuple{(:first_order, :total_order), Tuple{Symbol, Symbol}}=(first_order=:Jansen1999, total_order=:Jansen1999), kwargs...) = 
    Sobolʼ(SobolVariation(n; n_matrices=2, kwargs...), sobol_index_methods)

struct SobolSampling <: GSASampling
    sampling::Sampling
    monad_ids_df::DataFrame
    results::Dict{Function, GlobalSensitivity.SobolResult}
    sobol_index_methods::NamedTuple{(:first_order, :total_order), Tuple{Symbol, Symbol}}
end

SobolSampling(sampling::Sampling, monad_ids_df::DataFrame; sobol_index_methods::NamedTuple{(:first_order, :total_order), Tuple{Symbol, Symbol}}=(first_order=:Jansen1999, total_order=:Jansen1999)) = SobolSampling(sampling, monad_ids_df, Dict{Function, GlobalSensitivity.SobolResult}(), sobol_index_methods)

_runSensitivitySampling(method::Sobolʼ, args...; kwargs...) = sobolSensitivity(method, args...; kwargs...)

function sobolSensitivity(method::Sobolʼ, monad_min_length::Int, folder_names::AbstractSamplingFolders, AV::Vector{<:AbstractVariation}; reference_config_variation_id::Int=0, reference_rulesets_variation_id::Int=0, reference_ic_cell_variation_id::Int=folder_names.ic_cell_folder=="" ? -1 : 0, ignore_indices::Vector{Int}=Int[], force_recompile::Bool=true, prune_options::PruneOptions=PruneOptions())
    config_id = retrieveID("configs", folder_names.config_folder)
    rulesets_collection_id = retrieveID("rulesets_collections", folder_names.rulesets_collection_folder)
    ic_cell_id = retrieveID("ic_cells", folder_names.ic_cell_folder)
    config_variation_ids, rulesets_variation_ids, ic_cell_variation_ids, cdfs, parsed_variations = addVariations(method.sobol_variation, config_id, rulesets_collection_id, ic_cell_id, AV; reference_config_variation_id=reference_config_variation_id, reference_rulesets_variation_id=reference_rulesets_variation_id, reference_ic_cell_variation_id=reference_ic_cell_variation_id)
    d_config = length(parsed_variations.config_variations)
    d_rulesets = length(parsed_variations.rulesets_variations)
    d_ic_cell = length(parsed_variations.ic_cell_variations)
    d = d_config + d_rulesets + d_ic_cell
    focus_indices = [i for i in 1:d if !(i in ignore_indices)]
    config_variation_ids_A = config_variation_ids[:,1]
    rulesets_variation_ids_A = rulesets_variation_ids[:,1]
    ic_cell_variation_ids_A = ic_cell_variation_ids[:,1]
    A = cdfs[:,1,:] # cdfs is of size (d, 2, n)
    config_variation_ids_B = config_variation_ids[:,2]
    rulesets_variation_ids_B = rulesets_variation_ids[:,2]
    ic_cell_variation_ids_B = ic_cell_variation_ids[:,2]
    B = cdfs[:,2,:]
    Aᵦ = [i => copy(A) for i in focus_indices] |> Dict
    config_variation_ids_Aᵦ = [i => copy(config_variation_ids_A) for i in focus_indices] |> Dict
    rulesets_variation_ids_Aᵦ = [i => copy(rulesets_variation_ids_A) for i in focus_indices] |> Dict
    ic_cell_variation_ids_Aᵦ = [i => copy(ic_cell_variation_ids_A) for i in focus_indices] |> Dict
    for i in focus_indices
        Aᵦ[i][i,:] .= B[i,:]
        if i in parsed_variations.config_variation_indices
            config_variation_ids_Aᵦ[i][:] .= cdfsToVariations(Aᵦ[i][parsed_variations.config_variation_indices,:]', parsed_variations.config_variations, prepareConfigVariationFunctions(config_id, parsed_variations.config_variations; reference_config_variation_id=reference_config_variation_id)...)
        elseif i in parsed_variations.rulesets_variation_indices
            rulesets_variation_ids_Aᵦ[i][:] .= cdfsToVariations(Aᵦ[i][parsed_variations.rulesets_variation_indices,:]', parsed_variations.rulesets_variations, prepareRulesetsVariationFunctions(rulesets_collection_id; reference_rulesets_variation_id=reference_rulesets_variation_id)...)
        elseif i in parsed_variations.ic_cell_variation_indices
            ic_cell_variation_ids_Aᵦ[i][:] .= cdfsToVariations(Aᵦ[i][parsed_variations.ic_cell_variation_indices,:]', parsed_variations.ic_cell_variations, prepareICCellVariationFunctions(ic_cell_id; reference_ic_cell_variation_id=reference_ic_cell_variation_id)...)
        else
            throw(ArgumentError("Unknown variation index: $i"))
        end
    end
    all_config_variation_ids = hcat(config_variation_ids_A, config_variation_ids_B, [config_variation_ids_Aᵦ[i] for i in focus_indices]...) # make sure to the values from the dict in the expected order
    all_rulesets_variation_ids = hcat(rulesets_variation_ids_A, rulesets_variation_ids_B, [rulesets_variation_ids_Aᵦ[i] for i in focus_indices]...)
    all_ic_cell_variation_ids = hcat(ic_cell_variation_ids_A, ic_cell_variation_ids_B, [ic_cell_variation_ids_Aᵦ[i] for i in focus_indices]...)
    monad_dict, monad_ids = variationsToMonads(folder_names, all_config_variation_ids, all_rulesets_variation_ids, all_ic_cell_variation_ids)
    monads = monad_dict |> values |> collect
    header_line = ["A", "B", [columnName(av) for av in AV[focus_indices]]...]
    monad_ids_df = DataFrame(monad_ids, header_line)
    sampling = Sampling(monad_min_length, monads)
    n_success = run(sampling; force_recompile=force_recompile, prune_options=prune_options)
    return SobolSampling(sampling, monad_ids_df; sobol_index_methods=method.sobol_index_methods)
end

function sobolSensitivity(n_points::Int, args...; sobol_index_methods::NamedTuple{(:first_order, :total_order), Tuple{Symbol, Symbol}}=(first_order=:Jansen1999, total_order=:Jansen1999), kwargs...)
    return sobolSensitivity(Sobolʼ(n_points; sobol_index_methods=sobol_index_methods), args...; kwargs...)
end

function calculateGSA!(sobol_sampling::SobolSampling, functions::Vector{<:Function})
    for f in functions
        calculateGSA!(sobol_sampling, f)
    end
    return
end

function calculateGSA!(sobol_sampling::SobolSampling, f::Function)
    if f in keys(sobol_sampling.results)
        return
    end
    values = evaluateFunctionOnSampling(sobol_sampling, f)
    d = size(values, 2) - 2
    A_values = @view values[:, 1]
    B_values = @view values[:, 2]
    Aᵦ_values = [values[:, 2+i] for i in 1:d]
    expected_value² = mean(A_values .* B_values) # see Saltelli, 2002 Eq 21
    total_variance = var([A_values; B_values])
    first_order_variances = zeros(Float64, d)
    total_order_variances = zeros(Float64, d)
    si_method = sobol_sampling.sobol_index_methods.first_order
    st_method = sobol_sampling.sobol_index_methods.total_order
    for (i, Aᵦ) in enumerate(Aᵦ_values)
        # I found Jansen, 1999 to do best for first order variances on a simple test of f(x,y) = x.^2 + y.^2 + c with a uniform distribution on [0,1] x [0,1] including with noise added
        if si_method == :Sobol1993
            first_order_variances[i] = mean(B_values .* Aᵦ) .- expected_value² # Sobol, 1993
        elseif si_method == :Jansen1999
            first_order_variances[i] = total_variance - 0.5 * mean((B_values .- Aᵦ) .^ 2) # Jansen, 1999
        elseif si_method == :Saltelli2010
            first_order_variances[i] = mean(B_values .* (Aᵦ .- A_values)) # Saltelli, 2010
        end

        # I found Jansen, 1999 to do best for total order variances on a simple test of f(x,y) = x.^2 + y.^2 + c with a uniform distribution on [0,1] x [0,1] including with noise added
        if st_method == :Homma1996
            total_order_variances[i] = total_variance - mean(A_values .* Aᵦ) + expected_value² # Homma, 1996
        elseif st_method == :Jansen1999
            total_order_variances[i] = 0.5 * mean((Aᵦ .- A_values) .^ 2) # Jansen, 1999
        elseif st_method == :Sobol2007
            total_order_variances[i] = mean(A_values .* (A_values .- Aᵦ)) # Sobol, 2007
        end
    end

    first_order_indices = first_order_variances ./ total_variance
    total_order_indices = total_order_variances ./ total_variance

    sobol_sampling.results[f] = GlobalSensitivity.SobolResult(first_order_indices, nothing, nothing, nothing, total_order_indices, nothing) # do not yet support (S1 CIs, second order indices (S2), S2 CIs, or ST CIs)
    return
end

############# Random Balance Design (RBD) #############

struct RBD <: GSAMethod # the prime symbol is used to avoid conflict with the Sobol module
    rbd_variation::RBDVariation
    num_harmonics::Int
end

RBD(n::Int; num_harmonics::Int=6, kwargs...) = RBD(RBDVariation(n; kwargs...), num_harmonics)

struct RBDSampling <: GSASampling
    sampling::Sampling
    monad_ids_df::DataFrame
    results::Dict{Function, Vector{<:Real}}
    num_harmonics::Int
    num_cycles::Union{Int, Rational}
end

RBDSampling(sampling::Sampling, monad_ids_df::DataFrame, num_cycles; num_harmonics::Int=6) = RBDSampling(sampling, monad_ids_df, Dict{Function, GlobalSensitivity.SobolResult}(), num_harmonics, num_cycles)

_runSensitivitySampling(method::RBD, args...; kwargs...) = rbdSensitivity(method, args...; kwargs...)

function rbdSensitivity(method::RBD, monad_min_length::Int, folder_names::AbstractSamplingFolders, AV::Vector{<:AbstractVariation}; reference_config_variation_id::Int=0, reference_rulesets_variation_id::Int=0, reference_ic_cell_variation_id::Int=folder_names.ic_cell_folder=="" ? -1 : 0, ignore_indices::Vector{Int}=Int[], force_recompile::Bool=true, prune_options::PruneOptions=PruneOptions())
    if !isempty(ignore_indices)
        error("RBD does not support ignoring indices...yet? Only Sobolʼ does for now.")
    end
    config_variation_ids, rulesets_variation_ids, ic_cell_variation_ids, config_variations_matrix, rulesets_variations_matrix, ic_cell_variations_matrix = addVariations(method.rbd_variation, folder_names.config_folder, folder_names.rulesets_collection_folder, folder_names.ic_cell_folder, AV; reference_config_variation_id=reference_config_variation_id, reference_rulesets_variation_id=reference_rulesets_variation_id, reference_ic_cell_variation_id=reference_ic_cell_variation_id)
    monad_dict, monad_ids = variationsToMonads(folder_names, config_variations_matrix, rulesets_variations_matrix, ic_cell_variations_matrix)
    monads = monad_dict |> values |> collect
    header_line = [columnName(av) for av in AV]
    monad_ids_df = DataFrame(monad_ids, header_line)
    sampling = Sampling(monad_min_length, monads)
    n_success = run(sampling; force_recompile=force_recompile, prune_options=prune_options)
    return RBDSampling(sampling, monad_ids_df, method.rbd_variation.num_cycles; num_harmonics=method.num_harmonics)
end

function rbdSensitivity(n_points::Int, args...; rng::AbstractRNG=Random.GLOBAL_RNG, use_sobol::Bool=true, num_harmonics::Int=6, num_cycles::Int=missing, kwargs...)
    method = RBD(n_points; rng=rng, use_sobol=use_sobol, num_harmonics=num_harmonics, num_cycles=num_cycles)
    return rbdSensitivity(method, args...; kwargs...)
end

function calculateGSA!(rbd_sampling::RBDSampling, functions::Vector{<:Function})
    for f in functions
        calculateGSA!(rbd_sampling, f)
    end
    return
end

function calculateGSA!(rbd_sampling::RBDSampling, f::Function)
    if f in keys(rbd_sampling.results)
        return
    end
    values = evaluateFunctionOnSampling(rbd_sampling, f)
    if rbd_sampling.num_cycles == 1//2
        values = vcat(values, values[end-1:-1:2,:])
    end
    ys = fft(values, 1) .|> abs2
    ys ./= size(values, 1)
    V = sum(ys[2:end, :], dims=1)
    Vi = 2 * sum(ys[2:(rbd_sampling.num_harmonics+1), :], dims=1)
    rbd_sampling.results[f] = (Vi ./ V) |> vec
    return
end

############# Generic Helper Functions #############

function recordSensitivityScheme(gsa_sampling::GSASampling)
    method = methodString(gsa_sampling)
    path_to_csv = joinpath(outputFolder(gsa_sampling.sampling), "$(method)_scheme.csv")
    return CSV.write(path_to_csv, getMonadIDDataFrame(gsa_sampling); header=true)
end

function evaluateFunctionOnSampling(gsa_sampling::GSASampling, f::Function)
    monad_id_df = getMonadIDDataFrame(gsa_sampling)
    value_dict = Dict{Int, Float64}()
    values = zeros(Float64, size(monad_id_df))
    for (ind, monad_id) in enumerate(monad_id_df |> Matrix)
        if !(monad_id in keys(value_dict))
            simulation_ids = readMonadSimulationIDs(monad_id)
            sim_values = [f(simulation_id) for simulation_id in simulation_ids]
            value = sim_values |> mean
            value_dict[monad_id] = value
        end
        values[ind] = value_dict[monad_id]
    end
    return values
end

function variationsToMonads(folder_names::AbstractSamplingFolders, all_config_variation_ids::Matrix{Int}, all_rulesets_variation_ids::Matrix{Int}, all_ic_cell_variation_ids::Matrix{Int}=-ones(Int, size(all_config_variation_ids)))
    monad_dict = Dict{VariationIDs, Monad}()
    monad_ids = zeros(Int, size(all_config_variation_ids))
    for (i, (config_variation_id, rulesets_variation_id, ic_cell_variation_id)) in enumerate(zip(all_config_variation_ids, all_rulesets_variation_ids, all_ic_cell_variation_ids))
        variation_ids = VariationIDs(config_variation_id, rulesets_variation_id, ic_cell_variation_id)
        if variation_ids in keys(monad_dict)
            monad_ids[i] = monad_dict[variation_ids].id
            continue
        end
        monad = Monad(folder_names, variation_ids)
        monad_dict[variation_ids] = monad
        monad_ids[i] = monad.id
    end
    return monad_dict, monad_ids
end