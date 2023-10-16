module VCTConfiguration
using LightXML, CSV, DataFrames, SQLite

global xml_doc::XMLDocument;

function openXML(path_to_xml::String)
    VCTConfiguration.xml_doc = parse_file(path_to_xml)
    return nothing
end

closeXML() = free(VCTConfiguration.xml_doc)

function retrieveElement(xml_path::Vector{String})
    current_element = root(VCTConfiguration.xml_doc)
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
    openXML(path_to_xml)
    return retrieveElement(xml_path)
end

function getField(xml_path::Vector{String})
    return retrieveElement(xml_path) |> content
end

function getOutputFolder(path_to_xml)
    VCTConfiguration.openXML(path_to_xml)
    rel_path_to_output = getField(["save", "folder"])
    VCTConfiguration.closeXML()
    return rel_path_to_output
end

function updateField(xml_path::Vector{String},new_value::Union{Int,Real,String})
    current_element = retrieveElement(xml_path)
    set_content(current_element, string(new_value))
    return nothing
end

function updateField(xml_path_and_value::Vector{Any})
    return updateField(xml_path_and_value[1:end-1],xml_path_and_value[end])
end

function updateField(path_to_xml::String,xml_path::Vector{String},new_value::Union{Int,Real,String})
    openXML(path_to_xml)
    return updateField(xml_path,new_value)
end

function updateField(xml_doc_temp::XMLDocument,xml_path::Vector{String},new_value::Union{Int,Real,String})
    current_element = root(xml_doc_temp)
    retrieveElement!(current_element,xml_path)
    set_content(current_element, new_value)
    return nothing
end

function multiplyField(xml_path::Vector{String}, multiplier::AbstractFloat)
    current_element = retrieveElement(xml_path)
    val = content(current_element)
    if attribute(current_element, "type"; required=false) == "int"
        val = parse(Int, val) |> y -> round(Int, multiplier * y)
    else
        val = parse(AbstractFloat, val) |> y -> multiplier * y
    end

    val |> string |> x -> set_content(current_element, x)
    return nothing
end

function updateFieldsFromCSV(path_to_csv::String)
    df = CSV.read(path_to_csv,DataFrame;header=false,silencewarnings=true,types=String)
    for i = axes(df,1)
        df[i,:] |> Vector |> x->filter!(!ismissing,x) .|> string |> updateField
    end
end

function updateFieldsFromCSV(path_to_csv::String,path_to_xml::String)
    openXML(path_to_xml)
    updateFieldsFromCSV(path_to_csv)
end

function loadVariation(path_to_xml::String, variation_row::DataFrame, physicell_dir::String)
    openXML(path_to_xml)
    for column_name in names(variation_row)
        if column_name == "variation_id"
            continue
        end
        xml_path = split(column_name,"/") .|> string
        updateField(xml_path,variation_row[1,column_name])
    end
    save_file(VCTConfiguration.xml_doc, path_to_xml)
    save_file(VCTConfiguration.xml_doc, physicell_dir * "/config/PhysiCell_settings.xml")
    closeXML()
    return nothing
end

end