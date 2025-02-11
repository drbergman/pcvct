using PhysiCellCellCreator

################## XML Functions ##################

function openXML(path_to_xml::String)
    return parse_file(path_to_xml)
end

closeXML(xml_doc::XMLDocument) = free(xml_doc)

function getChildByAttribute(parent_element::XMLElement, path_element_split::Vector{<:AbstractString})
    path_element_name, attribute_name, attribute_value = path_element_split
    candidate_elements = get_elements_by_tagname(parent_element, path_element_name)
    for ce in candidate_elements
        if attribute(ce, attribute_name) == attribute_value
            return ce
        end
    end
    return nothing
end

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
        current_element = getChildByAttribute(current_element, split(path_element, ":"))
        if isnothing(current_element)
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

function makeXMLPath(xml_doc::XMLDocument, xml_path::Vector{<:AbstractString})
    current_element = root(xml_doc)
    for path_element in xml_path
        if !occursin(":",path_element)
            child_element = find_element(current_element, path_element)
            if isnothing(child_element)
                current_element = new_child(current_element, path_element)
            else
                current_element = child_element
            end
            continue
        end
        # Deal with checking attributes
        path_element_split = split(path_element, ":")
        child_element = getChildByAttribute(current_element, path_element_split)
        if isnothing(child_element)
            path_element_name, attribute_name, attribute_value = path_element_split
            child_element = new_child(current_element, path_element_name)
            set_attribute(child_element, attribute_name, attribute_value)
        end
        current_element = child_element
    end
    return nothing
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
    path_to_config_xml = joinpath(data_dir, "inputs", "configs", simulation.inputs.config.folder, "config_variations", "config_variation_$(simulation.variation_ids.config).xml")
    xml_doc = openXML(path_to_config_xml)
    domain_dict = Dict{String,Float64}()
    for d in ["x", "y", "z"]
        for side in ["min", "max"]
            key = "$(d)_$(side)"
            xml_path = ["domain"; key]
            domain_dict[key] = getField(xml_doc, xml_path) |> x -> parse(Float64, x)
        end
    end
    closeXML(xml_doc)
    path_to_ic_cell_variations = joinpath(path_to_ic_cell_folder, "ic_cell_variations")
    path_to_ic_cell_xml = joinpath(path_to_ic_cell_variations, "ic_cell_variation_$(simulation.variation_ids.ic_cell).xml")
    path_to_ic_cell_file = joinpath(path_to_ic_cell_variations, "ic_cell_variation_$(simulation.variation_ids.ic_cell)_s$(simulation.id).csv")
    generateICCell(path_to_ic_cell_xml, path_to_ic_cell_file, domain_dict)
    return path_to_ic_cell_file
end

function loadICECM(M::AbstractMonad)
    if M.inputs.ic_ecm.id == -1 # no ic ecm being used
        return
    end
    path_to_ic_ecm_folder = joinpath(data_dir, "inputs", "ics", "ecms", M.inputs.ic_ecm.folder)
    if isfile(joinpath(path_to_ic_ecm_folder, "ecm.csv")) # ic already given by ecm.csv
        return
    end
    path_to_ic_ecm_xml = joinpath(path_to_ic_ecm_folder, "ic_ecm_variations", "ic_ecm_variation_$(M.variation_ids.ic_ecm).xml")
    if isfile(path_to_ic_ecm_xml) # already have the ic ecm variation created
        return
    end
    mkpath(dirname(path_to_ic_ecm_xml))

    path_to_base_xml = joinpath(path_to_ic_ecm_folder, "ecm.xml")
    xml_doc = parse_file(path_to_base_xml)
    if M.variation_ids.ic_ecm != 0 # only update if not using the base variation for the ic ecm
        query = constructSelectQuery("ic_ecm_variations", "WHERE ic_ecm_variation_id=$(M.variation_ids.ic_ecm);")
        variation_row = queryToDataFrame(query; db=icECMDB(M.inputs.ic_ecm.folder), is_row=true)
        for column_name in names(variation_row)
            if column_name == "ic_ecm_variation_id"
                continue
            end
            xml_path = columnNameToXMLPath(column_name)
            updateField(xml_doc, xml_path, variation_row[1, column_name])
        end
    end
    save_file(xml_doc, path_to_ic_ecm_xml)
    closeXML(xml_doc)
    return
end

function pathToICECM(simulation::Simulation)
    @assert simulation.inputs.ic_ecm.id != -1 "No IC ecm variation being used" # we should have already checked this before calling this function
    path_to_ic_ecm_folder = joinpath(data_dir, "inputs", "ics", "ecms", simulation.inputs.ic_ecm.folder)
    if isfile(joinpath(path_to_ic_ecm_folder, "ecm.csv")) # ic already given by ecm.csv
        return joinpath(path_to_ic_ecm_folder, "ecm.csv")
    end
    path_to_config_xml = joinpath(data_dir, "inputs", "configs", simulation.inputs.config.folder, "config_variations", "config_variation_$(simulation.variation_ids.config).xml")
    xml_doc = openXML(path_to_config_xml)
    config_dict = Dict{String,Float64}()
    for d in ["x", "y"] # does not (yet?) support 3D
        for side in ["min", "max"]
            key = "$(d)_$(side)"
            xml_path = ["domain"; key]
            config_dict[key] = getField(xml_doc, xml_path) |> x -> parse(Float64, x)
        end
        key = "d$(d)" # d$(d) looks funny but it's just dx and dy
        xml_path = ["domain"; key]
        config_dict[key] = getField(xml_doc, xml_path) |> x -> parse(Float64, x)
    end
    closeXML(xml_doc)
    path_to_ic_ecm_variations = joinpath(path_to_ic_ecm_folder, "ic_ecm_variations")
    path_to_ic_ecm_xml = joinpath(path_to_ic_ecm_variations, "ic_ecm_variation_$(simulation.variation_ids.ic_ecm).xml")
    path_to_ic_ecm_file = joinpath(path_to_ic_ecm_variations, "ic_ecm_variation_$(simulation.variation_ids.ic_ecm)_s$(simulation.id).csv")
    generateICECM(path_to_ic_ecm_xml, path_to_ic_ecm_file, config_dict)
    return path_to_ic_ecm_file
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

function userParameterPath(field_name::String)::Vector{String}
    return ["user_parameters"; field_name]
end

function initialConditionPath()
    return ["initial_conditions"; "cell_positions"; "filename"]
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

function simpleICECMVariationNames(name::String)
    if name == "ic_ecm_variation_id"
        return "ICECMVarID"
    elseif startswith(name, "layer")
        return getICECMParameterName(name)
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

function getICECMParameterName(name::String)
    xml_path = columnNameToXMLPath(name)
    layer_id = split(xml_path[1], ":")[3]
    patch_type = split(xml_path[2], ":")[3]
    patch_id = split(xml_path[3], ":")[3]
    parameter = join(xml_path[4:end], "-")
    return "L$(layer_id)-$(patch_type)-P$(patch_id): $(parameter)" |> x->replace(x, '_' => ' ')
end