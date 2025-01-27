using Distributions
import Distributions: cdf

export AbstractVariation, ElementaryVariation, DiscreteVariation, DistributedVariation
export GridVariation, LHSVariation, addVariations

################## Abstract Variations ##################

abstract type AbstractVariation end
abstract type ElementaryVariation <: AbstractVariation end

"""
    DiscreteVariation{T}(xml_path::Vector{<:AbstractString}, values::Vector{T}) where T

Create a `DiscreteVariation` object with the given `xml_path` and `values`.

The type `T` is inferred from the type of the `values` argument.
A singleton value can be passed in place of `values` for convenience.

# Examples
```jldoctest
julia> dv = DiscreteVariation(["overall","max_time"], [1440.0, 2880.0])
DiscreteVariation{Float64}(:config, ["overall", "max_time"], [1440.0, 2880.0])
```
```jldoctest
julia> dv = DiscreteVariation(["overall","max_time"], 1440)
DiscreteVariation{Int64}(:config, ["overall", "max_time"], [1440])
```
"""
struct DiscreteVariation{T} <: ElementaryVariation
    location::Symbol
    target::Vector{<:AbstractString}
    values::Vector{T}
    
    function DiscreteVariation(target::Vector{<:AbstractString}, values::Vector{T}) where T
        location = variationLocation(target)
        return new{T}(location, target, values)
    end
end
DiscreteVariation(xml_path::Vector{<:AbstractString}, value::T) where T = DiscreteVariation(xml_path, [value])

Base.length(discrete_variation::DiscreteVariation) = length(discrete_variation.values)

function ElementaryVariation(args...; kwargs...)
    Base.depwarn("`ElementaryVariation` is deprecated in favor of the more descriptive `DiscreteVariation`.", :ElementaryVariation; force=true)
    return DiscreteVariation(args...; kwargs...)
end

struct DistributedVariation <: ElementaryVariation
    location::Symbol
    target::Vector{<:AbstractString}
    distribution::Distribution

    function DistributedVariation(target::Vector{<:AbstractString}, distribution::Distribution)
        location = variationLocation(target)
        return new(location, target, distribution)
    end
end

target(ev::ElementaryVariation) = ev.target::Vector{<:AbstractString}
location(ev::ElementaryVariation) = ev.location
columnName(ev::ElementaryVariation) = target(ev) |> xmlPathToColumnName

function UniformDistributedVariation(xml_path::Vector{<:AbstractString}, lb::T, ub::T) where {T<:Real}
    return DistributedVariation(xml_path, Uniform(lb, ub))
end

function NormalDistributedVariation(xml_path::Vector{<:AbstractString}, mu::T, sigma::T; lb::Real=-Inf, ub::Real=Inf) where {T<:Real}
    return DistributedVariation(xml_path, truncated(Normal(mu, sigma), lb, ub))
end

_values(discrete_variation::DiscreteVariation) = discrete_variation.values

function _values(discrete_variation::DiscreteVariation, cdf::Vector{<:Real})
    index = floor.(Int, cdf * length(discrete_variation)) .+ 1
    index[index.==(length(discrete_variation)+1)] .= length(discrete_variation) # if cdf = 1, index = length(discrete_variation)+1, so we set it to length(discrete_variation)
    return discrete_variation.values[index]
end

_values(discrete_variation::DiscreteVariation, cdf::Real) = _values(discrete_variation, [cdf])

function _values(dv::DistributedVariation, cdf::Vector{<:Real})
    return map(Base.Fix1(quantile, dv.distribution), cdf)
end

_values(dv::DistributedVariation, cdf::Real) = _values(dv, [cdf])

_values(::DistributedVariation) = error("A cdf must be provided for a DistributedVariation.")
_values(ev::ElementaryVariation, cdf) = error("values not defined for $(typeof(ev)) with type of cdf = $(typeof(cdf))")

function dataType(discrete_variation::DiscreteVariation)
    return typeof(discrete_variation).parameters[1] # typeof(discrete_variation).parameters[1] is the type parameter T in the definition of DiscreteVariation{T}
end

function dataType(dv::DistributedVariation)
    return eltype(dv.distribution)
end

dataType(ev::ElementaryVariation) = error("dataType not defined for $(typeof(ev))")

function cdf(discrete_variation::DiscreteVariation, x::Real)
    if !(x in discrete_variation.values)
        error("Value not in elementary variation values.")
    end
    return (findfirst(isequal(x), discrete_variation.values) - 1) / (length(discrete_variation) - 1)
end

cdf(dv::DistributedVariation, x::Real) = cdf(dv.distribution, x)

cdf(ev::ElementaryVariation, ::Real) = error("cdf not defined for $(typeof(ev))")

function variationLocation(xml_path::Vector{<:AbstractString})
    if startswith(xml_path[1], "hypothesis_ruleset:name:")
        return :rulesets
    elseif startswith(xml_path[1], "cell_patches:name:")
        return :ic_cell
    else
        return :config
    end
end

################## Database Interface Functions ##################

function addColumns(xml_paths::Vector{Vector{String}}, table_name::String, id_column_name::String, db_columns::SQLite.DB, path_to_xml::String, dataTypeRulesFn::Function)
    column_names = queryToDataFrame("PRAGMA table_info($(table_name));"; db=db_columns) |> x->x[!,:name]
    filter!(x -> x != id_column_name, column_names)
    varied_column_names = [xmlPathToColumnName(xml_path) for xml_path in xml_paths]

    is_new_column = [!(varied_column_name in column_names) for varied_column_name in varied_column_names]
    if any(is_new_column)
        new_column_names = varied_column_names[is_new_column]
        xml_doc = openXML(path_to_xml)
        default_values_for_new = [getField(xml_doc, xml_path) for xml_path in xml_paths[is_new_column]]
        closeXML(xml_doc)
        for (i, new_column_name) in enumerate(new_column_names)
            sqlite_data_type = dataTypeRulesFn(i, new_column_name)
            DBInterface.execute(db_columns, "ALTER TABLE $(table_name) ADD COLUMN '$(new_column_name)' $(sqlite_data_type);")
        end
        DBInterface.execute(db_columns, "UPDATE $(table_name) SET ($(join("\"".*new_column_names.*"\"",",")))=($(join("\"".*default_values_for_new.*"\"",",")));") # set newly added columns to default values

        index_name = "$(table_name)_index"
        SQLite.dropindex!(db_columns, index_name; ifexists=true) # remove previous index
        index_columns = deepcopy(column_names)
        append!(index_columns, new_column_names)
        SQLite.createindex!(db_columns, table_name, index_name, index_columns; unique=true, ifnotexists=false) # add new index to make sure no variations are repeated
    end

    static_column_names = deepcopy(column_names)
    old_varied_names = varied_column_names[.!is_new_column]
    filter!(x -> !(x in old_varied_names), static_column_names)

    return static_column_names, varied_column_names
end

function addConfigVariationColumns(config_id::Int, xml_paths::Vector{Vector{String}}, variable_types::Vector{DataType})
    config_folder = configFolder(config_id)
    db_columns = configDB(config_folder)
    path_to_xml = joinpath(data_dir, "inputs", "configs", config_folder, "PhysiCell_settings.xml")
    dataTypeRulesFn = (i, _) -> begin
        if variable_types[i] == Bool
            "TEXT"
        elseif variable_types[i] <: Integer
            "INT"
        elseif variable_types[i] <: Real
            "REAL"
        else
            "TEXT"
        end
    end
    return addColumns(xml_paths, "config_variations", "config_variation_id", db_columns, path_to_xml, dataTypeRulesFn)
end

function addRulesetsVariationsColumns(rulesets_collection_id::Int, xml_paths::Vector{Vector{String}})
    rulesets_collection_folder = rulesetsCollectionFolder(rulesets_collection_id)
    db_columns = rulesetsCollectionDB(rulesets_collection_folder)
    path_to_rulesets_collection_folder = joinpath(data_dir, "inputs", "rulesets_collections", rulesets_collection_folder)
    path_to_base_xml = joinpath(path_to_rulesets_collection_folder, "base_rulesets.xml")
    if !isfile(path_to_base_xml)
        writeRules(path_to_base_xml, joinpath(path_to_rulesets_collection_folder, "base_rulesets.csv"))
    end
    dataTypeRulesFn = (_, name) -> occursin("applies_to_dead", name) ? "INT" : "REAL"
    return addColumns(xml_paths, "rulesets_collection_variations", "rulesets_collection_variation_id", db_columns, path_to_base_xml, dataTypeRulesFn)
end

function addICCellVariationColumns(ic_cell_id::Int, xml_paths::Vector{Vector{String}})
    ic_cell_folder = icCellFolder(ic_cell_id)
    db_columns = icCellDB(ic_cell_folder)
    @assert db_columns isa SQLite.DB "ic_cell_folder must contain a cells.xml file to support variations."
    path_to_ic_cell_folder = joinpath(data_dir, "inputs", "ics", "cells", ic_cell_folder)
    path_to_base_xml = joinpath(path_to_ic_cell_folder, "cells.xml")
    dataTypeRulesFn = (_, name) -> endswith(name, "number") ? "INT" : "REAL"
    return addColumns(xml_paths, "ic_cell_variations", "ic_cell_variation_id", db_columns, path_to_base_xml, dataTypeRulesFn)
end

function addRow(db_columns::SQLite.DB, table_name::String, id_name::String, table_features::String, values::String)
    new_id = DBInterface.execute(db_columns, "INSERT OR IGNORE INTO $(table_name) ($(table_features)) VALUES($(values)) RETURNING $(id_name);") |> DataFrame |> x->x[!,1]
    new_added = length(new_id)==1
    if  !new_added
        query = constructSelectQuery(table_name, "WHERE ($(table_features))=($(values))"; selection=id_name)
        new_id = queryToDataFrame(query; db=db_columns, is_row=true) |> x->x[!,1]
    end
    return new_id[1]
end

function addConfigVariationRow(config_id::Int, table_features::String, values::String)
    db_columns = configDB(config_id)
    return addRow(db_columns, "config_variations", "config_variation_id", table_features, values)
end

function addConfigVariationRow(config_id::Int, table_features::String, static_values::String, varied_values::String)
    return addConfigVariationRow(config_id, table_features, "$(static_values)$(varied_values)")
end

function addRulesetsVariationRow(rulesets_collection_id::Int, table_features::String, values::String)
    db_columns = rulesetsCollectionDB(rulesets_collection_id)
    return addRow(db_columns, "rulesets_collection_variations", "rulesets_collection_variation_id", table_features, values)
end

function addRulesetsVariationRow(rulesets_collection_id::Int, table_features::String, static_values::String, varied_values::String)
    return addRulesetsVariationRow(rulesets_collection_id, table_features, "$(static_values)$(varied_values)")
end

function addICCellVariationRow(ic_cell_id::Int, table_features::String, values::String)
    db_columns = icCellDB(ic_cell_id)
    return addRow(db_columns, "ic_cell_variations", "ic_cell_variation_id", table_features, values)
end

function addICCellVariationRow(ic_cell_id::Int, table_features::String, static_values::String, varied_values::String)
    return addICCellVariationRow(ic_cell_id, table_features, "$(static_values)$(varied_values)")
end

function setUpColumns(evs::Vector{<:ElementaryVariation}, addColumnsByPathsFn::Function, prepareAddNewFn::Function)
    xml_paths = target.(evs)

    static_column_names, varied_column_names = addColumnsByPathsFn(xml_paths)
    return prepareAddNewFn(static_column_names, varied_column_names)
end

function prepareAddNew(db_columns::SQLite.DB, static_column_names::Vector{String}, varied_column_names::Vector{String}, table_name::String, id_name::String, reference_id::Int)
    if isempty(static_column_names)
        static_values = ""
        table_features = ""
    else
        query = constructSelectQuery(table_name, "WHERE $(id_name)=$(reference_id);"; selection=join("\"" .* static_column_names .* "\"", ", "))
        static_values = queryToDataFrame(query; db=db_columns, is_row=true) |> x -> join(x |> eachcol .|> c -> "\"$(string(c[1]))\"", ",")
        table_features = join("\"" .* static_column_names .* "\"", ",")
        if !isempty(varied_column_names)
            static_values *= ","
            table_features *= ","
        end
    end
    table_features *= join("\"" .* varied_column_names .* "\"", ",")
    return static_values, table_features
end

function prepareAddNewConfigVariations(config_id::Int, static_column_names::Vector{String}, varied_column_names::Vector{String}; reference_config_variation_id::Int=0)
    db_columns = configDB(config_id)
    return prepareAddNew(db_columns, static_column_names, varied_column_names, "config_variations", "config_variation_id", reference_config_variation_id)
end

function prepareAddNewRulesetsVariations(rulesets_collection_id::Int, static_column_names::Vector{String}, varied_column_names::Vector{String}; reference_rulesets_variation_id::Int=0)
    db_columns = rulesetsCollectionDB(rulesets_collection_id)
    return prepareAddNew(db_columns, static_column_names, varied_column_names, "rulesets_collection_variations", "rulesets_collection_variation_id", reference_rulesets_variation_id)
end

function prepareAddNewICCellVariations(ic_cell_id::Int, static_column_names::Vector{String}, varied_column_names::Vector{String}; reference_ic_cell_variation_id::Int=ic_cell_id==-1 ? -1 : 0)
    db_columns = icCellDB(ic_cell_id)
    return prepareAddNew(db_columns, static_column_names, varied_column_names, "ic_cell_variations", "ic_cell_variation_id", reference_ic_cell_variation_id)
end

################## Specialized Variations ##################

abstract type AddVariationMethod end
struct GridVariation <: AddVariationMethod end
struct LHSVariation <: AddVariationMethod
    n::Int
    add_noise::Bool
    rng::AbstractRNG
    orthogonalize::Bool
end
LHSVariation(n; add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG, orthogonalize::Bool=true) = LHSVariation(n, add_noise, rng, orthogonalize)
LHSVariation(; n::Int=4, add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG, orthogonalize::Bool=true) = LHSVariation(n, add_noise, rng, orthogonalize)

struct SobolVariation <: AddVariationMethod
    n::Int
    n_matrices::Int
    randomization::RandomizationMethod
    skip_start::Union{Missing, Bool, Int}
    include_one::Union{Missing, Bool}
end
SobolVariation(n::Int; n_matrices::Int=1, randomization::RandomizationMethod=NoRand(), skip_start::Union{Missing, Bool, Int}=missing, include_one::Union{Missing, Bool}=missing) = SobolVariation(n, n_matrices, randomization, skip_start, include_one)
SobolVariation(; pow2::Int=1, n_matrices::Int=1, randomization::RandomizationMethod=NoRand(), skip_start::Union{Missing, Bool, Int}=missing, include_one::Union{Missing, Bool}=missing) = SobolVariation(2^pow2, n_matrices, randomization, skip_start, include_one)

struct RBDVariation <: AddVariationMethod
    n::Int
    rng::AbstractRNG
    use_sobol::Bool
    pow2_diff::Union{Missing, Int}
    num_cycles::Rational

    function RBDVariation(n::Int, rng::AbstractRNG, use_sobol::Bool, pow2_diff::Union{Missing, Int}, num_cycles::Union{Missing, Int, Rational})
        if use_sobol
            k = log2(n) |> round |> Int # nearest power of 2 to n
            if ismissing(pow2_diff)
                pow2_diff = n - 2^k
            else
                @assert pow2_diff == n - 2^k "pow2_diff must be n - 2^k for RBDVariation with Sobol sequence"
            end
            @assert abs(pow2_diff) <= 1 "n must be within 1 of a power of 2 for RBDVariation with Sobol sequence"
            if ismissing(num_cycles)
                num_cycles = 1//2
            else
                @assert num_cycles == 1//2 "num_cycles must be 1//2 for RBDVariation with Sobol sequence"
            end
        else
            pow2_diff = missing # not used in this case
            if ismissing(num_cycles)
                num_cycles = 1
            else
                @assert num_cycles == 1 "num_cycles must be 1 for RBDVariation with random sequence"
            end
        end
        return new(n, rng, use_sobol, pow2_diff, num_cycles)
    end
end
RBDVariation(n::Int; rng::AbstractRNG=Random.GLOBAL_RNG, use_sobol::Bool=true, pow2_diff=missing, num_cycles=missing) = RBDVariation(n, rng, use_sobol, pow2_diff, num_cycles)

function addVariations(method::AddVariationMethod, inputs::InputFolders, evs::Vector{<:ElementaryVariation};
    reference_config_variation_id::Int=0, reference_rulesets_variation_id::Int=0, reference_ic_cell_variation_id::Int=inputs.ic_cell.folder=="" ? -1 : 0)
    reference_variation_ids = VariationIDs(reference_config_variation_id, reference_rulesets_variation_id, reference_ic_cell_variation_id)
    return addVariations(method, inputs, evs, reference_variation_ids)
end

struct ParsedVariations
    config_variations::Vector{<:ElementaryVariation}
    rulesets_collection_variations::Vector{<:ElementaryVariation}
    ic_cell_variations::Vector{<:ElementaryVariation}

    config_variation_indices::Vector{Int}
    rulesets_variation_indices::Vector{Int}
    ic_cell_variation_indices::Vector{Int}

    function ParsedVariations(config_variations::Vector{<:ElementaryVariation}, rulesets_collection_variations::Vector{<:ElementaryVariation}, ic_cell_variations::Vector{<:ElementaryVariation}, config_variation_indices::Vector{Int}, rulesets_variation_indices::Vector{Int}, ic_cell_variation_indices::Vector{Int})
        @assert length(config_variations) == length(config_variation_indices) "config_variations and config_variation_indices must have the same length"
        @assert length(rulesets_collection_variations) == length(rulesets_variation_indices) "rulesets_collection_variations and rulesets_variation_indices must have the same length"
        @assert length(ic_cell_variations) == length(ic_cell_variation_indices) "ic_cell_variations and ic_cell_variation_indices must have the same length"
        return new(config_variations, rulesets_collection_variations, ic_cell_variations, config_variation_indices, rulesets_variation_indices, ic_cell_variation_indices)
    end
end

function ParsedVariations(evs::Vector{<:ElementaryVariation})
    config_variations = ElementaryVariation[]
    rulesets_collection_variations = ElementaryVariation[]
    ic_cell_variations = ElementaryVariation[]
    config_variation_indices = Int[]
    rulesets_variation_indices = Int[]
    ic_cell_variation_indices = Int[]
    for (i, ev) in enumerate(evs)
        loc = location(ev)
        if loc == :config
            push!(config_variations, ev)
            push!(config_variation_indices, i)
        elseif loc == :rulesets
            push!(rulesets_collection_variations, ev)
            push!(rulesets_variation_indices, i)
        elseif loc == :ic_cell
            push!(ic_cell_variations, ev)
            push!(ic_cell_variation_indices, i)
        else
            error("Variation type not recognized.")
        end
    end
    return ParsedVariations(config_variations, rulesets_collection_variations, ic_cell_variations, config_variation_indices, rulesets_variation_indices, ic_cell_variation_indices)
end

################## Grid Variations ##################

function addVariations(::GridVariation, inputs::InputFolders, evs::Vector{<:ElementaryVariation}, reference_variation_ids::VariationIDs)
    pvs = ParsedVariations(evs)
    if isempty(pvs.config_variations)
        config_variation_ids = [reference_variation_ids.config]
    else
        config_variation_ids = gridToDB(pvs.config_variations, prepareConfigVariationFunctions(inputs.config.id, pvs.config_variations; reference_config_variation_id=reference_variation_ids.config)...)
    end
    if isempty(pvs.rulesets_collection_variations)
        rulesets_collection_variation_ids = [reference_variation_ids.rulesets_collection]
    else
        rulesets_collection_variation_ids = gridToDB(pvs.rulesets_collection_variations, prepareRulesetsVariationFunctions(inputs.rulesets_collection.id; reference_rulesets_variation_id=reference_variation_ids.rulesets_collection)...)
    end
    if isempty(pvs.ic_cell_variations)
        ic_cell_variation_ids = [reference_variation_ids.ic_cell]
    else
        ic_cell_variation_ids = gridToDB(pvs.ic_cell_variations, prepareICCellVariationFunctions(inputs.ic_cell.id; reference_ic_cell_variation_id=reference_variation_ids.ic_cell)...)
    end
    all_config_variation_ids, all_rulesets_variation_ids, all_ic_cell_variation_ids = ndgrid(config_variation_ids, rulesets_collection_variation_ids, ic_cell_variation_ids)
    return all_config_variation_ids, all_rulesets_variation_ids, all_ic_cell_variation_ids
end

function gridToDB(evs::Vector{<:ElementaryVariation}, addColumnsByPathsFn::Function, prepareAddNewFn::Function, addRowFn::Function)
    new_values = _values.(evs)

    static_values, table_features = setUpColumns(evs, addColumnsByPathsFn, prepareAddNewFn)

    NDG = ndgrid(new_values...)
    sz_variations = size(NDG[1])
    variation_ids = zeros(Int, sz_variations)
    for i in eachindex(NDG[1])
        varied_values = [A[i] for A in NDG] .|> string |> x -> join("\"" .* x .* "\"", ",")
        variation_ids[i] = addRowFn(table_features, static_values, varied_values)
    end
    return variation_ids |> vec
end

################## Latin Hypercube Sampling Functions ##################

function orthogonalLHS(k::Int, d::Int)
    n = k^d
    lhs_inds = zeros(Int, (n, d))
    for i in 1:d
        n_bins = k^(i - 1) # number of bins from previous dims (a bin has sampled points that are in the same subelement up through i-1 dim and need to be separated in subsequent dims)
        bin_size = k^(d-i+1) # number of sampled points in each bin
        if i == 1
            lhs_inds[:, 1] = 1:n
        else
            bin_inds_gps = [(j - 1) * bin_size .+ (1:bin_size) |> collect for j in 1:n_bins] # the indices belonging to each of the bins (this relies on the sorting step below to easily find which points are currently in the same box and need to be separated along the ith dimension)
            for pt_ind = 1:bin_size # pick ith coordinate for each point in the bin; each iter here will work up the ith coordinates assigning one to each bin at each iter
                ind = zeros(Int, n_bins) # indices where the next set of ith coordinates will go
                for (j, bin_inds) in enumerate(bin_inds_gps) # pick a random, remaining element for each bin
                    rand_ind_of_ind = rand(1:length(bin_inds)) # pick the index of a remaining index
                    ind[j] = popat!(bin_inds, rand_ind_of_ind) # get the random index and remove it so we don't pick it again
                end
                lhs_inds[ind,i] = shuffle(1:n_bins) .+ (pt_ind - 1) * n_bins # for the selected inds, shuffle the next set of ith coords into them
            end
        end
        lhs_inds[:, 1:i] = sortslices(lhs_inds[:, 1:i], dims=1, by=x -> (x ./ (n / k) .|> ceil .|> Int)) # sort the found values so that sampled points in the same box upon projection into the 1:i dims are adjacent
    end
    return lhs_inds
end

# function orthogonalLHS_relaxed(k::Int, d::Int)
#     # I have this here because this technically gives all possible orthogonal lhs samples, but my orthogonalLHS gives a more uniform LHS
#     n = k^d
#     lhs_inds = zeros(Int, (n, d))
#     for i in 1:d
#         bin_size = n / (k^(i - 1)) |> ceil |> Int # number of sampled points grouped by all previous dims
#         n_bins = k^(i - 1) # number of bins in this dimension
#         if i == 1
#             lhs_inds[:, 1] = 1:n
#             continue
#         else
#             bin_inds_gps = [(j - 1) * bin_size .+ (1:bin_size) |> collect for j in 1:n_bins] # the indexes in y corresponding to each of the bins (this relies on the sorting step below to easily find which points are currently in the same box and need to be separated along the ith dimension)
#             for pt_ind = 1:k
#                 y_vals = shuffle((pt_ind - 1) * Int(n / k) .+ (1:Int(n / k)))
#                 inds = zeros(Int, Int(n / k))
#                 for (j, bin_inds) in enumerate(bin_inds_gps)
#                     for s in 1:Int(n / k^(i))
#                         rand_ind_of_ind = rand(1:length(bin_inds))
#                         rand_ind = popat!(bin_inds, rand_ind_of_ind) # random value remaining in bin, remove it so we don't pick it again
#                         inds[(j-1)*Int(n / k^(i))+s] = rand_ind # record the index
#                     end
#                 end
#                 lhs_inds[inds, i] = y_vals
#             end
#         end
#         lhs_inds[:, 1:i] = sortslices(lhs_inds[:, 1:i], dims=1, by=x -> (x ./ (n / k) .|> ceil .|> Int)) # sort the found values so that sampled points in the same box upon projection into the 1:i dims are adjacent
#     end
# end

function generateLHSCDFs(n::Int, d::Int; add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG=rng, orthogonalize::Bool=true)
    cdfs = (Float64.(1:n) .- (add_noise ? rand(rng, Float64, n) : 0.5)) / n # permute below for each parameter separately
    k = n ^ (1 / d) |> round |> Int
    if orthogonalize && (n == k^d)
        # then good to do the orthogonalization
        lhs_inds = orthogonalLHS(k, d)
    else
        lhs_inds = hcat([shuffle(rng, 1:n) for _ in 1:d]...)
    end
    return cdfs[lhs_inds]
end

function addVariations(lhs_variation::LHSVariation, inputs::InputFolders, evs::Vector{<:ElementaryVariation}, reference_variation_ids::VariationIDs)
    pvs = ParsedVariations(evs)
    d = length(pvs.config_variations) + length(pvs.rulesets_collection_variations) + length(pvs.ic_cell_variations)
    cdfs = generateLHSCDFs(lhs_variation.n, d; add_noise=lhs_variation.add_noise, rng=lhs_variation.rng, orthogonalize=lhs_variation.orthogonalize)
    if isempty(pvs.config_variations)
        config_variation_ids = fill(reference_variation_ids.config, lhs_variation.n)
    else
        config_variation_ids = cdfsToVariations(cdfs[:, 1:length(pvs.config_variations)], pvs.config_variations, prepareConfigVariationFunctions(inputs.config.id, pvs.config_variations; reference_config_variation_id=reference_variation_ids.config)...)
    end
    if isempty(pvs.rulesets_collection_variations)
        rulesets_collection_variation_ids = fill(reference_variation_ids.rulesets_collection, lhs_variation.n)
    else
        rulesets_collection_variation_ids = cdfsToVariations(cdfs[:, length(pvs.config_variations)+1:end], pvs.rulesets_collection_variations, prepareRulesetsVariationFunctions(inputs.rulesets_collection.id; reference_rulesets_variation_id=reference_variation_ids.rulesets_collection)...)
    end
    if isempty(pvs.ic_cell_variations)
        ic_cell_variation_ids = fill(reference_variation_ids.ic_cell, lhs_variation.n)
    else
        ic_cell_variation_ids = cdfsToVariations(cdfs[:, length(pvs.config_variations)+length(pvs.rulesets_collection_variations)+1:end], pvs.ic_cell_variations, prepareICCellVariationFunctions(inputs.ic_cell.id; reference_ic_cell_variation_id=reference_variation_ids.ic_cell)...)
    end
    return config_variation_ids, rulesets_collection_variation_ids, ic_cell_variation_ids
end

################## Sobol Sequence Sampling Functions ##################

function generateSobolCDFs(n::Int, d::Int; n_matrices::Int=1, T::Type=Float64, randomization::RandomizationMethod=NoRand(), skip_start::Union{Missing, Bool, Int}=missing, include_one::Union{Missing, Bool}=missing)
    s = Sobol.SobolSeq(d * n_matrices)
    if ismissing(skip_start) # default to this
        if ispow2(n + 1) # then n = 2^k - 1
            skip_start = 1 # skip the first point (0)
        else
            skip_start = false # don't skip the first point (0)
            if ispow2(n - 1) # then n = 2^k + 1
                include_one |= ismissing(include_one) # unless otherwise specified, assume the +1 is to get the boundary 1 included as well
            elseif ispow2(n) # then n = 2^k
                nothing # including 0, grab the first 2^k points
            else # not within 1 of a power of 2, just start at the beginning?
                nothing
            end
        end
    end
    n_draws = n - (include_one===true) # if include_one is true, then we need to draw n-1 points and then append 1 to the end
    if skip_start == false # false or 0
        cdfs = randomize(reduce(hcat, [zeros(T, n_matrices * d), [next!(s) for i in 1:n_draws-1]...]), randomization) # n_draws-1 because the SobolSeq already skips 0
    else
        cdfs = Matrix{T}(undef, d * n_matrices, n_draws)
        num_to_skip = skip_start === true ? ((1 << (floor(Int, log2(n_draws - 1)) + 1))) : skip_start
        num_to_skip -= 1 # the SobolSeq already skips 0
        for _ in 1:num_to_skip
            Sobol.next!(s)
        end
        for col in eachcol(cdfs)
            Sobol.next!(s, col)
        end
        cdfs = randomize(cdfs, randomization)
    end
    if include_one===true # cannot compare missing==true, but can make this comparison
        cdfs = hcat(cdfs, ones(T, d * n_matrices))
    end
    return reshape(cdfs, (d, n_matrices, n)) 
end

generateSobolCDFs(sobol_variation::SobolVariation, d::Int) = generateSobolCDFs(sobol_variation.n, d; n_matrices=sobol_variation.n_matrices, randomization=sobol_variation.randomization, skip_start=sobol_variation.skip_start, include_one=sobol_variation.include_one)

function addVariations(sobol_variation::SobolVariation, inputs::InputFolders, evs::Vector{<:ElementaryVariation}, reference_variation_ids::VariationIDs)
    pvs = ParsedVariations(evs)
    d = length(pvs.config_variations) + length(pvs.rulesets_collection_variations) + length(pvs.ic_cell_variations)
    cdfs = generateSobolCDFs(sobol_variation, d) # cdfs is (d, sobol_variation.n_matrices, sobol_variation.n)
    cdfs_reshaped = reshape(cdfs, (d, sobol_variation.n_matrices * sobol_variation.n)) # reshape to (d, sobol_variation.n_matrices * sobol_variation.n) so that each column is a sobol sample
    cdfs_reshaped = cdfs_reshaped' # transpose so that each row is a sobol sample
    if isempty(pvs.config_variations)
        config_variation_ids = fill(reference_variation_ids.config, size(cdfs_reshaped,1))
    else
        config_variation_ids = cdfsToVariations(cdfs_reshaped[:,1:length(pvs.config_variations)], pvs.config_variations, prepareConfigVariationFunctions(inputs.config.id, pvs.config_variations; reference_config_variation_id=reference_variation_ids.config)...)
    end
    if isempty(pvs.rulesets_collection_variations)
        rulesets_collection_variation_ids = fill(reference_variation_ids.rulesets_collection, size(cdfs_reshaped,1))
    else
        rulesets_collection_variation_ids = cdfsToVariations(cdfs_reshaped[:,length(pvs.config_variations)+1:end], pvs.rulesets_collection_variations, prepareRulesetsVariationFunctions(inputs.rulesets_collection.id; reference_rulesets_variation_id=reference_variation_ids.rulesets_collection)...)
    end
    if isempty(pvs.ic_cell_variations)
        ic_cell_variation_ids = fill(reference_variation_ids.ic_cell, size(cdfs_reshaped,1))
    else
        ic_cell_variation_ids = cdfsToVariations(cdfs_reshaped[:,length(pvs.config_variations)+length(pvs.rulesets_collection_variations)+1:end], pvs.ic_cell_variations, prepareICCellVariationFunctions(inputs.ic_cell.id; reference_ic_cell_variation_id=reference_variation_ids.ic_cell)...)
    end
    config_variation_ids = reshape(config_variation_ids, (sobol_variation.n_matrices, sobol_variation.n))' # first, each sobol matrix variation indices goes into a row so that each column is the kth sample for each matrix; take the transpose so that each column corresponds to a matrix
    rulesets_collection_variation_ids = reshape(rulesets_collection_variation_ids, (sobol_variation.n_matrices, sobol_variation.n))'
    ic_cell_variation_ids = reshape(ic_cell_variation_ids, (sobol_variation.n_matrices, sobol_variation.n))'
    return config_variation_ids, rulesets_collection_variation_ids, ic_cell_variation_ids, cdfs, pvs
end

################## Random Balanced Design Sampling Functions ##################

function generateRBDCDFs(rbd_variation::RBDVariation, d::Int)
    if rbd_variation.use_sobol
        println("Using Sobol sequence for RBD.")
        if rbd_variation.n == 1
            S = zeros(Float64, (1, d))
            cdfs = 0.5 .+ zeros(Float64, (1,d))
        else
            @assert !ismissing(rbd_variation.pow2_diff) "pow2_diff must be calculated for RBDVariation constructor with Sobol sequence. How else could we get here?"
            @assert rbd_variation.num_cycles == 1//2 "num_cycles must be 1//2 for RBDVariation constructor with Sobol sequence. How else could we get here?"
            if rbd_variation.pow2_diff == -1
                skip_start = 1
            elseif rbd_variation.pow2_diff == 0
                skip_start = true
            else
                skip_start = false
            end
            S = generateSobolCDFs(rbd_variation.n, d; n_matrices=1, randomization=NoRand(), skip_start=skip_start, include_one=rbd_variation.pow2_diff==1) # pre_s is (d, n_matrices, rbd_variation.n)
            S = reshape(S, d, rbd_variation.n)'
            cdfs = deepcopy(S)
        end
    else
        @assert rbd_variation.num_cycles == 1 "num_cycles must be 1 for RBDVariation constructor with random sequence. How else could we get here?"
        pre_s = range(-π, stop = π, length = rbd_variation.n+1) |> collect
        pop!(pre_s)
        S = [pre_s[randperm(rbd_variation.rng, rbd_variation.n)] for _ in 1:d] |> x->reduce(hcat, x)
        cdfs = 0.5 .+ asin.(sin.(S)) ./ π
    end
    return cdfs, S
end

# This function could be used to get a Sobol sequence for the RBD using all [-π, π] values
# function generateRBDCDFs(n::Int, d::Int; rng::AbstractRNG=Random.GLOBAL_RNG, use_sobol::Bool=true)
#     if use_sobol
#         println("Using Sobol sequence for RBD.")
#         sobol_seq = SobolSeq(d)
#         pre_s = zeros(Float64, (d, n-1))
#         for col in eachcol(pre_s)
#             next!(sobol_seq, col)
#         end
#         S = -π .+ 2π * pre_s'
#         if n == 1
#             cdfs = 0.5 .+ zeros(Float64, (1,d))
#         elseif n == 2
#             cdfs = 0.5 .+ zeros(Float64, (2, d))
#         else
#             cdfs_all = range(0, stop=1, length=Int(n / 2) + 1) |> collect # all the cdf values that will be used
#             cdfs_all = vcat(cdfs_all, reverse(cdfs_all[2:end-1])) # make them go 0->1->0 but not repeat the 0 and 1
#             cdfs_all = circshift(cdfs_all, Int(n / 4)) # shift so that the first value is 0.5 and we begin by decreasing to 0
#             # now use the values from cdfs_all to create the cdfs for each parameter based on the pre_s values
#             cdfs = zeros(Float64, (n, d)) 
#             for (pre_s_row, cdfs_col) in zip(eachrow(pre_s), eachcol(cdfs))
#                 ord = sortperm(pre_s_row) |> invperm # this ranks all of the pre_s values for this parameter (remember, the first one at 0 is omitted by SobolSeq)
#                 cdfs_col .= [0.5; cdfs_all[ord.+1]] # the first one (0.5) comes from the omitted 0.0 to start the SobolSeq; the rest are the cdfs based on the pre_s values (the +1 is because ord comes from pre_s which omits the first element, but this first element is included in cdfs_all)
#             end
#         end
#         # cdfs = 0.5 .+ [zeros(Float64, (1,d)); asin.(sin.(S)) ./ π] # this is the simpler line to do this, but floating point arithmetic introduces some differences that should not exist when using a n=2^k Sobol sequence
#     else
#         pre_s = range(-π, stop = π, length = n+1) |> collect
#         pop!(pre_s)
#         S = [s0[randperm(rng, n)] for _ in 1:d] |> x->reduce(hcat, x)
#         cdfs = 0.5 .+ asin.(sin.(S)) ./ π
#     end
#     return cdfs, S
# end

function createSortedRBDMatrix(variation_ids::Vector{Int}, S::AbstractMatrix{Float64})
    variations_matrix = Array{Int}(undef, size(S))
    for (vm_col, s_col) in zip(eachcol(variations_matrix), eachcol(S))
        vm_col .= variation_ids[sortperm(s_col)]
    end
    return variations_matrix
end

function addVariations(rbd_variation::RBDVariation, inputs::InputFolders, evs::Vector{<:ElementaryVariation}, reference_variation_ids::VariationIDs)
    pvs = ParsedVariations(evs)
    d = length(pvs.config_variations) + length(pvs.rulesets_collection_variations) + length(pvs.ic_cell_variations)
    cdfs, S = generateRBDCDFs(rbd_variation, d)
    if isempty(pvs.config_variations)
        config_variation_ids = fill(reference_variation_ids.config, size(cdfs,1))
    else
        config_variation_ids = cdfsToVariations(cdfs[:,1:length(pvs.config_variations)], pvs.config_variations, prepareConfigVariationFunctions(inputs.config.id, pvs.config_variations; reference_config_variation_id=reference_variation_ids.config)...)
    end
    if isempty(pvs.rulesets_collection_variations)
        rulesets_collection_variation_ids = fill(reference_variation_ids.rulesets_collection, size(cdfs,1))
    else
        rulesets_collection_variation_ids = cdfsToVariations(cdfs[:,length(pvs.config_variations)+1:end], pvs.rulesets_collection_variations, prepareRulesetsVariationFunctions(inputs.rulesets_collection.id; reference_rulesets_variation_id=reference_variation_ids.rulesets_collection)...)
    end
    if isempty(pvs.ic_cell_variations)
        ic_cell_variation_ids = fill(reference_variation_ids.ic_cell, size(cdfs,1))
    else
        ic_cell_variation_ids = cdfsToVariations(cdfs[:,length(pvs.config_variations)+length(pvs.rulesets_collection_variations)+1:end], pvs.ic_cell_variations, prepareICCellVariationFunctions(inputs.ic_cell.id; reference_ic_cell_variation_id=reference_variation_ids.ic_cell)...)
    end
    config_variations_matrix = createSortedRBDMatrix(config_variation_ids, S)
    rulesets_variations_matrix = createSortedRBDMatrix(rulesets_collection_variation_ids, S)
    ic_cell_variations_matrix = createSortedRBDMatrix(ic_cell_variation_ids, S)
    return config_variation_ids, rulesets_collection_variation_ids, ic_cell_variation_ids, config_variations_matrix, rulesets_variations_matrix, ic_cell_variations_matrix
end

################## Sampling Helper Functions ##################

function cdfsToVariations(cdfs::AbstractMatrix{Float64}, evs::Vector{<:ElementaryVariation}, addColumnsByPathsFn::Function, prepareAddNewFn::Function, addRowFn::Function)
    n = size(cdfs, 1)
    new_values = []
    for (i, ev) in enumerate(evs)
        new_value = _values(ev, cdfs[:,i]) # ok, all the new values for the given parameter
        push!(new_values, new_value)
    end

    static_values, table_features = setUpColumns(evs, addColumnsByPathsFn, prepareAddNewFn)

    variation_ids = zeros(Int, n)

    for i in 1:n
        varied_values = [new_value[i] for new_value in new_values] .|> string |> x -> join("\"" .* x .* "\"", ",")
        variation_ids[i] = addRowFn(table_features, static_values, varied_values)
    end
    return variation_ids
end

function prepareConfigVariationFunctions(config_id::Int, evs::Vector{<:ElementaryVariation}; reference_config_variation_id=0)
    addColumnsByPathsFn = (paths) -> addConfigVariationColumns(config_id, paths, dataType.(evs))
    prepareAddNewFn = (args...) -> prepareAddNewConfigVariations(config_id, args...; reference_config_variation_id=reference_config_variation_id)
    addRowFn = (args...) -> addConfigVariationRow(config_id, args...)
    return addColumnsByPathsFn, prepareAddNewFn, addRowFn
end

function prepareRulesetsVariationFunctions(rulesets_collection_id::Int; reference_rulesets_variation_id::Int=0)
    addColumnsByPathsFn = (paths) -> addRulesetsVariationsColumns(rulesets_collection_id, paths)
    prepareAddNewFn = (args...) -> prepareAddNewRulesetsVariations(rulesets_collection_id, args...; reference_rulesets_variation_id=reference_rulesets_variation_id)
    addRowFn = (args...) -> addRulesetsVariationRow(rulesets_collection_id, args...)
    return addColumnsByPathsFn, prepareAddNewFn, addRowFn
end

function prepareICCellVariationFunctions(ic_cell_id::Int; reference_ic_cell_variation_id::Int=0)
    addColumnsByPathsFn = (paths) -> addICCellVariationColumns(ic_cell_id, paths)
    prepareAddNewFn = (args...) -> prepareAddNewICCellVariations(ic_cell_id, args...; reference_ic_cell_variation_id=reference_ic_cell_variation_id)
    addRowFn = (args...) -> addICCellVariationRow(ic_cell_id, args...)
    return addColumnsByPathsFn, prepareAddNewFn, addRowFn
end