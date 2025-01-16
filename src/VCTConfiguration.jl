export addDomainVariationDimension!, addCustomDataVariationDimension!, addAttackRateVariationDimension!

################## XML Functions ##################

function openXML(path_to_xml::String)
    return parse_file(path_to_xml)
end

closeXML(xml_doc::XMLDocument) = free(xml_doc)

function retrieveElement(xml_doc::XMLDocument, xml_path::Vector{<:AbstractString}; required::Bool=true)
    current_element = root(xml_doc)
    for path_element in xml_path
        if !occursin(":",path_element)
            current_element = find_element(current_element, path_element)
            if isnothing(current_element)
                required ? retrieveElementError(xml_path, path_element) : return nothing
            end
            continue
        end
        # Deal with checking attributes
        path_element_name, attribute_check = split(path_element, ":", limit=2)
        attribute_name, attribute_value = split(attribute_check, ":") # if I need to add a check for multiple attributes, we can do that later
        candidate_elements = get_elements_by_tagname(current_element, path_element_name)
        found = false
        for ce in candidate_elements
            if attribute(ce, attribute_name) == attribute_value
                found = true
                current_element = ce
                break
            end
        end
        if !found
            required ? retrieveElementError(xml_path, path_element) : return nothing
        end
    end
    return current_element
end

function retrieveElementError(xml_path::Vector{<:AbstractString}, path_element::String)
    error_msg = "Element not found: $(join(xml_path, " -> "))"
    error_msg *= "\n\tFailed at: $(path_element)"
    throw(ArgumentError(error_msg))
end

function getField(xml_doc::XMLDocument, xml_path::Vector{<:AbstractString}; required::Bool=true)
    return retrieveElement(xml_doc, xml_path; required=required) |> content
end

function updateField(xml_doc::XMLDocument, xml_path::Vector{<:AbstractString}, new_value::Union{Int,Real,String})
    current_element = retrieveElement(xml_doc, xml_path; required=true)
    set_content(current_element, string(new_value))
    return nothing
end

function updateField(xml_doc::XMLDocument, xml_path_and_value::Vector{Any})
    return updateField(xml_doc, xml_path_and_value[1:end-1],xml_path_and_value[end])
end

function xmlPathToColumnName(xml_path::Vector{<:AbstractString})
    return join(xml_path, "/")
end

columnNameToXMLPath(column_name::String) = split(column_name, "/")

function updateFieldsFromCSV(xml_doc::XMLDocument, path_to_csv::String)
    df = CSV.read(path_to_csv, DataFrame; header=false, silencewarnings=true, types=String)
    for i = axes(df,1)
        df[i, :] |> Vector |> x -> filter!(!ismissing, x) |> x -> updateField(xml_doc, x)
    end
end

################## Configuration Functions ##################

function loadConfiguration(M::AbstractMonad)
    path_to_xml = joinpath(data_dir, "inputs", "configs", M.inputs.config.folder, "config_variations", "config_variation_$(M.variation_ids.config).xml")
    if isfile(path_to_xml)
        return
    end
    mkpath(dirname(path_to_xml))
    path_to_xml_src = joinpath(data_dir, "inputs", "configs", M.inputs.config.folder, "PhysiCell_settings.xml")
    cp(path_to_xml_src, path_to_xml, force=true)

    xml_doc = openXML(path_to_xml)
    query = constructSelectQuery("config_variations", "WHERE config_variation_id=$(M.variation_ids.config);")
    variation_row = queryToDataFrame(query; db=configDB(M.inputs.config.folder), is_row=true)
    for column_name in names(variation_row)
        if column_name == "config_variation_id"
            continue
        end
        xml_path = columnNameToXMLPath(column_name)
        updateField(xml_doc, xml_path, variation_row[1, column_name])
    end
    save_file(xml_doc, path_to_xml)
    closeXML(xml_doc)
    return
end

function loadConfiguration(sampling::Sampling)
    for index in eachindex(sampling.variation_ids)
        monad = Monad(sampling, index) # instantiate a monad with the variation_id and the simulation ids already found
        loadConfiguration(monad)
    end
end

function loadRulesets(M::AbstractMonad)
    if M.variation_ids.rulesets_collection == -1 # no rules being used
        return
    end
    path_to_rulesets_collections_folder = joinpath(data_dir, "inputs", "rulesets_collections", M.inputs.rulesets_collection.folder)
    path_to_rulesets_xml = joinpath(path_to_rulesets_collections_folder, "rulesets_collections_variations", "rulesets_variation_$(M.variation_ids.rulesets_collection).xml")
    if isfile(path_to_rulesets_xml) # already have the rulesets_collection variation created
        return
    end
    mkpath(dirname(path_to_rulesets_xml)) # ensure the directory exists

    # create xml file using LightXML
    path_to_base_xml = joinpath(path_to_rulesets_collections_folder, "base_rulesets.xml")
    if !isfile(path_to_base_xml)
        # this could happen if the rules are not being varied (so no call to addRulesetsVariationsColumns) and then a sim runs without the base_rulesets.xml being created yet
        writeRules(path_to_base_xml, joinpath(path_to_rulesets_collections_folder, "base_rulesets.csv"))
    end
        
    xml_doc = parse_file(path_to_base_xml)
    if M.variation_ids.rulesets_collection != 0 # only update if not using the base variation for the ruleset
        query = constructSelectQuery("rulesets_collection_variations", "WHERE rulesets_collection_variation_id=$(M.variation_ids.rulesets_collection);")
        variation_row = queryToDataFrame(query; db=rulesetsCollectionDB(M), is_row=true)
        for column_name in names(variation_row)
            if column_name == "rulesets_collection_variation_id"
                continue
            end
            xml_path = columnNameToXMLPath(column_name)
            updateField(xml_doc, xml_path, variation_row[1, column_name])
        end
    end
    save_file(xml_doc, path_to_rulesets_xml)
    closeXML(xml_doc)
    return
end

function loadICCells(M::AbstractMonad)
    if M.inputs.ic_cell.id == -1 # no ic cells being used
        return
    end
    path_to_ic_cells_folder = joinpath(data_dir, "inputs", "ics", "cells", M.inputs.ic_cell.folder)
    if isfile(joinpath(path_to_ic_cells_folder, "cells.csv")) # ic already given by cells.csv
        return
    end
    path_to_ic_cells_xml = joinpath(path_to_ic_cells_folder, "ic_cell_variations", "ic_cell_variation_$(M.variation_ids.ic_cell).xml")
    if isfile(path_to_ic_cells_xml) # already have the ic cell variation created
        return
    end
    mkpath(dirname(path_to_ic_cells_xml))

    path_to_base_xml = joinpath(path_to_ic_cells_folder, "cells.xml")
    xml_doc = parse_file(path_to_base_xml)
    if M.variation_ids.ic_cell != 0 # only update if not using the base variation for the ic cells
        query = constructSelectQuery("ic_cell_variations", "WHERE ic_cell_variation_id=$(M.variation_ids.ic_cell);")
        variation_row = queryToDataFrame(query; db=icCellDB(M.inputs.ic_cell.folder), is_row=true)
        for column_name in names(variation_row)
            if column_name == "ic_cell_variation_id"
                continue
            end
            xml_path = columnNameToXMLPath(column_name)
            updateField(xml_doc, xml_path, variation_row[1, column_name])
        end
    end
    save_file(xml_doc, path_to_ic_cells_xml)
    closeXML(xml_doc)
    return
end

function pathToICCell(simulation::Simulation)
    @assert simulation.inputs.ic_cell.id != -1 "No IC cell variation being used" # we should have already checked this before calling this function
    path_to_ic_cell_folder = joinpath(data_dir, "inputs", "ics", "cells", simulation.inputs.ic_cell.folder)
    if isfile(joinpath(path_to_ic_cell_folder, "cells.csv")) # ic already given by cells.csv
        return joinpath(path_to_ic_cell_folder, "cells.csv")
    end
    path_to_ic_cell_variations = joinpath(path_to_ic_cell_folder, "ic_cell_variations")
    path_to_ic_cell_xml = joinpath(path_to_ic_cell_variations, "ic_cell_variation_$(simulation.variation_ids.ic_cell).xml")
    path_to_ic_cell_file = joinpath(path_to_ic_cell_variations, "ic_cell_variation_$(simulation.variation_ids.ic_cell)_s$(simulation.id).csv")
    generateICCell(path_to_ic_cell_xml, path_to_ic_cell_file)
    return path_to_ic_cell_file
end

################## XML Path Helper Functions ##################

# can I define my own macro that takes all these functions and adds methods for FN(cell_def, node::String) and FN(cell_def, path_suffix::Vector{String})??
function cellDefinitionPath(cell_definition::String)::Vector{String}
    return ["cell_definitions", "cell_definition:name:$(cell_definition)"]
end

function phenotypePath(cell_definition::String)::Vector{String}
    return [cellDefinitionPath(cell_definition); "phenotype"]
end

cyclePath(cell_definition::String)::Vector{String} = [phenotypePath(cell_definition); "cycle"]
deathPath(cell_definition::String)::Vector{String} = [phenotypePath(cell_definition); "death"]
apoptosisPath(cell_definition::String)::Vector{String} = [deathPath(cell_definition); "model:code:100"]
necrosisPath(cell_definition::String)::Vector{String} = [deathPath(cell_definition); "model:code:101"]

motilityPath(cell_definition::String)::Vector{String} = [phenotypePath(cell_definition); "motility"]
motilityPath(cell_definition::String, field_name::String)::Vector{String} = [motilityPath(cell_definition); field_name]

cellInteractionsPath(cell_definition::String)::Vector{String} = [phenotypePath(cell_definition); "cell_interactions"]
cellInteractionsPath(cell_definition::String, field_name::String)::Vector{String} = [cellInteractionsPath(cell_definition); field_name]

attackRatesPath(cell_definition::String)::Vector{String} = cellInteractionsPath(cell_definition, "attack_rates")
attackRatesPath(cell_definition::String, target_name::String)::Vector{String} = [attackRatesPath(cell_definition); "attack_rate:name:$(target_name)"]

customDataPath(cell_definition::String)::Vector{String} = [cellDefinitionPath(cell_definition); "custom_data"]

function customDataPath(cell_definition::String, field_name::String)::Vector{String}
    return [customDataPath(cell_definition); field_name]
end

function customDataPath(cell_definition::String, field_names::Vector{<:AbstractString})
    return [customDataPath(cell_definition, field_name) for field_name in field_names]
end

function userParameterPath(field_name::String)::Vector{String}
    return ["user_parameters"; field_name]
end

function userParameterPath(field_names::Vector{<:AbstractString})
    return [userParameterPath(field_name) for field_name in field_names]
end

function initialConditionPath()
    return ["initial_conditions"; "cell_positions"; "filename"]
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

################## Simplify Name Functions ##################

function simpleConfigVariationNames(name::String)
    if name == "config_variation_id"
        return "ConfigVarID"
    elseif name == "overall/max_time"
        return "Max Time"
    elseif name == "save/full_data/interval"
        return "Full Save Interval"
    elseif name == "save/SVG/interval"
        return "SVG Save Interval"
    elseif startswith(name, "cell_definitions")
        return getCellParameterName(name)
    else
        return name
    end
end

function simpleRulesetsVariationNames(name::String)
    if name == "rulesets_collection_variation_id"
        return "RulesVarID"
    elseif startswith(name, "hypothesis_ruleset")
        return getRuleParameterName(name)
    else
        return name
    end
end

function simpleICCellVariationNames(name::String)
    if name == "ic_cell_variation_id"
        return "ICCellVarID"
    elseif startswith(name, "cell_patches")
        return getICCellParameterName(name)
    else
        return name
    end
end

function getCellParameterName(column_name::String)
    xml_path = columnNameToXMLPath(column_name)
    cell_type = split(xml_path[2], ":")[3]
    target_name = ""
    for component in xml_path[3:end]
        if contains(component, ":name:")
            target_name = split(component, ":")[3]
            break
        elseif contains(component, ":code:")
            target_code = split(component, ":")[3]
            if target_code == "100"
                target_name = "apop"
            elseif target_code == "101"
                target_name = "necr"
            else
                throw(ArgumentError("Unknown code in xml path: $(target_code)"))
            end
            break
        end
    end
    suffix = xml_path[end]
    if target_name != ""
        suffix = "$(target_name) $(suffix)"
    end
    return replace("$(cell_type): $(suffix)", '_' => ' ')
end

function getRuleParameterName(name::String)
    xml_path = columnNameToXMLPath(name)
    cell_type = split(xml_path[1], ":")[3]
    behavior = split(xml_path[2], ":")[3]
    is_decreasing = xml_path[3] == "decreasing_signals"
    if xml_path[4] == "max_response"
        ret_val = "$(cell_type): $(behavior) $(is_decreasing ? "min" : "max")"
    else
        response = is_decreasing ? "decreases" : "increases"
        signal = split(xml_path[4], ":")[3]
        ret_val = "$(cell_type): $(signal) $(response) $(behavior) $(xml_path[5])"
    end
    return ret_val |> x->replace(x, '_' => ' ')
end

function getICCellParameterName(name::String)
    xml_path = columnNameToXMLPath(name)
    cell_type = split(xml_path[1], ":")[3]
    patch_type = split(xml_path[2], ":")[3]
    id = split(xml_path[3], ":")[3]
    parameter = xml_path[4]
    return "$(cell_type) IC: $(patch_type)[$(id)] $(parameter)" |> x->replace(x, '_' => ' ')
end