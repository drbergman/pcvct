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
        if !occursin(":", path_element)
            current_element = find_element(current_element, path_element)
            if isnothing(current_element)
                required ? retrieveElementError(xml_path, path_element) : return nothing
            end
            continue
        end
        #! Deal with checking attributes
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

function getContent(xml_doc::XMLDocument, xml_path::Vector{<:AbstractString}; required::Bool=true)
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
        #! Deal with checking attributes
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

"""
    createXMLFile(location::Symbol, M::AbstractMonad)

Create XML file for the given location and variation_id in the given monad.

The file is placed in `\$(location)_variations` and can be accessed from there to run the simulation(s).
"""
function createXMLFile(location::Symbol, M::AbstractMonad)
    path_to_folder = locationPath(location, M)
    path_to_xml = joinpath(path_to_folder, variationsTableName(location), "$(location)_variation_$(M.variation_id[location]).xml")
    if isfile(path_to_xml)
        return path_to_xml
    end
    mkpath(dirname(path_to_xml))

    path_to_base_xml = prepareBaseFile(M.inputs[location])
    @assert endswith(path_to_base_xml, ".xml") "Base XML file for $(location) must end with .xml. Got $(path_to_base_xml)"
    @assert isfile(path_to_base_xml) "Base XML file not found: $(path_to_base_xml)"

    xml_doc = openXML(path_to_base_xml)
    if M.variation_id[location] != 0 #! only update if not using the base variation for the location
        query = constructSelectQuery(variationsTableName(location), "WHERE $(locationVarIDName(location))=$(M.variation_id[location])")
        variation_row = queryToDataFrame(query; db=variationsDatabase(location, M), is_row=true)
        for column_name in names(variation_row)
            if column_name == locationVarIDName(location)
                continue
            end
            xml_path = columnNameToXMLPath(column_name)
            updateField(xml_doc, xml_path, variation_row[1, column_name])
        end
    end
    save_file(xml_doc, path_to_xml)
    closeXML(xml_doc)
    return
end

function prepareBaseFile(input_folder::InputFolder)
    if input_folder.location == :rulesets_collection
        return prepareBaseRulesetsCollectionFile(input_folder)
    end
    return joinpath(locationPath(input_folder), input_folder.basename)
end

function prepareBaseRulesetsCollectionFile(input_folder::InputFolder)
    path_to_rulesets_collection_folder = locationPath(:rulesets_collection, input_folder.folder)
    path_to_base_xml = joinpath(path_to_rulesets_collection_folder, "base_rulesets.xml")
    if !isfile(path_to_base_xml)
        #! this could happen if the rules are not being varied (so no call to addRulesetsVariationsColumns) and then a sim runs without the base_rulesets.xml being created yet
        writeRules(path_to_base_xml, joinpath(path_to_rulesets_collection_folder, "base_rulesets.csv"))
    end
    return path_to_base_xml
end

function prepareVariedInputFolder(location::Symbol, M::AbstractMonad)
    if !M.inputs[location].varied #! this input is not being varied (either unused or static)
        return
    end
    createXMLFile(location, M)
end

function prepareVariedInputFolder(location::Symbol, sampling::Sampling)
    if !sampling.inputs[location].varied #! this input is not being varied (either unused or static)
        return
    end
    for monad in Monad.(readSamplingMonadIDs(sampling))
        prepareVariedInputFolder(location, monad)
    end
end

function pathToICCell(simulation::Simulation)
    @assert simulation.inputs[:ic_cell].id != -1 "No IC cell variation being used" #! we should have already checked this before calling this function
    path_to_ic_cell_folder = locationPath(:ic_cell, simulation)
    if isfile(joinpath(path_to_ic_cell_folder, "cells.csv")) #! ic already given by cells.csv
        return joinpath(path_to_ic_cell_folder, "cells.csv")
    end
    path_to_config_xml = joinpath(locationPath(:config, simulation), "config_variations", "config_variation_$(simulation.variation_id[:config]).xml")
    xml_doc = openXML(path_to_config_xml)
    domain_dict = Dict{String,Float64}()
    for d in ["x", "y", "z"]
        for side in ["min", "max"]
            key = "$(d)_$(side)"
            xml_path = ["domain"; key]
            domain_dict[key] = getContent(xml_doc, xml_path) |> x -> parse(Float64, x)
        end
    end
    closeXML(xml_doc)
    path_to_ic_cell_variations = joinpath(path_to_ic_cell_folder, "ic_cell_variations")
    path_to_ic_cell_xml = joinpath(path_to_ic_cell_variations, "ic_cell_variation_$(simulation.variation_id[:ic_cell]).xml")
    path_to_ic_cell_file = joinpath(path_to_ic_cell_variations, "ic_cell_variation_$(simulation.variation_id[:ic_cell])_s$(simulation.id).csv")
    generateICCell(path_to_ic_cell_xml, path_to_ic_cell_file, domain_dict)
    return path_to_ic_cell_file
end

function pathToICECM(simulation::Simulation)
    @assert simulation.inputs[:ic_ecm].id != -1 "No IC ecm variation being used" #! we should have already checked this before calling this function
    path_to_ic_ecm_folder = locationPath(:ic_ecm, simulation)
    if isfile(joinpath(path_to_ic_ecm_folder, "ecm.csv")) #! ic already given by ecm.csv
        return joinpath(path_to_ic_ecm_folder, "ecm.csv")
    end
    path_to_config_xml = joinpath(locationPath(:config, simulation), "config_variations", "config_variation_$(simulation.variation_id[:config]).xml")
    xml_doc = openXML(path_to_config_xml)
    config_dict = Dict{String,Float64}()
    for d in ["x", "y"] #! does not (yet?) support 3D
        for side in ["min", "max"]
            key = "$(d)_$(side)"
            xml_path = ["domain"; key]
            config_dict[key] = getContent(xml_doc, xml_path) |> x -> parse(Float64, x)
        end
        key = "d$(d)" #! d$(d) looks funny but it's just dx and dy
        xml_path = ["domain"; key]
        config_dict[key] = getContent(xml_doc, xml_path) |> x -> parse(Float64, x)
    end
    closeXML(xml_doc)
    path_to_ic_ecm_variations = joinpath(path_to_ic_ecm_folder, "ic_ecm_variations")
    path_to_ic_ecm_xml = joinpath(path_to_ic_ecm_variations, "ic_ecm_variation_$(simulation.variation_id[:ic_ecm]).xml")
    path_to_ic_ecm_file = joinpath(path_to_ic_ecm_variations, "ic_ecm_variation_$(simulation.variation_id[:ic_ecm])_s$(simulation.id).csv")
    generateICECM(path_to_ic_ecm_xml, path_to_ic_ecm_file, config_dict)
    return path_to_ic_ecm_file
end

################## XML Path Helper Functions ##################

#! can I define my own macro that takes all these functions and adds methods for FN(cell_def, node::String) and FN(cell_def, path_suffix::Vector{String})??
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

function shortLocationVariationID(fieldname::Symbol)
    if fieldname == :config
        return :ConfigVarID
    elseif fieldname == :rulesets_collection
        return :RulesVarID
    elseif fieldname == :intracellular
        return :IntraVarID
    elseif fieldname == :ic_cell
        return :ICCellVarID
    elseif fieldname == :ic_ecm
        return :ICECMVarID
    else
        throw(ArgumentError("Got fieldname $(fieldname). However, it must be 'config', 'rulesets_collection', 'intracellular', 'ic_cell', or 'ic_ecm'."))
    end
end

shortLocationVariationID(fieldname::String) = shortLocationVariationID(Symbol(fieldname))

function shortLocationVariationID(type::Type, fieldname::Union{String, Symbol})
    return type(shortLocationVariationID(fieldname))
end

function shortVariationName(location::Symbol, name::String)
    if location == :config
        return shortConfigVariationName(name)
    elseif location == :rulesets_collection
        return shortRulesetsVariationName(name)
    elseif location == :intracellular
        return shortIntracellularVariationName(name)
    elseif location == :ic_cell
        return shortICCellVariationName(name)
    elseif location == :ic_ecm
        return shortICECMVariationName(name)
    else
        throw(ArgumentError("location must be 'config', 'rulesets_collection', 'intracellular', 'ic_cell', or 'ic_ecm'."))
    end
end

function shortConfigVariationName(name::String)
    if name == "config_variation_id"
        return shortLocationVariationID(String, "config")
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

function shortRulesetsVariationName(name::String)
    if name == "rulesets_collection_variation_id"
        return shortLocationVariationID(String, "rulesets_collection")
    elseif startswith(name, "hypothesis_ruleset")
        return getRuleParameterName(name)
    else
        return name
    end
end

function shortIntracellularVariationName(name::String)
    if name == "intracellular_variation_id"
        return shortLocationVariationID(String, "intracellular")
    else
        return name
    end
end

function shortICCellVariationName(name::String)
    if name == "ic_cell_variation_id"
        return shortLocationVariationID(String, "ic_cell")
    elseif startswith(name, "cell_patches")
        return getICCellParameterName(name)
    else
        return name
    end
end

function shortICECMVariationName(name::String)
    if name == "ic_ecm_variation_id"
        return shortLocationVariationID(String, "ic_ecm")
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