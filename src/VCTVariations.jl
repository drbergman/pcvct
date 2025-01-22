using Distributions, LazyGrids
import Distributions: cdf

export ElementaryVariation, DiscreteVariation, DistributedVariation, CoVariation
export UniformDistributedVariation, NormalDistributedVariation
export GridVariation, LHSVariation, SobolVariation
export addDomainVariationDimension!, addCustomDataVariationDimension!, addAttackRateVariationDimension!

################## XMLPath ##################
"""
    XMLPath

Hold the XML path as a vector of strings.

PhysiCell uses a `:` in names for signals/behaviors from cell custom data.
For example, `custom:sample` is the default way to represent the `sample` custom data in a PhysiCell rule.
pcvct uses `:` to indicate an attribute in an XML path and thus splits on `:` when looking for attribute values.
To avoid this conflict, pcvct will internally replace `custom:<name>` and `custom: <name>` with `custom <name>`.
Users should never have to think about this.
Any pcvct function that uses XML paths will automatically handle this replacement.
"""
struct XMLPath
    xml_path::Vector{String}

    function XMLPath(xml_path::Vector{<:AbstractString})
        custom_fields = startswith.(xml_path, "custom:")
        xml_path[custom_fields] = "custom " .* [lstrip(p[8:end]) for p in xml_path[custom_fields]]
        new(xml_path)
    end
end

################## Abstract Variations ##################

abstract type AbstractVariation end
abstract type ElementaryVariation <: AbstractVariation end

"""
    DiscreteVariation

The location, target, and values of a discrete variation.

# Fields
- `location::Symbol`: The location of the variation. Can be `:config`, `:rulesets`, or `:ic_cell`. The location is inferred from the target.
- `target::XMLPath`: The target of the variation. The target is a vector of strings that represent the XML path to the element being varied. See [`XMLPath`](@ref) for more information.
- `values::Vector{T}`: The values of the variation. The values are the possible values that the target can take on.

A singleton value can be passed in place of `values` for convenience.

# Examples
```jldoctest
julia> dv = DiscreteVariation(["overall", "max_time"], [1440.0, 2880.0])
DiscreteVariation{Float64}(:config, pcvct.XMLPath(["overall", "max_time"]), [1440.0, 2880.0])
```
```jldoctest
xml_path = ["hypothesis_ruleset:name:default","behavior:name:cycle entry","decreasing_signals","max_response"]
DiscreteVariation(xml_path, 0)
# output
DiscreteVariation{Int64}(:rulesets, pcvct.XMLPath(["hypothesis_ruleset:name:default", "behavior:name:cycle entry", "decreasing_signals", "max_response"]), [0])
```
```jldoctest
xml_path = ["cell_patches:name:default","patch_collection:type:disc","patch:ID:1","x0"]
DiscreteVariation(xml_path, [0.0, 100.0])
# output
DiscreteVariation{Float64}(:ic_cell, pcvct.XMLPath(["cell_patches:name:default", "patch_collection:type:disc", "patch:ID:1", "x0"]), [0.0, 100.0])
```
"""
struct DiscreteVariation{T} <: ElementaryVariation
    location::Symbol
    target::XMLPath
    values::Vector{T}
    
    function DiscreteVariation(target::Vector{<:AbstractString}, values::Vector{T}) where T
        return DiscreteVariation(XMLPath(target), values)
    end
    function DiscreteVariation(target::XMLPath, values::Vector{T}) where T
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

"""
    DistributedVariation

The location, target, and distribution of a distributed variation.

Analagousy to [`DiscreteVariation`](@ref), instances of `DistributedVariation` can be initialized with a `target` (XML path) and a `distribution` (a distribution from the `Distributions` package).
Alternatively, users can use the [`UniformDistributedVariation`](@ref) and [`NormalDistributedVariation`](@ref) functions to create instances of `DistributedVariation`.

# Fields
- `location::Symbol`: The location of the variation. Can be `:config`, `:rulesets`, or `:ic_cell`. The location is inferred from the target.
- `target::XMLPath`: The target of the variation. The target is a vector of strings that represent the XML path to the element being varied. See [`XMLPath`](@ref) for more information.
- `distribution::Distribution`: The distribution of the variation.
- `flip::Bool=false`: Whether to flip the distribution, i.e., when asked for the iCDF of `x`, return the iCDF of `1-x`. Useful for [`CoVariation`](@ref)'s.

# Examples
```jldoctest
using Distributions
d = Uniform(1, 2)
DistributedVariation([pcvct.apoptosisPath("default"); "death_rate"], d)
# output
DistributedVariation(:config, pcvct.XMLPath(["cell_definitions", "cell_definition:name:default", "phenotype", "death", "model:code:100", "death_rate"]), Distributions.Uniform{Float64}(a=1.0, b=2.0), false)
```
```jldoctest
using Distributions
d = Uniform(1, 2)
flip = true # the cdf on this variation will decrease from 1 to 0 as the value increases from 1 to 2
DistributedVariation([pcvct.necrosisPath("default"); "death_rate"], d, flip)
# output
DistributedVariation(:config, pcvct.XMLPath(["cell_definitions", "cell_definition:name:default", "phenotype", "death", "model:code:101", "death_rate"]), Distributions.Uniform{Float64}(a=1.0, b=2.0), true)
"""
struct DistributedVariation <: ElementaryVariation
    location::Symbol
    target::XMLPath
    distribution::Distribution
    flip::Bool

    function DistributedVariation(target::Vector{<:AbstractString}, distribution::Distribution, flip::Bool=false)
        return DistributedVariation(XMLPath(target), distribution, flip)
    end
    function DistributedVariation(target::XMLPath, distribution::Distribution, flip::Bool=false)
        location = variationLocation(target)
        return new(location, target, distribution, flip)
    end
end

target(ev::ElementaryVariation) = ev.target
location(ev::ElementaryVariation) = ev.location
columnName(ev::ElementaryVariation) = target(ev).xml_path |> xmlPathToColumnName

Base.length(::DistributedVariation) = -1 # set to -1 to be a convention

"""
    UniformDistributedVariation(xml_path::Vector{<:AbstractString}, lb::T, ub::T) where {T<:Real}

Create a distributed variation with a uniform distribution.
"""
function UniformDistributedVariation(xml_path::Vector{<:AbstractString}, lb::T, ub::T, flip::Bool=false) where {T<:Real}
    return DistributedVariation(xml_path, Uniform(lb, ub), flip)
end

"""
    NormalDistributedVariation(xml_path::Vector{<:AbstractString}, mu::T, sigma::T; lb::Real=-Inf, ub::Real=Inf) where {T<:Real}

Create a (possibly truncated) distributed variation with a normal distribution.
"""
function NormalDistributedVariation(xml_path::Vector{<:AbstractString}, mu::T, sigma::T, flip::Bool=false; lb::Real=-Inf, ub::Real=Inf) where {T<:Real}
    return DistributedVariation(xml_path, truncated(Normal(mu, sigma), lb, ub), flip)
end

_values(discrete_variation::DiscreteVariation) = discrete_variation.values

function _values(discrete_variation::DiscreteVariation, cdf::Vector{<:Real})
    index = floor.(Int, cdf * length(discrete_variation)) .+ 1
    index[index.==(length(discrete_variation)+1)] .= length(discrete_variation) # if cdf = 1, index = length(discrete_variation)+1, so we set it to length(discrete_variation)
    return discrete_variation.values[index]
end

_values(discrete_variation::DiscreteVariation, cdf::Real) = _values(discrete_variation, [cdf])

function _values(dv::DistributedVariation, cdf::Vector{<:Real})
    return map(Base.Fix1(quantile, dv.distribution), dv.flip ? 1 .- cdf : cdf)
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

function cdf(dv::DistributedVariation, x::Real)
    out = cdf(dv.distribution, x)
    if dv.flip
        return 1 - out
    end
    return out
end

cdf(ev::ElementaryVariation, ::Real) = error("cdf not defined for $(typeof(ev))")

function variationLocation(xp::XMLPath)
    if startswith(xp.xml_path[1], "hypothesis_ruleset:name:")
        return :rulesets
    elseif startswith(xp.xml_path[1], "cell_patches:name:")
        return :ic_cell
    else
        return :config
    end
end

################## Co-Variations ##################

"""
    CoVariation

A co-variation of one or more variations.

# Fields
- `variations::Vector{T}`: The variations that make up the co-variation.
"""
struct CoVariation{T<:ElementaryVariation} <: AbstractVariation
    variations::Vector{T}

    function CoVariation(inputs::Vararg{Tuple{Vector{<:AbstractString},Distribution},N}) where {N}
        variations = DistributedVariation[]
        for (xml_path, distribution) in inputs
            @assert xml_path isa Vector{<:AbstractString} "xml_path must be a vector of strings"
            push!(variations, DistributedVariation(xml_path, distribution))
        end
        return new{DistributedVariation}(variations)
    end
    function CoVariation(inputs::Vararg{Tuple{Vector{<:AbstractString},Vector},N}) where {N}
        variations = DiscreteVariation[]
        n_discrete = -1
        for (xml_path, val) in inputs
            n_vals = length(val)
            if n_discrete == -1
                n_discrete = n_vals
            else
                @assert n_discrete == n_vals "All discrete vals must have the same length"
            end
            push!(variations, DiscreteVariation(xml_path, val))
        end
        return new{DiscreteVariation}(variations)
    end
    function CoVariation(ev::T) where {T<:ElementaryVariation}
        return new{T}([ev])
    end
    function CoVariation(evs::Vector{T}) where {T<:ElementaryVariation}
        if T == DistributedVariation
            return new{T}(evs)
        end
        @assert (length.(evs) |> unique |> length) == 1 "All DiscreteVariations in a CoVariation must have the same length."
        return new{DiscreteVariation}(evs)
    end
    function CoVariation(inputs::Vararg{T,N}) where {T<:ElementaryVariation,N}
        return CoVariation(Vector{T}([inputs...]))
    end
end

target(cv::CoVariation) = target.(cv.variations)
location(cv::CoVariation) = location.(cv.variations)
columnName(cv::CoVariation) = columnName.(cv.variations) |> x->join(x, " AND ")

function Base.length(cv::CoVariation)
    return length(cv.variations[1])
end

################## Variation Dimension Functions ##################

"""
    addDomainVariationDimension!(evs::Vector{<:ElementaryVariation}, domain::NamedTuple)

Pushes variations onto `evs` for each domain boundary named in `domain`.

The names in `domain` can be flexibly named as long as they contain either `min` or `max` and one of `x`, `y`, or `z` (other than the the `x` in `max`).
It is not required to include all three dimensions and their boundaries.
The values for each boundary can be a single value or a vector of values.

# Examples:
```
evs = ElementaryVariation[]
addDomainVariationDimension!(evs, (x_min=-78, xmax=78, min_y=-30, maxy=[30, 60], z_max=10))
"""
function addDomainVariationDimension!(evs::Vector{<:ElementaryVariation}, domain::NamedTuple)
    dim_chars = ["z", "y", "x"]
    for (tag, value) in pairs(domain)
        tag = String(tag)
        if contains(tag, "min")
            remaining_characters = replace(tag, "min" => "")
            dim_side = "min"
        elseif contains(tag, "max")
            remaining_characters = replace(tag, "max" => "")
            dim_side = "max"
        else
            msg = """
            Invalid tag for a domain dimension: $(tag)
            It must contain either 'min' or 'max'
            """
            throw(ArgumentError(msg))
        end
        ind = findfirst(contains.(remaining_characters, dim_chars))
        @assert !isnothing(ind) "Invalid domain dimension: $(tag)"
        dim_char = dim_chars[ind]
        tag = "$(dim_char)_$(dim_side)"
        xml_path = ["domain", tag]
        push!(evs, DiscreteVariation(xml_path, value)) # do this to make sure that singletons and vectors are converted to vectors
    end
end

"""
    addAttackRateVariationDimension!(evs::Vector{<:ElementaryVariation}, cell_definition::String, target_name::String, values::Vector{T} where T)

Pushes a variation onto `evs` for the attack rate of a cell type against a target cell type.

# Examples:
```
addAttackRateVariationDimension!(evs, "immune", "cancer", [0.1, 0.2, 0.3])
```
"""
function addAttackRateVariationDimension!(evs::Vector{<:ElementaryVariation}, cell_definition::String, target_name::String, values::Vector{T} where T)
    xml_path = attackRatesPath(cell_definition, target_name)
    push!(evs, DiscreteVariation(xml_path, values))
end

"""
    addCustomDataVariationDimension!(evs::Vector{<:ElementaryVariation}, cell_definition::String, field_name::String, values::Vector{T} where T)

Pushes a variation onto `evs` for a custom data field of a cell type.

# Examples:
```
addCustomDataVariationDimension!(evs, "immune", "perforin", [0.1, 0.2, 0.3])
```
"""
function addCustomDataVariationDimension!(evs::Vector{<:ElementaryVariation}, cell_definition::String, field_name::String, values::Vector{T} where T)
    xml_path = customDataPath(cell_definition, field_name)
    push!(evs, DiscreteVariation(xml_path, values))
end

################## Database Interface Functions ##################

function addColumns(xps::Vector{XMLPath}, table_name::String, id_column_name::String, db_columns::SQLite.DB, path_to_xml::String, dataTypeRulesFn::Function)
    column_names = queryToDataFrame("PRAGMA table_info($(table_name));"; db=db_columns) |> x->x[!,:name]
    filter!(x -> x != id_column_name, column_names)
    varied_column_names = [xmlPathToColumnName(xp.xml_path) for xp in xps]

    is_new_column = [!(varied_column_name in column_names) for varied_column_name in varied_column_names]
    if any(is_new_column)
        new_column_names = varied_column_names[is_new_column]
        xml_doc = openXML(path_to_xml)
        default_values_for_new = [getField(xml_doc, xp.xml_path) for xp in xps[is_new_column]]
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

function addConfigVariationColumns(config_id::Int, xps::Vector{XMLPath}, variable_types::Vector{DataType})
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
    return addColumns(xps, "config_variations", "config_variation_id", db_columns, path_to_xml, dataTypeRulesFn)
end

function addRulesetsVariationsColumns(rulesets_collection_id::Int, xps::Vector{XMLPath})
    rulesets_collection_folder = rulesetsCollectionFolder(rulesets_collection_id)
    db_columns = rulesetsCollectionDB(rulesets_collection_folder)
    path_to_rulesets_collection_folder = joinpath(data_dir, "inputs", "rulesets_collections", rulesets_collection_folder)
    path_to_base_xml = joinpath(path_to_rulesets_collection_folder, "base_rulesets.xml")
    if !isfile(path_to_base_xml)
        writeRules(path_to_base_xml, joinpath(path_to_rulesets_collection_folder, "base_rulesets.csv"))
    end
    dataTypeRulesFn = (_, name) -> occursin("applies_to_dead", name) ? "INT" : "REAL"
    return addColumns(xps, "rulesets_collection_variations", "rulesets_collection_variation_id", db_columns, path_to_base_xml, dataTypeRulesFn)
end

function addICCellVariationColumns(ic_cell_id::Int, xps::Vector{XMLPath})
    ic_cell_folder = icCellFolder(ic_cell_id)
    db_columns = icCellDB(ic_cell_folder)
    @assert db_columns isa SQLite.DB "ic_cell_folder must contain a cells.xml file to support variations."
    path_to_ic_cell_folder = joinpath(data_dir, "inputs", "ics", "cells", ic_cell_folder)
    path_to_base_xml = joinpath(path_to_ic_cell_folder, "cells.xml")
    dataTypeRulesFn = (_, name) -> endswith(name, "number") ? "INT" : "REAL"
    return addColumns(xps, "ic_cell_variations", "ic_cell_variation_id", db_columns, path_to_base_xml, dataTypeRulesFn)
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
    xps = target.(evs)
    static_column_names, varied_column_names = addColumnsByPathsFn(xps)
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

"""
    GridVariation

A variation method that creates a grid of all possible combinations of the values of the variations.

# Examples
```jldoctest
julia> GridVariation() # the only method for GridVariation
GridVariation()
```
"""
struct GridVariation <: AddVariationMethod end

"""
    LHSVariation

A variation method that creates a Latin Hypercube Sample of the values of the variations.

# Fields
Default values from constructors are shown.
- `n::Int`: The number of samples to take.
- `add_noise::Bool=false`: Whether to add noise to the samples or have them be in the center of the bins.
- `rng::AbstractRNG=Random.GLOBAL_RNG`: The random number generator to use.
- `orthogonalize::Bool=true`: Whether to orthogonalize the samples. See https://en.wikipedia.org/wiki/Latin_hypercube_sampling#:~:text=In%20orthogonal%20sampling

# Examples
```jldoctest
julia> LHSVariation(4) # set `n` and use default values for the rest
LHSVariation(4, false, Random.TaskLocalRNG(), true)
```
```jldoctest
using Random
LHSVariation(; n=4, add_noise=true, rng=MersenneTwister(1234), orthogonalize=false)
# output
LHSVariation(4, true, MersenneTwister(1234), false)
```
"""
struct LHSVariation <: AddVariationMethod
    n::Int
    add_noise::Bool
    rng::AbstractRNG
    orthogonalize::Bool
end
LHSVariation(n; add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG, orthogonalize::Bool=true) = LHSVariation(n, add_noise, rng, orthogonalize)
LHSVariation(; n::Int=4, add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG, orthogonalize::Bool=true) = LHSVariation(n, add_noise, rng, orthogonalize)

"""
    SobolVariation

A variation method that creates a Sobol sequence of the values of the variations.

See [`generateSobolCDFs`](@ref) for more information on how the Sobol sequence is generated based on `n` and the other fields.

See the GlobalSensitivity.jl package for more information on `RandomizationMethod`'s to use.

# Fields
Default values from constructors are shown.
- `n::Int`: The number of samples to take.
- `n_matrices::Int=1`: The number of matrices to use in the Sobol sequence.
- `randomization::RandomizationMethod=NoRand()`: The randomization method to use on the deterministic Sobol sequence.
- `skip_start::Union{Missing, Bool, Int}=missing`: Whether to skip the start of the sequence. Missing means pcvct will choose the best option.
- `include_one::Union{Missing, Bool}=missing`: Whether to include 1 in the sequence. Missing means pcvct will choose the best option.

# Examples
```jldoctest
julia> SobolVariation(9) # set `n` and use default values for the rest; will use [0, 0.5, 0.25, 0.75, 0.125, 0.375, 0.625, 0.875, 1]
SobolVariation(9, 1, QuasiMonteCarlo.NoRand(), missing, missing)
```
```jldoctest
julia> SobolVariation(15; skip_start=true) # use [0.5, 0.25, 0.75, ..., 1/16, 3/16, ..., 15/16]
SobolVariation(15, 1, QuasiMonteCarlo.NoRand(), true, missing)
```
```jldoctest
julia> SobolVariation(4; include_one=true) # use [0, 0.5, 1] and one of [0.25, 0.75]
SobolVariation(4, 1, QuasiMonteCarlo.NoRand(), missing, true)
```
"""
struct SobolVariation <: AddVariationMethod
    n::Int
    n_matrices::Int
    randomization::RandomizationMethod
    skip_start::Union{Missing, Bool, Int}
    include_one::Union{Missing, Bool}
end
SobolVariation(n::Int; n_matrices::Int=1, randomization::RandomizationMethod=NoRand(), skip_start::Union{Missing, Bool, Int}=missing, include_one::Union{Missing, Bool}=missing) = SobolVariation(n, n_matrices, randomization, skip_start, include_one)
SobolVariation(; pow2::Int=1, n_matrices::Int=1, randomization::RandomizationMethod=NoRand(), skip_start::Union{Missing, Bool, Int}=missing, include_one::Union{Missing, Bool}=missing) = SobolVariation(2^pow2, n_matrices, randomization, skip_start, include_one)

"""
    RBDVariation

A variation method that creates a Random Balance Design of the values of the variations.

This creates `n` sample points where the values in each dimension are uniformly distributed.
By default, this will use Sobol sequences (see [`SobolVariation`](@ref)) to create the sample points.
If `use_sobol` is `false`, it will use random permutations of uniformly spaced points for each dimension.

# Fields
Default values from constructors are shown.
- `n::Int`: The number of samples to take.
- `rng::AbstractRNG=Random.GLOBAL_RNG`: The random number generator to use.
- `use_sobol::Bool=true`: Whether to use Sobol sequences to create the sample points.
Do not set these next two fields unless you know what you are doing. Let pcvct compute them.
- `pow2_diff::Union{Missing, Int}=missing`: The difference between `n` and the nearest power of 2. Missing means pcvct will compute it if using Sobol sequences.
- `num_cycles::Union{Missing, Int, Rational}=missing`: The number of cycles to use in the Sobol sequence. Missing means pcvct will set it.

# Examples
```jldoctest
julia> pcvct.RBDVariation(4) # set `n` and use default values for the rest
pcvct.RBDVariation(4, Random.TaskLocalRNG(), true, 0, 1//2)
```
```jldoctest
julia> pcvct.RBDVariation(4; use_sobol=false) # use random permutations of uniformly spaced points
pcvct.RBDVariation(4, Random.TaskLocalRNG(), false, missing, 1//1)
```
"""
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

function addVariations(method::AddVariationMethod, inputs::InputFolders, avs::Vector{<:AbstractVariation};
    reference_config_variation_id::Int=0, reference_rulesets_variation_id::Int=0, reference_ic_cell_variation_id::Int=inputs.ic_cell.folder=="" ? -1 : 0)
    reference_variation_ids = VariationIDs(reference_config_variation_id, reference_rulesets_variation_id, reference_ic_cell_variation_id)
    return addVariations(method, inputs, avs, reference_variation_ids)
end

function addVariations(method::AddVariationMethod, inputs::InputFolders, avs::Vector{<:AbstractVariation}, reference_variation_ids::VariationIDs)
    pv = ParsedVariations(avs)
    return addVariations(method, inputs, pv, reference_variation_ids)
end

struct ParsedVariations
    sz::Vector{Int}
    variations::Vector{<:AbstractVariation} # 

    config_variations::Vector{<:ElementaryVariation}
    rulesets_collection_variations::Vector{<:ElementaryVariation}
    ic_cell_variations::Vector{<:ElementaryVariation}

    config_variation_indices::Vector{Int}
    rulesets_collection_variation_indices::Vector{Int}
    ic_cell_variation_indices::Vector{Int}

    function ParsedVariations(sz::Vector{Int}, variations::Vector{<:AbstractVariation}, config_variations::Vector{<:ElementaryVariation}, rulesets_collection_variations::Vector{<:ElementaryVariation}, ic_cell_variations::Vector{<:ElementaryVariation}, config_variation_indices::Vector{Int}, rulesets_collection_variation_indices::Vector{Int}, ic_cell_variation_indices::Vector{Int})
        @assert length(config_variations) == length(config_variation_indices) "config_variations and config_variation_indices must have the same length"
        @assert length(rulesets_collection_variations) == length(rulesets_collection_variation_indices) "rulesets_collection_variations and rulesets_collection_variation_indices must have the same length"
        @assert length(ic_cell_variations) == length(ic_cell_variation_indices) "ic_cell_variations and ic_cell_variation_indices must have the same length"
        return new(sz, variations, config_variations, rulesets_collection_variations, ic_cell_variations, config_variation_indices, rulesets_collection_variation_indices, ic_cell_variation_indices)
    end
end

function ParsedVariations(avs::Vector{<:AbstractVariation})
    sz = length.(avs)

    config_variations = ElementaryVariation[]
    rulesets_collection_variations = ElementaryVariation[]
    ic_cell_variations = ElementaryVariation[]
    config_variation_indices = Int[]
    rulesets_collection_variation_indices = Int[]
    ic_cell_variation_indices = Int[]
    for (i, av) in enumerate(avs)
        if av isa ElementaryVariation
            av = CoVariation(av) # wrap it in a covariation
        end
        @assert av isa CoVariation "Everything at this point should have been converted to a CoVariation"
        for ev in av.variations
            loc = location(ev)
            if loc == :config
                push!(config_variations, ev)
                push!(config_variation_indices, i)
            elseif loc == :rulesets
                push!(rulesets_collection_variations, ev)
                push!(rulesets_collection_variation_indices, i)
            elseif loc == :ic_cell
                push!(ic_cell_variations, ev)
                push!(ic_cell_variation_indices, i)
            else
                error("Variation type not recognized.")
            end
        end
    end
    for v in [config_variation_indices, rulesets_collection_variation_indices, ic_cell_variation_indices]
        @assert issorted(v) "Variation indices must be sorted after parsing."
    end
    return ParsedVariations(sz, avs, config_variations, rulesets_collection_variations, ic_cell_variations, config_variation_indices, rulesets_collection_variation_indices, ic_cell_variation_indices)
end

################## Grid Variations ##################

function addVariations(::GridVariation, inputs::InputFolders, pv::ParsedVariations, reference_variation_ids::VariationIDs)
    @assert all(pv.sz .!= -1) "GridVariation only works with DiscreteVariations"
    return [addLocationGridVariations(inputs, pv, reference_variation_ids, location) for location in [:config, :rulesets_collection, :ic_cell]]
end

function addLocationGridVariations(inputs::InputFolders, pv::ParsedVariations, reference_variation_ids::VariationIDs, location::Symbol)
    variations_field = Symbol("$(location)_variations")
    if isempty(getfield(pv, variations_field))
        return fill(getfield(reference_variation_ids, location), pv.sz...)
    end
    variation_indices_field = Symbol("$(location)_variation_indices")
    fns = prepareVariationFunctions(location, inputs, pv, reference_variation_ids)
    out = gridToDB(getfield(pv, variations_field), fns..., getfield(pv, variation_indices_field))
    dim_szs = [d in getfield(pv, variation_indices_field) ? pv.sz[d] : 1 for d in eachindex(pv.sz)]
    out = reshape(out, dim_szs...)

    other_dims = [dim_szs[d] == 1 ? pv.sz[d] : 1 for d in eachindex(pv.sz)]
    return repeat(out, other_dims...)
end

function prepareVariationFunctions(location::Symbol, inputs::InputFolders, pv::ParsedVariations, reference_variation_ids::VariationIDs)
    if location == :config
        return prepareConfigVariationFunctions(inputs.config.id, pv.config_variations; reference_config_variation_id=reference_variation_ids.config)
    elseif location == :rulesets_collection
        return prepareRulesetsVariationFunctions(inputs.rulesets_collection.id; reference_rulesets_variation_id=reference_variation_ids.rulesets_collection)
    elseif location == :ic_cell
        return prepareICCellVariationFunctions(inputs.ic_cell.id; reference_ic_cell_variation_id=reference_variation_ids.ic_cell)
    end
end

function gridToDB(evs::Vector{<:ElementaryVariation}, addColumnsByPathsFn::Function, prepareAddNewFn::Function, addRowFn::Function, ev_dims::AbstractVector{Int}=1:length(evs))
    static_values, table_features = setUpColumns(evs, addColumnsByPathsFn, prepareAddNewFn)
    
    all_values = []
    for ev_dim in unique(ev_dims)
        dim_indices = findall(ev_dim .== ev_dims)
        push!(all_values, zip(_values.(evs[dim_indices])...))
    end

    NDG = ndgrid(collect.(all_values)...)
    sz_variations = size(NDG[1])
    variation_ids = zeros(Int, sz_variations)
    for i in eachindex(NDG[1])
        dim_vals_as_vecs = [[A[i]...] for A in NDG] # ith entry is a vector of the values for the ith dimension
        varied_values = vcat(dim_vals_as_vecs...) .|> string |> x -> join("\"" .* x .* "\"", ",")
        variation_ids[i] = addRowFn(table_features, static_values, varied_values)
    end
    return variation_ids
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

"""
    generateLHSCDFs(n::Int, d::Int[; add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG, orthogonalize::Bool=true])

Generate a Latin Hypercube Sample of the Cumulative Distribution Functions (CDFs) for `n` samples in `d` dimensions.

# Arguments
- `n::Int`: The number of samples to take.
- `d::Int`: The number of dimensions to sample.
- `add_noise::Bool=false`: Whether to add noise to the samples or have them be in the center of the bins.
- `rng::AbstractRNG=Random.GLOBAL_RNG`: The random number generator to use.
- `orthogonalize::Bool=true`: Whether to orthogonalize the samples, if possible. See https://en.wikipedia.org/wiki/Latin_hypercube_sampling#:~:text=In%20orthogonal%20sampling

# Returns
- `cdfs::Matrix{Float64}`: The CDFs for the samples. Each row is a sample and each column is a dimension (corresponding to a feature).

# Examples
```jldoctest
cdfs = pcvct.generateLHSCDFs(4, 2)
size(cdfs)
# output
(4, 2)
```
"""
function generateLHSCDFs(n::Int, d::Int; add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG, orthogonalize::Bool=true)
    cdfs = (Float64.(1:n) .- (add_noise ? rand(rng, Float64, n) : 0.5)) / n # permute below for each parameter separately
    k = n ^ (1 / d) |> round |> Int
    if orthogonalize && (n == k^d)
        # then good to do the orthogonalization
        lhs_inds = orthogonalLHS(k, d)
    else
        lhs_inds = reduce(hcat, [shuffle(rng, 1:n) for _ in 1:d]) # each shuffled index vector is added as a column
    end
    return cdfs[lhs_inds]
end

function addVariations(lhs_variation::LHSVariation, inputs::InputFolders, pv::ParsedVariations, reference_variation_ids::VariationIDs)
    d = length(pv.sz)
    cdfs = generateLHSCDFs(lhs_variation.n, d; add_noise=lhs_variation.add_noise, rng=lhs_variation.rng, orthogonalize=lhs_variation.orthogonalize)
    return [addLocationCDFVariations(inputs, pv, reference_variation_ids, location, cdfs) for location in [:config, :rulesets_collection, :ic_cell]]
end

function addLocationCDFVariations(inputs::InputFolders, pv::ParsedVariations, reference_variation_ids::VariationIDs, location::Symbol, cdfs::AbstractMatrix{Float64})
    variations_field = Symbol("$(location)_variations")
    if isempty(getfield(pv, variations_field))
        return fill(getfield(reference_variation_ids, location), size(cdfs, 1))
    end
    variation_indices_field = Symbol("$(location)_variation_indices")
    fns = prepareVariationFunctions(location, inputs, pv, reference_variation_ids)
    return cdfsToVariations(cdfs, getfield(pv, variations_field), fns..., getfield(pv, variation_indices_field))
end

################## Sobol Sequence Sampling Functions ##################

"""
    generateSobolCDFs(n::Int, d::Int[; n_matrices::Int=1, randomization::RandomizationMethod=NoRand(), skip_start::Union{Missing, Bool, Int}=missing, include_one::Union{Missing, Bool}=missing)

Generate `n_matrices` Sobol sequences of the Cumulative Distribution Functions (CDFs) for `n` samples in `d` dimensions.

The subsequence of the Sobol sequence is chosen based on the value of `n` and the value of `include_one`.
If it is one less than a power of 2, e.g. `n=7`, skip 0 and start from 0.5.
Otherwise, it will always start from 0.
If it is one more than a power of 2, e.g. `n=9`, include 1 (unless `include_one` is `false`).

The `skip_start` field can be used to control this by skipping the start of the sequence.
If `skip_start` is `true`, skip to the smallest consecutive subsequence with the same denominator that has at least `n` elements.
If `skip_start` is `false`, start from 0.
If `skip_start` is an integer, skip that many elements in the sequence, .e.g., `skip_start=1` skips 0 and starts at 0.5.

If you want to include 1 in the sequence, set `include_one` to `true`.
If you want to exlude 1 (in the case of `n=9`, e.g.), set `include_one` to `false`.

# Arguments
- `n::Int`: The number of samples to take.
- `d::Int`: The number of dimensions to sample.
- `n_matrices::Int=1`: The number of matrices to use in the Sobol sequence (effectively, the dimension of the sample is `d` x `n_matrices`).
- `randomization::RandomizationMethod=NoRand()`: The randomization method to use on the deterministic Sobol sequence. See GlobalSensitivity.jl.
- `skip_start::Union{Missing, Bool, Int}=missing`: Whether to skip the start of the sequence. Missing means pcvct will choose the best option.
- `include_one::Union{Missing, Bool}=missing`: Whether to include 1 in the sequence. Missing means pcvct will choose the best option.

# Returns
- `cdfs::Array{Float64, 3}`: The CDFs for the samples. The first dimension is the features, the second dimension is the matrix, and the third dimension is the sample points.

# Examples
```jldoctest
cdfs = pcvct.generateSobolCDFs(11, 3)
size(cdfs)
# output
(3, 1, 11)
```
```jldoctest
cdfs = pcvct.generateSobolCDFs(7, 5; n_matrices=2)
size(cdfs)
# output
(5, 2, 7)
```
"""
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

function addVariations(sobol_variation::SobolVariation, inputs::InputFolders, pv::ParsedVariations, reference_variation_ids::VariationIDs)
    d = length(pv.sz)
    cdfs = generateSobolCDFs(sobol_variation, d) # cdfs is (d, sobol_variation.n_matrices, sobol_variation.n)
    cdfs_reshaped = reshape(cdfs, (d, sobol_variation.n_matrices * sobol_variation.n)) # reshape to (d, sobol_variation.n_matrices * sobol_variation.n) so that each column is a sobol sample
    cdfs_reshaped = cdfs_reshaped' # transpose so that each row is a sobol sample
    cvis, rvis, ivis = [addLocationCDFVariations(inputs, pv, reference_variation_ids, location, cdfs_reshaped) for location in [:config, :rulesets_collection, :ic_cell]] .|>
        x -> reshape(x, (sobol_variation.n_matrices, sobol_variation.n))' # first, each sobol matrix variation indices goes into a row so that each column is the kth sample for each matrix; take the transpose so that each column corresponds to a matrix
    return cvis, rvis, ivis, cdfs
end

################## Random Balance Design Sampling Functions ##################

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

function addVariations(rbd_variation::RBDVariation, inputs::InputFolders, pv::ParsedVariations, reference_variation_ids::VariationIDs)
    d = length(pv.sz)
    cdfs, S = generateRBDCDFs(rbd_variation, d)
    config_vids, rules_vids, ic_cell_vids = [addLocationCDFVariations(inputs, pv, reference_variation_ids, location, cdfs) for location in [:config, :rulesets_collection, :ic_cell]]
    config_var_matrix, rules_var_matrix, ic_cell_var_matrix = [createSortedRBDMatrix(vids, S) for vids in [config_vids, rules_vids, ic_cell_vids]]
    return config_vids, rules_vids, ic_cell_vids, config_var_matrix, rules_var_matrix, ic_cell_var_matrix
end

################## Sampling Helper Functions ##################

function cdfsToVariations(cdfs::AbstractMatrix{Float64}, evs::Vector{<:ElementaryVariation}, addColumnsByPathsFn::Function, prepareAddNewFn::Function, addRowFn::Function, ev_dims::AbstractVector{Int}=1:length(evs))
    static_values, table_features = setUpColumns(evs, addColumnsByPathsFn, prepareAddNewFn)

    n = size(cdfs, 1)
    new_values = []
    for (ev, col_ind) in zip(evs, ev_dims)
        new_value = _values(ev, cdfs[:,col_ind]) # ok, all the new values for the given parameter
        push!(new_values, new_value)
    end

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