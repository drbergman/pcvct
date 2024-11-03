export addLHSConfigVariation, addLHSRulesetsVariation
export GridVariation, LHSVariation, addVariations

################## Abstract Variations ##################

abstract type AbstractVariation end
struct ElementaryVariation{T} <: AbstractVariation
    xml_path::Vector{String}
    values::Vector{T}
end

ElementaryVariation{T}(xml_path::Vector{String}, value::T) where T = ElementaryVariation{T}(xml_path, [value])

struct DistributedVariation <: AbstractVariation
    xml_path::Vector{String}
    distribution::Distribution
end

getVariationXMLPath(av::AbstractVariation) = av.xml_path::Vector{String}
variationColumnName(av::AbstractVariation) = getVariationXMLPath(av) |> xmlPathToColumnName

function UniformDistributedVariation(xml_path::Vector{String}, lb::T, ub::T) where {T<:Real}
    return DistributedVariation(xml_path, Uniform(lb, ub))
end

function NormalDistributedVariation(xml_path::Vector{String}, mu::T, sigma::T; lb::Real=-Inf, ub::Real=Inf) where {T<:Real}
    return DistributedVariation(xml_path, Truncated(Normal(mu, sigma), lb, ub))
end

function getVariationValues(ev::ElementaryVariation; cdf=missing)
    if ismissing(cdf)
        return ev.values
    end
    index = floor.(Int, cdf * length(ev.values)) .+ 1
    index[index .== length(ev.values)+1] .= length(ev.values) # if cdf = 1, index = length(ev.values)+1, so we set it to length(ev.values)
    return ev.values[index]
end

function getVariationValues(dv::DistributedVariation; cdf=missing)
    if ismissing(cdf)
        error("A cdf must be provided for a DistributedVariation.")
    end
    return map(Base.Fix1(quantile, dv.distribution), cdf)
end

getVariationValues(av::AbstractVariation; cdf=missing) = error("getVariationValues not defined for $(typeof(av))")

function getVariationDataType(ev::ElementaryVariation)
    return typeof(ev).parameters[1] # typeof(ev).parameters[1] is the type parameter T in the definition of ElementaryVariation{T}
end

function getVariationDataType(dv::DistributedVariation)
    return eltype(dv.distribution)
end

getVariationDataType(av::AbstractVariation) = error("getVariationDataType not defined for $(typeof(av))")

function variationCDF(ev::ElementaryVariation, value)
    if !(value in ev.values)
        error("Value not in elementary variation values.")
    end
    return (findfirst(isequal(value), ev.values) - 1) / (length(ev.values) - 1)
end

variationCDF(dv::DistributedVariation, value) = cdf(dv.distribution, value)

variationCDF(av::AbstractVariation, value) = error("variationCDF not defined for $(typeof(av))")

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
    config_folder = getConfigFolder(config_id)
    db_columns = getConfigDB(config_folder)
    path_to_xml = joinpath(data_dir, "inputs", "configs", config_folder, "PhysiCell_settings.xml")
    dataTypeRulesFn = (i, _) -> begin
        if variable_types[i] == Bool
            "TEXT"
        elseif variable_types[i] <: Int
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
    rulesets_collection_folder = getRulesetsCollectionFolder(rulesets_collection_id)
    db_columns = getRulesetsCollectionDB(rulesets_collection_folder)
    path_to_rulesets_collection_folder = joinpath(data_dir, "inputs", "rulesets_collections", rulesets_collection_folder)
    path_to_base_xml = joinpath(path_to_rulesets_collection_folder, "base_rulesets.xml")
    if !isfile(path_to_base_xml)
        writeRules(path_to_base_xml, joinpath(path_to_rulesets_collection_folder, "base_rulesets.csv"))
    end
    dataTypeRulesFn = (_, name) -> occursin("applies_to_dead", name) ? "INT" : "REAL"
    return addColumns(xml_paths, "rulesets_variations", "rulesets_variation_id", db_columns, path_to_base_xml, dataTypeRulesFn)
end

function addICCellVariationColumns(ic_cell_id::Int, xml_paths::Vector{Vector{String}})
    ic_cell_folder = getICCellFolder(ic_cell_id)
    db_columns = getICCellDB(ic_cell_folder)
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
        new_id = queryToDataFrame(query, db=db_columns) |> x->x[!,1]
    end
    return new_id[1]
end

function addConfigVariationRow(config_id::Int, table_features::String, values::String)
    db_columns = getConfigDB(config_id)
    return addRow(db_columns, "config_variations", "config_variation_id", table_features, values)
end

function addConfigVariationRow(config_id::Int, table_features::String, static_values::String, varied_values::String)
    return addConfigVariationRow(config_id, table_features, "$(static_values)$(varied_values)")
end

function addRulesetsVariationRow(rulesets_collection_id::Int, table_features::String, values::String)
    db_columns = getRulesetsCollectionDB(rulesets_collection_id)
    return addRow(db_columns, "rulesets_variations", "rulesets_variation_id", table_features, values)
end

function addRulesetsVariationRow(rulesets_collection_id::Int, table_features::String, static_values::String, varied_values::String)
    return addRulesetsVariationRow(rulesets_collection_id, table_features, "$(static_values)$(varied_values)")
end

function addICCellVariationRow(ic_cell_id::Int, table_features::String, values::String)
    db_columns = getICCellDB(ic_cell_id)
    return addRow(db_columns, "ic_cell_variations", "ic_cell_variation_id", table_features, values)
end

function addICCellVariationRow(ic_cell_id::Int, table_features::String, static_values::String, varied_values::String)
    return addICCellVariationRow(ic_cell_id, table_features, "$(static_values)$(varied_values)")
end

function addGrid(AV::Vector{<:AbstractVariation}, addColumnsByPathsFn::Function, prepareAddNewFn::Function, addRowFn::Function)
    new_values = [getVariationValues(av) for av in AV]

    static_values, table_features = setUpColumns(AV, addColumnsByPathsFn, prepareAddNewFn)

    NDG = ndgrid(new_values...)
    sz_variations = size(NDG[1])
    variation_ids = zeros(Int, sz_variations)
    for i in eachindex(NDG[1])
        varied_values = [A[i] for A in NDG] .|> string |> x -> join("\"" .* x .* "\"", ",")
        variation_ids[i] = addRowFn(table_features, static_values, varied_values)
    end
    return variation_ids |> vec
end

function setUpColumns(AV::Vector{<:AbstractVariation}, addColumnsByPathsFn::Function, prepareAddNewFn::Function)
    xml_paths = [getVariationXMLPath(av) for av in AV]

    static_column_names, varied_column_names = addColumnsByPathsFn(xml_paths)
    println("Static column names: $static_column_names")
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
    db_columns = getConfigDB(config_id)
    return prepareAddNew(db_columns, static_column_names, varied_column_names, "config_variations", "config_variation_id", reference_config_variation_id)
end

function prepareAddNewRulesetsVariations(rulesets_collection_id::Int, static_column_names::Vector{String}, varied_column_names::Vector{String}; reference_rulesets_variation_id::Int=0)
    db_columns = getRulesetsCollectionDB(rulesets_collection_id)
    return prepareAddNew(db_columns, static_column_names, varied_column_names, "rulesets_variations", "rulesets_variation_id", reference_rulesets_variation_id)
end

function prepareAddNewICCellVariations(ic_cell_id::Int, static_column_names::Vector{String}, varied_column_names::Vector{String}; reference_ic_cell_variation_id::Int=ic_cell_id==-1 ? -1 : 0)
    db_columns = getICCellDB(ic_cell_id)
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

function addVariations(method::AddVariationMethod, config_id::Int, rulesets_collection_id::Int, ic_cell_id::Int, AV::Vector{<:AbstractVariation}; reference_config_variation_id::Int=0, reference_rulesets_variation_id::Int=0, reference_ic_cell_variation_id::Int=ic_cell_id==-1 ? -1 : 0) 
    parsed_variations = ParsedVariations(AV)
    return addParsedVariations(method, config_id, rulesets_collection_id, ic_cell_id, parsed_variations; reference_config_variation_id=reference_config_variation_id, reference_rulesets_variation_id=reference_rulesets_variation_id, reference_ic_cell_variation_id=reference_ic_cell_variation_id)
end

addVariations(method::AddVariationMethod, config_folder::String, rulesets_collection_folder::String, ic_cell_folder::String, AV::Vector{<:AbstractVariation}; reference_config_variation_id::Int=0, reference_rulesets_variation_id::Int=0, reference_ic_cell_variation_id::Int=ic_cell_folder=="" ? -1 : 0) = addVariations(method, retrieveID("configs", config_folder), retrieveID("rulesets_collections", rulesets_collection_folder), retrieveID("ic_cells", ic_cell_folder), AV; reference_config_variation_id=reference_config_variation_id, reference_rulesets_variation_id=reference_rulesets_variation_id, reference_ic_cell_variation_id=reference_ic_cell_variation_id)

struct ParsedVariations
    config_variations::Vector{<:AbstractVariation}
    rulesets_variations::Vector{<:AbstractVariation}
    ic_cell_variations::Vector{<:AbstractVariation}

    config_variation_indices::Vector{Int}
    rulesets_variation_indices::Vector{Int}
    ic_cell_variation_indices::Vector{Int}

    function ParsedVariations(config_variations::Vector{<:AbstractVariation}, rulesets_variations::Vector{<:AbstractVariation}, ic_cell_variations::Vector{<:AbstractVariation}, config_variation_indices::Vector{Int}, rulesets_variation_indices::Vector{Int}, ic_cell_variation_indices::Vector{Int})
        @assert length(config_variations) == length(config_variation_indices) "config_variations and config_variation_indices must have the same length"
        @assert length(rulesets_variations) == length(rulesets_variation_indices) "rulesets_variations and rulesets_variation_indices must have the same length"
        @assert length(ic_cell_variations) == length(ic_cell_variation_indices) "ic_cell_variations and ic_cell_variation_indices must have the same length"
        return new(config_variations, rulesets_variations, ic_cell_variations, config_variation_indices, rulesets_variation_indices, ic_cell_variation_indices)
    end
end

function ParsedVariations(AV::Vector{<:AbstractVariation})
    config_variations = AbstractVariation[]
    rulesets_variations = AbstractVariation[]
    ic_cell_variations = AbstractVariation[]
    config_variation_indices = Int[]
    rulesets_variation_indices = Int[]
    ic_cell_variation_indices = Int[]
    for (i, av) in enumerate(AV)
        variation_target = variationTarget(av)
        if variation_target == :config
            push!(config_variations, av)
            push!(config_variation_indices, i)
        elseif variation_target == :rulesets
            push!(rulesets_variations, av)
            push!(rulesets_variation_indices, i)
        elseif variation_target == :ic_cell
            push!(ic_cell_variations, av)
            push!(ic_cell_variation_indices, i)
        else
            error("Variation type not recognized.")
        end
    end
    return ParsedVariations(config_variations, rulesets_variations, ic_cell_variations, config_variation_indices, rulesets_variation_indices, ic_cell_variation_indices)
end

function addParsedVariations(grid_variation::GridVariation, config_id::Int, rulesets_collection_id::Int, ic_cell_id::Int, parsed_variations::ParsedVariations; reference_config_variation_id::Int=0, reference_rulesets_variation_id::Int=0, reference_ic_cell_variation_id::Int=ic_cell_id==-1 ? -1 : 0)
    return addGridCombo(grid_variation, config_id, rulesets_collection_id, ic_cell_id, parsed_variations; reference_config_variation_id=reference_config_variation_id, reference_rulesets_variation_id=reference_rulesets_variation_id, reference_ic_cell_variation_id=reference_ic_cell_variation_id)
end

function addParsedVariations(lhs_variation::LHSVariation, config_id::Int, rulesets_collection_id::Int, ic_cell_id::Int, parsed_variations::ParsedVariations; reference_config_variation_id::Int=0, reference_rulesets_variation_id::Int=0, reference_ic_cell_variation_id::Int=ic_cell_id==-1 ? -1 : 0)
    return addLHSCombo(lhs_variation, config_id, rulesets_collection_id, ic_cell_id, parsed_variations; reference_config_variation_id=reference_config_variation_id, reference_rulesets_variation_id=reference_rulesets_variation_id, reference_ic_cell_variation_id=reference_ic_cell_variation_id)
end

function addParsedVariations(sobol_variation::SobolVariation, config_id::Int, rulesets_collection_id::Int, ic_cell_id::Int, parsed_variations::ParsedVariations; reference_config_variation_id::Int=0, reference_rulesets_variation_id::Int=0, reference_ic_cell_variation_id::Int=ic_cell_id==-1 ? -1 : 0)
    return addSobolCombo(sobol_variation, config_id, rulesets_collection_id, ic_cell_id, parsed_variations; reference_config_variation_id=reference_config_variation_id, reference_rulesets_variation_id=reference_rulesets_variation_id, reference_ic_cell_variation_id=reference_ic_cell_variation_id)
end

function addParsedVariations(rbd_variation::RBDVariation, config_id::Int, rulesets_collection_id::Int, ic_cell_id::Int, parsed_variations::ParsedVariations; reference_config_variation_id::Int=0, reference_rulesets_variation_id::Int=0, reference_ic_cell_variation_id::Int=ic_cell_id==-1 ? -1 : 0)
    return addRBDCombo(rbd_variation, config_id, rulesets_collection_id, ic_cell_id, parsed_variations; reference_config_variation_id=reference_config_variation_id, reference_rulesets_variation_id=reference_rulesets_variation_id, reference_ic_cell_variation_id=reference_ic_cell_variation_id)
end

function variationTarget(av::AbstractVariation)
    xml_path = getVariationXMLPath(av)
    if startswith(xml_path[1], "hypothesis_ruleset:name:")
        return :rulesets
    elseif startswith(xml_path[1], "cell_patches:name:")
        return :ic_cell
    else
        return :config
    end
end

################## Grid Variations ##################

function addGridConfigVariation(config_id::Int, AV::Vector{<:AbstractVariation}; reference_config_variation_id::Int=0)
    addColumnsByPathsFn = (paths) -> addConfigVariationColumns(config_id, paths, [getVariationDataType(av) for av in AV])
    prepareAddNewFn = (static_column_names, varied_column_names) -> prepareAddNewConfigVariations(config_id, static_column_names, varied_column_names; reference_config_variation_id=reference_config_variation_id)
    addRowFn = (features, static_values, varied_values) -> addConfigVariationRow(config_id, features, static_values, varied_values)
    return addGrid(AV, addColumnsByPathsFn, prepareAddNewFn, addRowFn)
end

addGridConfigVariation(config_folder::String, AV::Vector{<:AbstractVariation}; reference_config_variation_id::Int=0) = addGridConfigVariation(retrieveID("configs", config_folder), AV; reference_config_variation_id=reference_config_variation_id)
addGridConfigVariation(config_id::Int, AV::AbstractVariation; reference_config_variation_id::Int=0) = addGridConfigVariation(config_id, [AV]; reference_config_variation_id=reference_config_variation_id)
addGridConfigVariation(config_folder::String, AV::AbstractVariation; reference_config_variation_id::Int=0) = addGridConfigVariation(config_folder, [AV]; reference_config_variation_id=reference_config_variation_id)

function addGridRulesetsVariation(rulesets_collection_id::Int, AV::Vector{<:AbstractVariation}; reference_rulesets_variation_id::Int=0)
    addColumnsByPathsFn = (paths) -> addRulesetsVariationsColumns(rulesets_collection_id, paths)
    prepareAddNewFn = (static_names, varied_names) -> prepareAddNewRulesetsVariations(rulesets_collection_id, static_names, varied_names; reference_rulesets_variation_id=reference_rulesets_variation_id)
    addRowFn = (features, static_values, varied_values) -> addRulesetsVariationRow(rulesets_collection_id, features, static_values, varied_values)
    return addGrid(AV, addColumnsByPathsFn, prepareAddNewFn, addRowFn)
end

addGridRulesetsVariation(rulesets_collection_folder::String, AV::Vector{<:AbstractVariation}; reference_rulesets_variation_id::Int=0) = addGridRulesetsVariation(retrieveID("rulesets_collections", rulesets_collection_folder), AV; reference_rulesets_variation_id=reference_rulesets_variation_id)
addGridRulesetsVariation(rulesets_collection_id::Int, AV::AbstractVariation; reference_rulesets_variation_id::Int=0) = addGridRulesetsVariation(rulesets_collection_id, [AV]; reference_rulesets_variation_id=reference_rulesets_variation_id)
addGridRulesetsVariation(rulesets_collection_folder::String, AV::AbstractVariation; reference_rulesets_variation_id::Int=0) = addGridRulesetsVariation(rulesets_collection_folder, [AV]; reference_rulesets_variation_id=reference_rulesets_variation_id)

function addGridICCellVariation(ic_cell_id::Int, AV::Vector{<:AbstractVariation}; reference_ic_cell_variation_id::Int=ic_cell_id==-1 ? -1 : 0)
    addColumnsByPathsFn = (paths) -> addICCellVariationColumns(ic_cell_id, paths)
    prepareAddNewFn = (static_names, varied_names) -> prepareAddNewICCellVariations(ic_cell_id, static_names, varied_names; reference_ic_cell_variation_id=reference_ic_cell_variation_id)
    addRowFn = (features, static_values, varied_values) -> addICCellVariationRow(ic_cell_id, features, static_values, varied_values)
    return addGrid(AV, addColumnsByPathsFn, prepareAddNewFn, addRowFn)
end

addGridICCellVariation(ic_cell_folder::String, AV::Vector{<:AbstractVariation}; reference_ic_cell_variation_id::Int=ic_cell_folder=="" ? -1 : 0) = addGridICCellVariation(retrieveID("ic_cells", ic_cell_folder), AV; reference_ic_cell_variation_id=reference_ic_cell_variation_id)
addGridICCellVariation(ic_cell_id::Int, AV::AbstractVariation; reference_ic_cell_variation_id::Int=ic_cell_id==-1 ? -1 : 0) = addGridICCellVariation(ic_cell_id, [AV]; reference_ic_cell_variation_id=reference_ic_cell_variation_id)
addGridICCellVariation(ic_cell_folder::String, AV::AbstractVariation; reference_ic_cell_variation_id::Int=ic_cell_folder=="" ? -1 : 0) = addGridICCellVariation(ic_cell_folder, [AV]; reference_ic_cell_variation_id=reference_ic_cell_variation_id)

function addGridCombo(::GridVariation, config_id::Int, rulesets_collection_id::Int, ic_cell_id::Int, pv::ParsedVariations; reference_config_variation_id::Int=0, reference_rulesets_variation_id::Int=0, reference_ic_cell_variation_id::Int=ic_cell_id==-1 ? -1 : 0)
    if isempty(pv.config_variations)
        config_variation_ids = [reference_config_variation_id]
    else
        config_variation_ids = addGridConfigVariation(config_id, pv.config_variations; reference_config_variation_id=reference_config_variation_id)
    end
    if isempty(pv.rulesets_variations)
        rulesets_variation_ids = [reference_rulesets_variation_id]
    else
        rulesets_variation_ids = addGridRulesetsVariation(rulesets_collection_id, pv.rulesets_variations; reference_rulesets_variation_id=reference_rulesets_variation_id)
    end
    if isempty(pv.ic_cell_variations)
        ic_cell_variation_ids = [ic_cell_id==-1 ? -1 : reference_ic_cell_variation_id]
    else
        ic_cell_variation_ids = addGridICCellVariation(ic_cell_id, pv.ic_cell_variations; reference_ic_cell_variation_id=reference_ic_cell_variation_id)
    end
    all_config_variation_ids, all_rulesets_variation_ids, all_ic_cell_variation_ids = ndgrid(config_variation_ids, rulesets_variation_ids, ic_cell_variation_ids)
    return all_config_variation_ids, all_rulesets_variation_ids, all_ic_cell_variation_ids
end

addGridCombo(config_folder::String, rulesets_collection_folder::String, ic_cell_folder::String, pv::ParsedVariations; reference_config_variation_id::Int=0, reference_rulesets_variation_id::Int=0, reference_ic_cell_variation_id::Int=ic_cell_folder=="" ? -1 : 0) = addGridCombo(retrieveID("configs", config_folder), retrieveID("rulesets_collections", rulesets_collection_folder), retrieveID("ic_cells", ic_cell_folder), pv; reference_config_variation_id=reference_config_variation_id, reference_rulesets_variation_id=reference_rulesets_variation_id, reference_ic_cell_variation_id=reference_ic_cell_variation_id)

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

function orthogonalLHS_relaxed(k::Int, d::Int)
    # I have this here because this technically gives all possible orthogonal lhs samples, but my orthogonalLHS gives a more uniform LHS
    n = k^d
    lhs_inds = zeros(Int, (n, d))
    for i in 1:d
        bin_size = n / (k^(i - 1)) |> ceil |> Int # number of sampled points grouped by all previous dims
        n_bins = k^(i - 1) # number of bins in this dimension
        if i == 1
            lhs_inds[:, 1] = 1:n
            continue
        else
            bin_inds_gps = [(j - 1) * bin_size .+ (1:bin_size) |> collect for j in 1:n_bins] # the indexes in y corresponding to each of the bins (this relies on the sorting step below to easily find which points are currently in the same box and need to be separated along the ith dimension)
            for pt_ind = 1:k
                y_vals = shuffle((pt_ind - 1) * Int(n / k) .+ (1:Int(n / k)))
                inds = zeros(Int, Int(n / k))
                for (j, bin_inds) in enumerate(bin_inds_gps)
                    for s in 1:Int(n / k^(i))
                        rand_ind_of_ind = rand(1:length(bin_inds))
                        rand_ind = popat!(bin_inds, rand_ind_of_ind) # random value remaining in bin, remove it so we don't pick it again
                        inds[(j-1)*Int(n / k^(i))+s] = rand_ind # record the index
                    end
                end
                lhs_inds[inds, i] = y_vals
            end
        end
        lhs_inds[:, 1:i] = sortslices(lhs_inds[:, 1:i], dims=1, by=x -> (x ./ (n / k) .|> ceil .|> Int)) # sort the found values so that sampled points in the same box upon projection into the 1:i dims are adjacent
    end
end

function generateLHSCDFs(n::Int, d::Int; add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG=rng, orthogonalize::Bool=orthogonalize)
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

function addLHS(n::Integer, AV::Vector{<:AbstractVariation}, addColumnsByPathsFn::Function, prepareAddNewFn::Function, addRowFn::Function; add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG, orthogonalize::Bool=true)
    d = length(AV)
    cdfs = generateLHSCDFs(n, d; add_noise=add_noise, rng=rng, orthogonalize=orthogonalize)
    return cdfsToVariations(cdfs, AV, addColumnsByPathsFn, prepareAddNewFn, addRowFn)
end

function addLHSConfigVariation(n::Integer, config_id::Int, AV::Vector{<:AbstractVariation}; reference_config_variation_id::Int=0, add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG)
    fns = prepareConfigVariationFunctions(config_id, AV; reference_config_variation_id=reference_config_variation_id)
    return addLHS(n, AV, fns...; add_noise=add_noise, rng=rng)
end

addLHSConfigVariation(n::Integer, config_folder::String, AV::Vector{<:AbstractVariation}; reference_config_variation_id::Int=0, add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG) = addLHSConfigVariation(n, retrieveID("configs", config_folder), AV; reference_config_variation_id=reference_config_variation_id, add_noise=add_noise, rng=rng)
addLHSConfigVariation(n::Integer, config_id::Int, AV::AbstractVariation; reference_config_variation_id::Int=0, add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG) = addLHSConfigVariation(n, config_id, [AV]; reference_config_variation_id=reference_config_variation_id, add_noise=add_noise, rng=rng)
addLHSConfigVariation(n::Integer, config_folder::String, AV::AbstractVariation; reference_config_variation_id::Int=0, add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG) = addLHSConfigVariation(n, config_folder, [AV]; reference_config_variation_id=reference_config_variation_id, add_noise=add_noise, rng=rng)

function addLHSRulesetsVariation(n::Integer, rulesets_collection_id::Int, AV::Vector{<:AbstractVariation}; reference_rulesets_variation_id::Int=0, add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG)
    fns = prepareRulesetsVariationFunctions(rulesets_collection_id; reference_rulesets_variation_id=reference_rulesets_variation_id)
    return addLHS(n, AV, fns...; add_noise=add_noise, rng=rng)
end

addLHSRulesetsVariation(n::Integer, rulesets_collection_folder::String, AV::Vector{<:AbstractVariation}; reference_config_variation_id::Int=0, add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG) = addLHSRulesetsVariation(n, retrieveID("rulesets_collections", rulesets_collection_folder), AV; reference_config_variation_id=reference_config_variation_id, add_noise=add_noise, rng=rng)
addLHSRulesetsVariation(n::Integer, rulesets_collection_id::Int, AV::AbstractVariation; reference_config_variation_id::Int=0, add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG) = addLHSRulesetsVariation(n, rulesets_collection_id, [AV]; reference_config_variation_id=reference_config_variation_id, add_noise=add_noise, rng=rng)
addLHSRulesetsVariation(n::Integer, rulesets_collection_folder::String, AV::AbstractVariation; reference_config_variation_id::Int=0, add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG) = addLHSRulesetsVariation(n, rulesets_collection_folder, [AV]; reference_config_variation_id=reference_config_variation_id, add_noise=add_noise, rng=rng)

function addLHSICCellVariation(n::Integer, ic_cell_id::Int, AV::Vector{<:AbstractVariation}; reference_ic_cell_variation_id::Int=ic_cell_id==-1 ? -1 : 0, add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG)
    fns = prepareICCellVariationFunctions(ic_cell_id; reference_ic_cell_variation_id=reference_ic_cell_variation_id)
    return addLHS(n, AV, fns...; add_noise=add_noise, rng=rng)
end

addLHSICCellVariation(n::Integer, ic_cell_folder::String, AV::Vector{<:AbstractVariation}; reference_ic_cell_variation_id::Int=ic_cell_folder=="" ? -1 : 0, add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG) = addLHSICCellVariation(n, retrieveID("ic_cells", ic_cell_folder), AV; reference_ic_cell_variation_id=reference_ic_cell_variation_id, add_noise=add_noise, rng=rng)
addLHSICCellVariation(n::Integer, ic_cell_id::Int, AV::AbstractVariation; reference_ic_cell_variation_id::Int=ic_cell_id==-1 ? -1 : 0, add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG) = addLHSICCellVariation(n, ic_cell_id, [AV]; reference_ic_cell_variation_id=reference_ic_cell_variation_id, add_noise=add_noise, rng=rng)
addLHSICCellVariation(n::Integer, ic_cell_folder::String, AV::AbstractVariation; reference_ic_cell_variation_id::Int=ic_cell_folder=="" ? -1 : 0, add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG) = addLHSICCellVariation(n, ic_cell_folder, [AV]; reference_ic_cell_variation_id=reference_ic_cell_variation_id, add_noise=add_noise, rng=rng)

function addLHSCombo(lhs_variation::LHSVariation, config_id::Int, rulesets_collection_id::Int, ic_cell_id::Int, pv::ParsedVariations; reference_config_variation_id::Int=0, reference_rulesets_variation_id::Int=0, reference_ic_cell_variation_id::Int=ic_cell_id==-1 ? -1 : 0)
    d = length(pv.config_variations) + length(pv.rulesets_variations) + length(pv.ic_cell_variations)
    cdfs = generateLHSCDFs(lhs_variation.n, d; add_noise=lhs_variation.add_noise, rng=lhs_variation.rng, orthogonalize=lhs_variation.orthogonalize)
    if isempty(pv.config_variations)
        config_variation_ids = fill(reference_config_variation_id, lhs_variation.n)
    else
        config_variation_ids = cdfsToVariations(cdfs[:, 1:length(pv.config_variations)], pv.config_variations, prepareConfigVariationFunctions(config_id, pv.config_variations; reference_config_variation_id=reference_config_variation_id)...)
    end
    if isempty(pv.rulesets_variations)
        rulesets_variation_ids = fill(reference_rulesets_variation_id, lhs_variation.n)
    else
        rulesets_variation_ids = cdfsToVariations(cdfs[:, length(pv.config_variations)+1:end], pv.rulesets_variations, prepareRulesetsVariationFunctions(rulesets_collection_id; reference_rulesets_variation_id=reference_rulesets_variation_id)...)
    end
    if isempty(pv.ic_cell_variations)
        ic_cell_variation_ids = fill(ic_cell_id==-1 ? -1 : reference_ic_cell_variation_id, lhs_variation.n)
    else
        ic_cell_variation_ids = cdfsToVariations(cdfs[:, length(pv.config_variations)+length(pv.rulesets_variations)+1:end], pv.ic_cell_variations, prepareICCellVariationFunctions(ic_cell_id; reference_ic_cell_variation_id=reference_ic_cell_variation_id)...)
    end
    return config_variation_ids, rulesets_variation_ids, ic_cell_variation_ids
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

function addSobolCombo(sobol_variation::SobolVariation, config_id::Int, rulesets_collection_id::Int, ic_cell_id::Int, pv::ParsedVariations; reference_config_variation_id::Int=0, reference_rulesets_variation_id::Int=0, reference_ic_cell_variation_id::Int=ic_cell_id==-1 ? -1 : 0)
    d = length(pv.config_variations) + length(pv.rulesets_variations) + length(pv.ic_cell_variations)
    cdfs = generateSobolCDFs(sobol_variation, d) # cdfs is (d, sobol_variation.n_matrices, sobol_variation.n)
    cdfs_reshaped = reshape(cdfs, (d, sobol_variation.n_matrices * sobol_variation.n)) # reshape to (d, sobol_variation.n_matrices * sobol_variation.n) so that each column is a sobol sample
    cdfs_reshaped = cdfs_reshaped' # transpose so that each row is a sobol sample
    config_variation_ids = cdfsToVariations(cdfs_reshaped[:,1:length(pv.config_variations)], pv.config_variations, prepareConfigVariationFunctions(config_id, pv.config_variations; reference_config_variation_id=reference_config_variation_id)...)
    rulesets_variation_ids = cdfsToVariations(cdfs_reshaped[:,length(pv.config_variations)+1:end], pv.rulesets_variations, prepareRulesetsVariationFunctions(rulesets_collection_id; reference_rulesets_variation_id=reference_rulesets_variation_id)...)
    ic_cell_variation_ids = cdfsToVariations(cdfs_reshaped[:,length(pv.config_variations)+length(pv.rulesets_variations)+1:end], pv.ic_cell_variations, prepareICCellVariationFunctions(ic_cell_id; reference_ic_cell_variation_id=reference_ic_cell_variation_id)...)
    config_variation_ids = reshape(config_variation_ids, (sobol_variation.n_matrices, sobol_variation.n))' # first, each sobol matrix variation indices goes into a row so that each column is the kth sample for each matrix; take the transpose so that each column corresponds to a matrix
    rulesets_variation_ids = reshape(rulesets_variation_ids, (sobol_variation.n_matrices, sobol_variation.n))'
    ic_cell_variation_ids = reshape(ic_cell_variation_ids, (sobol_variation.n_matrices, sobol_variation.n))'
    return config_variation_ids, rulesets_variation_ids, ic_cell_variation_ids, cdfs, pv
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

function addRBDCombo(rbd_variation::RBDVariation, config_id::Int, rulesets_collection_id::Int, ic_cell_id::Int, pv::ParsedVariations; reference_config_variation_id::Int=0, reference_rulesets_variation_id::Int=0, reference_ic_cell_variation_id::Int=ic_cell_id==-1 ? -1 : 0, rng::AbstractRNG=Random.GLOBAL_RNG, use_sobol::Bool=true)
    d = length(pv.config_variations) + length(pv.rulesets_variations) + length(pv.ic_cell_variations)
    cdfs, S = generateRBDCDFs(rbd_variation, d)
    config_variation_ids = cdfsToVariations(cdfs[:, 1:length(pv.config_variations)], pv.config_variations, prepareConfigVariationFunctions(config_id, pv.config_variations; reference_config_variation_id=reference_config_variation_id)...)
    rulesets_variation_ids = cdfsToVariations(cdfs[:, length(pv.config_variations)+1:end], pv.rulesets_variations, prepareRulesetsVariationFunctions(rulesets_collection_id; reference_rulesets_variation_id=reference_rulesets_variation_id)...)
    ic_cell_variation_ids = cdfsToVariations(cdfs[:, length(pv.config_variations)+length(pv.rulesets_variations)+1:end], pv.ic_cell_variations, prepareICCellVariationFunctions(ic_cell_id; reference_ic_cell_variation_id=reference_ic_cell_variation_id)...)
    config_variations_matrix = createSortedRBDMatrix(config_variation_ids, S)
    rulesets_variations_matrix = createSortedRBDMatrix(rulesets_variation_ids, S)
    ic_cell_variations_matrix = createSortedRBDMatrix(ic_cell_variation_ids, S)
    return config_variation_ids, rulesets_variation_ids, ic_cell_variation_ids, config_variations_matrix, rulesets_variations_matrix, ic_cell_variations_matrix
end

################## Sampling Helper Functions ##################

function cdfsToVariations(cdfs::AbstractMatrix{Float64}, AV::Vector{<:AbstractVariation}, addColumnsByPathsFn::Function, prepareAddNewFn::Function, addRowFn::Function)
    n = size(cdfs, 1)
    new_values = []
    for (i, av) in enumerate(AV)
        new_value = getVariationValues(av; cdf=cdfs[:,i]) # ok, all the new values for the given parameter
        push!(new_values, new_value)
    end

    static_values, table_features = setUpColumns(AV, addColumnsByPathsFn, prepareAddNewFn)

    variation_ids = zeros(Int, n)

    for i in 1:n
        varied_values = [new_value[i] for new_value in new_values] .|> string |> x -> join("\"" .* x .* "\"", ",")
        variation_ids[i] = addRowFn(table_features, static_values, varied_values)
    end
    return variation_ids
end

function prepareConfigVariationFunctions(config_id::Int, AV::Vector{<:AbstractVariation}; reference_config_variation_id=0)
    addColumnsByPathsFn = (paths) -> addConfigVariationColumns(config_id, paths, [getVariationDataType(av) for av in AV])
    prepareAddNewFn = (static_column_names, varied_column_names) -> prepareAddNewConfigVariations(config_id, static_column_names, varied_column_names; reference_config_variation_id=reference_config_variation_id)
    addRowFn = (features, static_values, varied_values) -> addConfigVariationRow(config_id, features, static_values, varied_values)
    return addColumnsByPathsFn, prepareAddNewFn, addRowFn
end

function prepareRulesetsVariationFunctions(rulesets_collection_id::Int; reference_rulesets_variation_id::Int=0)
    addColumnsByPathsFn = (paths) -> addRulesetsVariationsColumns(rulesets_collection_id, paths)
    prepareAddNewFn = (static_column_names, varied_column_names) -> prepareAddNewRulesetsVariations(rulesets_collection_id, static_column_names, varied_column_names; reference_rulesets_variation_id=reference_rulesets_variation_id)
    addRowFn = (features, static_values, varied_values) -> addRulesetsVariationRow(rulesets_collection_id, features, static_values, varied_values)
    return addColumnsByPathsFn, prepareAddNewFn, addRowFn
end

function prepareICCellVariationFunctions(ic_cell_id::Int; reference_ic_cell_variation_id::Int=0)
    addColumnsByPathsFn = (paths) -> addICCellVariationColumns(ic_cell_id, paths)
    prepareAddNewFn = (static_column_names, varied_column_names) -> prepareAddNewICCellVariations(ic_cell_id, static_column_names, varied_column_names; reference_ic_cell_variation_id=reference_ic_cell_variation_id)
    addRowFn = (features, static_values, varied_values) -> addICCellVariationRow(ic_cell_id, features, static_values, varied_values)
    return addColumnsByPathsFn, prepareAddNewFn, addRowFn
end