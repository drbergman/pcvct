using Distributions, DataFrames, CSV, Sobol, FFTW
import GlobalSensitivity # do not bring in their definition of Sobol as it conflicts with the Sobol module

export MOAT, Sobolʼ, RBD

abstract type GSAMethod end
abstract type GSASampling end

getMonadIDDataFrame(gsa_sampling::GSASampling) = gsa_sampling.monad_ids_df
getSimulationIDs(gsa_sampling::GSASampling) = getSimulationIDs(gsa_sampling.sampling)

function methodString(gsa_sampling::GSASampling)
    method = typeof(gsa_sampling) |> string |> lowercase
    method = split(method, ".")[end] # remove module name that comes with the type, e.g. main.vctmodule.moatsampling -> moatsampling
    return endswith(method, "sampling") ? method[1:end-8] : method
end

"""
    run(method::GSAMethod, args...; functions::Vector{<:Function}=Function[], kwargs...)

Run a global sensitivity analysis method on the given arguments.

# Arguments
- `method::GSAMethod`: the method to run. Options are [`MOAT`](@ref), [`Sobolʼ`](@ref), and [`RBD`](@ref).
- `n_replicates::Int`: the number of replicates to run for each monad, i.e., at each sampled parameter vector.
- `inputs::InputFolders`: the input folders shared across all simuations to run.
- `evs::Vector{<:ElementaryVariation}`: the elementary variations to sample. These can be either [`DiscreteVariation`](@ref)'s or [`DistributedVariation`](@ref)'s.

Alternatively, the third argument, `inputs`, can be replaced with a `reference::AbstractMonad`, i.e., a simulation or monad to be the reference.
This should be preferred to setting reference variation IDs manually, i.e., if not using the base files in the input folders.

# Keyword Arguments
The three `reference_` keyword arguments are only compatible when the third argument is of type `InputFolders`.
- `reference_config_variation_id::Int=0`: the reference config variation ID
- `reference_rulesets_variation_id::Int=0`: the reference rulesets variation ID
- `reference_ic_cell_variation_id::Int=0`: the reference IC cell variation ID
- `ignore_indices::Vector{Int}=[]`: indices into `evs` to ignore when perturbing the parameters. Only used for Sobolʼ. See [`Sobolʼ`](@ref) for a use case.
- `force_recompile::Bool=false`: whether to force recompilation of the simulation code
- `prune_options::PruneOptions=PruneOptions()`: the options for pruning the simulation results
- `use_previous::Bool=true`: whether to use previous simulation results if they exist
- `functions::Vector{<:Function}=Function[]`: the functions to calculate the sensitivity indices for. Each function must take a simulation ID as the singular input and return a real number.
"""
function run(method::GSAMethod, n_replicates::Integer, inputs::InputFolders, evs::Union{ElementaryVariation,Vector{<:ElementaryVariation}}; functions::Vector{<:Function}=Function[], kwargs...)
    if evs isa ElementaryVariation
        evs = [evs]
    end
    gsa_sampling = _runSensitivitySampling(method, n_replicates, inputs, evs; kwargs...)
    sensitivityResults!(gsa_sampling, functions)
    return gsa_sampling
end

function run(method::GSAMethod, n_replicates::Integer, reference::AbstractMonad, evs::Union{ElementaryVariation,Vector{<:ElementaryVariation}}; functions::Vector{<:Function}=Function[], kwargs...)
    return run(method, n_replicates, reference.inputs, evs;
               reference_config_variation_id=reference.variation_ids.config,
               reference_rulesets_variation_id=reference.variation_ids.rulesets_collection,
               reference_ic_cell_variation_id=reference.variation_ids.ic_cell,
               functions=functions, kwargs...)
end

function sensitivityResults!(gsa_sampling::GSASampling, functions::Vector{<:Function})
    calculateGSA!(gsa_sampling, functions)
    recordSensitivityScheme(gsa_sampling)
end

############# Morris One-At-A-Time (MOAT) #############

"""
    MOAT

Store the information necessary to run a Morris One-At-A-Time (MOAT) global sensitivity analysis.

# Fields
- `lhs_variation::LHSVariation`: the Latin Hypercube Sampling (LHS) variation to use for the MOAT. See [`LHSVariation`](@ref).

# Examples
Note: any keyword arguments in the `MOAT` constructor are passed to [`LHSVariation`](@ref).
```
MOAT() # default to 15 base points
MOAT(10) # 10 base points
MOAT(10; add_noise=true) # do not restrict the base points to the center of their cells
```
"""
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

function _runSensitivitySampling(method::MOAT, n_replicates::Int, inputs::InputFolders, evs::Vector{<:ElementaryVariation};
    reference_config_variation_id::Int=0, reference_rulesets_variation_id::Int=0,
    reference_ic_cell_variation_id::Int=inputs.ic_cell.folder=="" ? -1 : 0,
    ignore_indices::Vector{Int}=Int[], force_recompile::Bool=false, prune_options::PruneOptions=PruneOptions(), use_previous::Bool=true)

    if !isempty(ignore_indices)
        error("MOAT does not support ignoring indices...yet? Only Sobolʼ does for now.")
    end
    config_variation_ids, rulesets_collection_variation_ids, ic_cell_variation_ids = addVariations(method.lhs_variation, inputs, evs; reference_config_variation_id=reference_config_variation_id, reference_rulesets_variation_id=reference_rulesets_variation_id, reference_ic_cell_variation_id=reference_ic_cell_variation_id)
    perturbed_config_variation_ids = repeat(config_variation_ids, 1, length(evs))
    perturbed_rulesets_variation_ids = repeat(rulesets_collection_variation_ids, 1, length(evs))
    perturbed_ic_cell_variation_ids = repeat(ic_cell_variation_ids, 1, length(evs))
    for (base_point_ind, (config_variation_id, rulesets_collection_variation_id, ic_cell_variation_id)) in enumerate(zip(config_variation_ids, rulesets_collection_variation_ids, ic_cell_variation_ids)) # for each base point in the LHS
        for (par_ind, ev) in enumerate(evs) # perturb each parameter one time
            loc = location(ev)
            if loc == :config
                perturbed_config_variation_ids[base_point_ind, par_ind] = perturbConfigVariation(ev, config_variation_id, inputs.config.folder)
            elseif loc == :rulesets
                perturbed_rulesets_variation_ids[base_point_ind, par_ind] = perturbRulesetsVariation(ev, rulesets_collection_variation_id, inputs.rulesets_collection.folder)
            elseif loc == :ic_cell
                perturbed_ic_cell_variation_ids[base_point_ind, par_ind] = perturbICCellVariation(ev, ic_cell_variation_id, inputs.ic_cell.folder)
            else
                error("Unknown variation location: $loc")
            end
        end
    end
    all_config_variation_ids = hcat(config_variation_ids, perturbed_config_variation_ids)
    all_rulesets_variation_ids = hcat(rulesets_collection_variation_ids, perturbed_rulesets_variation_ids)
    all_ic_cell_variation_ids = hcat(ic_cell_variation_ids, perturbed_ic_cell_variation_ids)
    monad_dict, monad_ids = variationsToMonads(inputs, all_config_variation_ids, all_rulesets_variation_ids, all_ic_cell_variation_ids, use_previous)
    header_line = ["base"; columnName.(evs)]
    monad_ids_df = DataFrame(monad_ids, header_line)
    sampling = Sampling(n_replicates, monad_dict |> values |> collect)
    out = run(sampling; force_recompile=force_recompile, prune_options=prune_options)
    return MOATSampling(sampling, monad_ids_df)
end

function perturbConfigVariation(ev::ElementaryVariation, config_variation_id::Int, folder::String)
    base_value = configValue(ev, config_variation_id, folder)
    addFn = (discrete_variation) -> gridToDB([discrete_variation], prepareConfigVariationFunctions(retrieveID("configs", folder), [discrete_variation]; reference_config_variation_id=config_variation_id)...)
    return makePerturbation(ev, base_value, addFn)
end

function perturbRulesetsVariation(ev::ElementaryVariation, rulesets_collection_variation_id::Int, folder::String)
    base_value = rulesetsValue(ev, rulesets_collection_variation_id, folder)
    addFn = (discrete_variation) -> gridToDB([discrete_variation], prepareRulesetsVariationFunctions(retrieveID("rulesets_collections", folder); reference_rulesets_variation_id=rulesets_collection_variation_id)...)
    return makePerturbation(ev, base_value, addFn)
end

function perturbICCellVariation(ev::ElementaryVariation, ic_cell_variation_id::Int, folder::String)
    base_value = icCellBaseValue(ev, ic_cell_variation_id, folder)
    addFn = (discrete_variation) -> gridToDB([discrete_variation], prepareICCellVariationFunctions(retrieveID("ic_cells", folder); reference_ic_cell_variation_id=ic_cell_variation_id)...)
    return makePerturbation(ev, base_value, addFn)
end

function makePerturbation(ev::ElementaryVariation, base_value::Real, addFn::Function)
    cdf_at_base = cdf(ev, base_value)
    dcdf = cdf_at_base < 0.5 ? 0.5 : -0.5
    new_value = _values(ev, cdf_at_base + dcdf) # note, this is a vector of values

    discrete_variation = DiscreteVariation(target(ev), new_value)

    new_variation_id = addFn(discrete_variation)
    @assert length(new_variation_id) == 1 "Only doing one perturbation at a time."
    return new_variation_id[1]
end

configValue(ev::ElementaryVariation, args...) = configValue(columnName(ev), args...)

function configValue(column_name::String, config_variation_id::Int, folder::String)
    query = constructSelectQuery("config_variations", "WHERE config_variation_id=$config_variation_id;"; selection="\"$(column_name)\"")
    variation_value_df = queryToDataFrame(query; db=configDB(folder), is_row=true)
    return variation_value_df[1,1]
end

rulesetsValue(ev::ElementaryVariation, args...) = rulesetsValue(columnName(ev), args...)

function rulesetsValue(column_name::String, rulesets_collection_variation_id::Int, folder::String)
    query = constructSelectQuery("rulesets_collection_variations", "WHERE rulesets_collection_variation_id=$rulesets_collection_variation_id;"; selection="\"$(column_name)\"")
    variation_value_df = queryToDataFrame(query; db=rulesetsCollectionDB(folder), is_row=true)
    return variation_value_df[1,1]
end

icCellBaseValue(ev::ElementaryVariation, args...) = icCellBaseValue(columnName(ev), args...)

function icCellBaseValue(column_name::String, ic_cell_variation_id::Int, folder::String)
    query = constructSelectQuery("ic_cell_variations", "WHERE ic_cell_variation_id=$ic_cell_variation_id;"; selection="\"$(column_name)\"")
    variation_value_df = queryToDataFrame(query; db=icCellDB(folder), is_row=true)
    return variation_value_df[1,1]
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

"""
    Sobolʼ

Store the information necessary to run a Sobol' global sensitivity analysis as well as how to extract the first and total order indices.

The rasp symbol is used to avoid conflict with the Sobol module. To type it in VS Code, use `\\rasp` and then press `tab`.
The methods available for the first order indices are `:Sobol1993`, `:Jansen1999`, and `:Saltelli2010`. Default is `:Jansen1999`.
The methods available for the total order indices are `:Homma1996`, `:Jansen1999`, and `:Sobol2007`. Default is `:Jansen1999`.

# Fields
- `sobol_variation::SobolVariation`: the Sobol' variation to use for the Sobol' analysis. See [`SobolVariation`](@ref).
- `sobol_index_methods::NamedTuple{(:first_order, :total_order), Tuple{Symbol, Symbol}}`: the methods to use for calculating the first and total order indices.

# Examples
Note: any keyword arguments in the `Sobolʼ` constructor are passed to [`SobolVariation`](@ref), except for the `sobol_index_methods` keyword argument.
Do not use the `n_matrices` keyword argument in the `SobolVariation` constructor as it is set to 2 as required for Sobol' analysis.
```
Sobolʼ(15) # 15 points from the Sobol' sequence
Sobolʼ(15; sobol_index_methods=(first_order=:Jansen1999, total_order=:Jansen1999)) # use Jansen, 1999 for both first and total order indices
Sobolʼ(15; randomization=NoRand())` # use the default Sobol' sequence with no randomization. See GlobalSensitivity.jl for more options.
Sobolʼ(15; skip_start=true) # force the Sobol' sequence to skip to the lowest denominator in the sequence that can hold 15 points, i.e., choose from [1/32, 3/32, 5/32, ..., 31/32]
Sobolʼ(15; skip_start=false) # force the Sobol' sequence to start at the beginning, i.e. [0, 0.5, 0.25, 0.75, ...]
Sobolʼ(15; include_one=true) # force the Sobol' sequence to include 1 in the sequence
```
"""
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

function _runSensitivitySampling(method::Sobolʼ, n_replicates::Int, inputs::InputFolders, evs::Vector{<:ElementaryVariation};
    reference_config_variation_id::Int=0, reference_rulesets_variation_id::Int=0,
    reference_ic_cell_variation_id::Int=inputs.ic_cell.folder=="" ? -1 : 0,
    ignore_indices::Vector{Int}=Int[], force_recompile::Bool=false, prune_options::PruneOptions=PruneOptions(), use_previous::Bool=true)

    config_id = retrieveID("configs", inputs.config.folder)
    rulesets_collection_id = retrieveID("rulesets_collections", inputs.rulesets_collection.folder)
    ic_cell_id = retrieveID("ic_cells", inputs.ic_cell.folder)
    reference_variation_ids = VariationIDs(reference_config_variation_id, reference_rulesets_variation_id, reference_ic_cell_variation_id)
    config_variation_ids, rulesets_collection_variation_ids, ic_cell_variation_ids, cdfs, parsed_variations =
        addVariations(method.sobol_variation, inputs, evs, reference_variation_ids)
    d_config = length(parsed_variations.config_variations)
    d_rulesets = length(parsed_variations.rulesets_collection_variations)
    d_ic_cell = length(parsed_variations.ic_cell_variations)
    d = d_config + d_rulesets + d_ic_cell
    focus_indices = [i for i in 1:d if !(i in ignore_indices)]
    config_variation_ids_A = config_variation_ids[:,1]
    rulesets_variation_ids_A = rulesets_collection_variation_ids[:,1]
    ic_cell_variation_ids_A = ic_cell_variation_ids[:,1]
    A = cdfs[:,1,:] # cdfs is of size (d, 2, n)
    config_variation_ids_B = config_variation_ids[:,2]
    rulesets_variation_ids_B = rulesets_collection_variation_ids[:,2]
    ic_cell_variation_ids_B = ic_cell_variation_ids[:,2]
    B = cdfs[:,2,:]
    Aᵦ = [i => copy(A) for i in focus_indices] |> Dict
    config_variation_ids_Aᵦ = [i => copy(config_variation_ids_A) for i in focus_indices] |> Dict
    rulesets_variation_ids_Aᵦ = [i => copy(rulesets_variation_ids_A) for i in focus_indices] |> Dict
    ic_cell_variation_ids_Aᵦ = [i => copy(ic_cell_variation_ids_A) for i in focus_indices] |> Dict
    for i in focus_indices
        Aᵦ[i][i,:] .= B[i,:]
        if i in parsed_variations.config_variation_indices
            fns = prepareConfigVariationFunctions(config_id, parsed_variations.config_variations; reference_config_variation_id=reference_config_variation_id)
            config_variation_ids_Aᵦ[i][:] .= cdfsToVariations(Aᵦ[i][parsed_variations.config_variation_indices,:]', parsed_variations.config_variations, fns...)
        elseif i in parsed_variations.rulesets_variation_indices
            fns = prepareRulesetsVariationFunctions(rulesets_collection_id; reference_rulesets_variation_id=reference_rulesets_variation_id)
            rulesets_variation_ids_Aᵦ[i][:] .= cdfsToVariations(Aᵦ[i][parsed_variations.rulesets_variation_indices,:]', parsed_variations.rulesets_collection_variations, fns...)
        elseif i in parsed_variations.ic_cell_variation_indices
            fns = prepareICCellVariationFunctions(ic_cell_id; reference_ic_cell_variation_id=reference_ic_cell_variation_id)
            ic_cell_variation_ids_Aᵦ[i][:] .= cdfsToVariations(Aᵦ[i][parsed_variations.ic_cell_variation_indices,:]', parsed_variations.ic_cell_variations, fns...)
        else
            throw(ArgumentError("Unknown variation index: $i"))
        end
    end
    all_config_variation_ids = hcat(config_variation_ids_A, config_variation_ids_B, [config_variation_ids_Aᵦ[i] for i in focus_indices]...) # make sure to the values from the dict in the expected order
    all_rulesets_variation_ids = hcat(rulesets_variation_ids_A, rulesets_variation_ids_B, [rulesets_variation_ids_Aᵦ[i] for i in focus_indices]...)
    all_ic_cell_variation_ids = hcat(ic_cell_variation_ids_A, ic_cell_variation_ids_B, [ic_cell_variation_ids_Aᵦ[i] for i in focus_indices]...)
    monad_dict, monad_ids = variationsToMonads(inputs, all_config_variation_ids, all_rulesets_variation_ids, all_ic_cell_variation_ids, use_previous)
    monads = monad_dict |> values |> collect
    header_line = ["A"; "B"; columnName.(evs[focus_indices])]
    monad_ids_df = DataFrame(monad_ids, header_line)
    sampling = Sampling(n_replicates, monads)
    out = run(sampling; force_recompile=force_recompile, prune_options=prune_options)
    return SobolSampling(sampling, monad_ids_df; sobol_index_methods=method.sobol_index_methods)
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

"""
    RBD

Store the information necessary to run a Random Balance Design (RBD) global sensitivity analysis.

By default, `RBD` will use the Sobol' sequence to sample the parameter space.
See below for how to turn this off.
Currently, users cannot control the Sobolʼ sequence used in RBD to the same degree it can be controlled in Sobolʼ.
Open an [Issue](https://github.com/drbergman/pcvct/issues) if you would like this feature.

# Fields
- `rbd_variation::RBDVariation`: the RBD variation to use for the RBD analysis. See [`RBDVariation`](@ref).
- `num_harmonics::Int`: the number of harmonics to use from the Fourier transform for the RBD analysis.

# Examples
Note: any keyword arguments in the `RBD` constructor are passed to [`RBDVariation`](@ref), except for the `num_harmonics` keyword argument.
If `num_harmonics` is not specified, it defaults to 6.
```
RBD(15) # 15 points from the Sobol' sequence
RBD(15; num_harmonics=10) # use 10 harmonics
RBD(15; use_sobol=false) # opt out of using the Sobol' sequence, instead using a random sequence in each dimension
```
"""
struct RBD <: GSAMethod # the prime symbol is used to avoid conflict with the Sobol module
    rbd_variation::RBDVariation
    num_harmonics::Int
end

RBD(n::Integer; num_harmonics::Integer=6, kwargs...) = RBD(RBDVariation(n; kwargs...), num_harmonics)

struct RBDSampling <: GSASampling
    sampling::Sampling
    monad_ids_df::DataFrame
    results::Dict{Function, Vector{<:Real}}
    num_harmonics::Int
    num_cycles::Union{Int, Rational}
end

RBDSampling(sampling::Sampling, monad_ids_df::DataFrame, num_cycles; num_harmonics::Int=6) = RBDSampling(sampling, monad_ids_df, Dict{Function, GlobalSensitivity.SobolResult}(), num_harmonics, num_cycles)

function _runSensitivitySampling(method::RBD, n_replicates::Int, inputs::InputFolders, evs::Vector{<:ElementaryVariation};
    reference_config_variation_id::Int=0, reference_rulesets_variation_id::Int=0, reference_ic_cell_variation_id::Int=inputs.ic_cell.folder=="" ? -1 : 0,
    ignore_indices::Vector{Int}=Int[], force_recompile::Bool=false, prune_options::PruneOptions=PruneOptions(), use_previous::Bool=true)
    if !isempty(ignore_indices)
        error("RBD does not support ignoring indices...yet? Only Sobolʼ does for now.")
    end
    config_variation_ids, rulesets_collection_variation_ids, ic_cell_variation_ids, config_variations_matrix, rulesets_variations_matrix, ic_cell_variations_matrix = addVariations(method.rbd_variation, inputs, evs; reference_config_variation_id=reference_config_variation_id, reference_rulesets_variation_id=reference_rulesets_variation_id, reference_ic_cell_variation_id=reference_ic_cell_variation_id)
    monad_dict, monad_ids = variationsToMonads(inputs, config_variations_matrix, rulesets_variations_matrix, ic_cell_variations_matrix, use_previous)
    monads = monad_dict |> values |> collect
    header_line = columnName.(evs)
    monad_ids_df = DataFrame(monad_ids, header_line)
    sampling = Sampling(n_replicates, monads)
    out = run(sampling; force_recompile=force_recompile, prune_options=prune_options)
    return RBDSampling(sampling, monad_ids_df, method.rbd_variation.num_cycles; num_harmonics=method.num_harmonics)
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

"""
    variationsToMonads(inputs::InputFolders, all_config_variation_ids::Matrix{Int}, all_rulesets_variation_ids::Matrix{Int}, all_ic_cell_variation_ids::Matrix{Int}, use_previous::Bool)

Return a dictionary of monads and a matrix of monad IDs based on the given variation IDs.

The three matrix inputs together define a single matrix of variation IDs.
This information, together with the `inputs`, identifies the monads to be used.
The `use_previous` flag determines whether to use previous simulations, if they exist.

# Returns
- `monad_dict::Dict{VariationIDs, Monad}`: a dictionary of the monads to be used without duplicates.
- `monad_ids::Matrix{Int}`: a matrix of the monad IDs to be used. Matches the shape of the input IDs matrices.
"""
function variationsToMonads(inputs::InputFolders, all_config_variation_ids::Matrix{Int}, all_rulesets_variation_ids::Matrix{Int}, all_ic_cell_variation_ids::Matrix{Int}, use_previous::Bool)
    monad_dict = Dict{VariationIDs, Monad}()
    monad_ids = zeros(Int, size(all_config_variation_ids))
    for (i, (config_variation_id, rulesets_collection_variation_id, ic_cell_variation_id)) in enumerate(zip(all_config_variation_ids, all_rulesets_variation_ids, all_ic_cell_variation_ids))
        variation_ids = VariationIDs(config_variation_id, rulesets_collection_variation_id, ic_cell_variation_id)
        if variation_ids in keys(monad_dict)
            monad_ids[i] = monad_dict[variation_ids].id
            continue
        end
        monad = Monad(inputs, variation_ids; use_previous=use_previous)
        monad_dict[variation_ids] = monad
        monad_ids[i] = monad.id
    end
    return monad_dict, monad_ids
end