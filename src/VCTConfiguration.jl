# global xml_doc::XMLDocument;
# current_variation_id = 0

function getConfigDB(base_config_id::Int)
    folder_name = DBInterface.execute(db, "SELECT folder_name FROM base_configs WHERE (base_config_id)=($(base_config_id));") |> DataFrame |> x->x.folder_name[1]
    return "$(data_dir)/base_configs/$(folder_name)/variations.db" |> SQLite.DB
end

function openXML(path_to_xml::String)
    # global xml_doc = parse_file(path_to_xml)
    # return nothing
    return parse_file(path_to_xml)
end

closeXML(xml_doc::XMLDocument) = free(xml_doc)

function retrieveElement(xml_doc::XMLDocument, xml_path::Vector{String})
    current_element = root(xml_doc)
    for path_element in xml_path
        if !occursin(":",path_element)
            current_element = find_element(current_element, path_element)
            continue
        end
        # Deal with checking attributes
        path_element_name, attribute_check = split(path_element,":",limit=2)
        attribute_name, attribute_value = split(attribute_check,":") # if I need to add a check for multiple attributes, we can do that later
        candidate_elements = get_elements_by_tagname(current_element, path_element_name)
        for ce in candidate_elements
            if attribute(ce,attribute_name)==attribute_value
                current_element = ce
                break
            end
        end
    end
    return current_element
end

function retrieveElement(path_to_xml::String,xml_path::Vector{String})
    # openXML(path_to_xml)
    # return retrieveElement(xml_path)
    
    return openXML(path_to_xml) |> x->retrieveElement(x, xml_path)
end

function getField(xml_doc::XMLDocument, xml_path::Vector{String})
    return retrieveElement(xml_doc, xml_path) |> content
end

function getOutputFolder(path_to_xml)
    xml_doc = openXML(path_to_xml)
    rel_path_to_output = getField(xml_doc, ["save", "folder"])
    closeXML(xml_doc)
    return rel_path_to_output
end

function updateField(xml_doc::XMLDocument, xml_path::Vector{String},new_value::Union{Int,Real,String})
    current_element = retrieveElement(xml_doc, xml_path)
    set_content(current_element, string(new_value))
    return nothing
end

function updateField(xml_doc::XMLDocument, xml_path_and_value::Vector{Any})
    return updateField(xml_doc, xml_path_and_value[1:end-1],xml_path_and_value[end])
end

function updateField(path_to_xml::String,xml_path::Vector{String},new_value::Union{Int,Real,String})
    return openXML(path_to_xml) |> x -> updateField(x, xml_path, new_value)
end

# function updateField(xml_doc::XMLDocument,xml_path::Vector{String},new_value::Union{Int,Real,String})
#     current_element = root(xml_doc)
#     retrieveElement!(current_element, xml_path)
#     set_content(current_element, new_value)
#     return nothing
# end

function multiplyField(xml_doc::XMLDocument, xml_path::Vector{String}, multiplier::AbstractFloat)
    current_element = retrieveElement(xml_doc, xml_path)
    val = content(current_element)
    if attribute(current_element, "type"; required=false) == "int"
        val = parse(Int, val) |> y -> round(Int, multiplier * y)
    else
        val = parse(AbstractFloat, val) |> y -> multiplier * y
    end

    val |> string |> x -> set_content(current_element, x)
    return nothing
end

function updateFieldsFromCSV(xml_doc::XMLDocument, path_to_csv::String)
    df = CSV.read(path_to_csv,DataFrame;header=false,silencewarnings=true,types=String)
    for i = axes(df,1)
        df[i, :] |> Vector |> x -> filter!(!ismissing, x) .|> string |> x -> updateField(xml_doc, x)
    end
end

function updateFieldsFromCSV(path_to_csv::String,path_to_xml::String)
    return openXML(path_to_xml) |> x->updateFieldsFromCSV(x, path_to_csv)
end

function loadConfiguration(path_to_xml::String, variation_row::DataFrame, physicell_dir::String)
    xml_doc = openXML(path_to_xml)
    for column_name in names(variation_row)
        if column_name == "variation_id"
            continue
        end
        xml_path = split(column_name,"/") .|> string
        updateField(xml_doc, xml_path, variation_row[1, column_name])
    end
    # save_file(xml_doc, path_to_xml)
    save_file(xml_doc, physicell_dir * "/config/PhysiCell_settings.xml")
    closeXML(xml_doc)
    return nothing
end

function loadConfiguration!(simulation::Union{Simulation,Monad})
    path_to_xml = "$(physicell_dir)/config/base_config_$(simulation.base_config_id)/variation_$(simulation.variation_id).xml"
    if isfile(path_to_xml)
        return
    end
    mkpath(path_to_xml)
    if isempty(simulation.base_config_folder)
        simulation.base_config_folder = selectRow("folder_name", "base_configs", "WHERE base_config_id=$(simulation.base_config_id);")
    end
    path_to_xml_src = "$(data_dir)/base_configs/$(simulation.base_config_folder)/PhysiCell_settings.xml"
    cp(path_to_xml_src, path_to_xml, force=true)

    xml_doc = openXML(path_to_xml)
    variation_row = selectRow("variations", "WHERE variation_id=$(simulation.variation_id);", db=getConfigDB(simulation.base_config_id))
    for column_name in names(variation_row)
        if column_name == "variation_id"
            continue
        end
        xml_path = split(column_name,"/") .|> string
        updateField(xml_doc, xml_path,variation_row[1,column_name])
    end
    save_file(xml_doc, path_to_xml)
    closeXML(xml_doc)
    return
end

function motilityPath(cell_definition::String, field_name::String)
    return ["cell_definitions", "cell_definition:name:$(cell_definition)", "phenotype", "motility", field_name]
end

function addMotilityVariationDimension!(D::Vector{Vector{Vector}}, cell_definition::String, field_name::String, values::Vector{T} where T)
    xml_path = motilityPath(cell_definition, field_name)
    new_var = [xml_path, values]
    push!(D, new_var)
end

function customDataPath(cell_definition::String, field_name::String)
    return ["cell_definitions", "cell_definition:name:$(cell_definition)", "custom_data", field_name]
end

function customDataPath(cell_definition::String, field_names::Vector{String})
    return [customDataPath(cell_definition, field_name) for field_name in field_names]
end

function addCustomDataVariationDimension!(D::Vector{Vector{Vector}}, cell_definition::String, field_name::String, values::Vector{T} where T)
    xml_path = customDataPath(cell_definition, field_name)
    new_var = [xml_path, values]
    push!(D, new_var)
end

function addCustomDataVariationDimension!(D::Vector{Vector{Vector}}, cell_definition::String, field_names::Vector{String}, values::Vector{Vector})
    for x in zip(field_names,values)
        field_name, value = x
        addCustomDataVariationDimension!(D, cell_definition, field_name, value)
    end
end

function userParameterPath(field_name::String)
    return ["user_parameters", field_name]
end

function userParameterPath(field_names::Vector{String})
    return [userParameterPath(field_name) for field_name in field_names]
end

function initialConditionPath()
    return ["initial_conditions","cell_positions","filename"]
end
