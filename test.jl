using LightXML

xml_doc = parse_file("../PhysiCell/config/PhysiCell_settings.xml")
current_element = root(xml_doc)
current_element = find_element(current_element, "cell_definitions")
current_element = find_element(current_element, "user_parameters")
candidate_elements = get_elements_by_tagname(current_element, "cell_definition")
attribute_name = "ID"
attribute_value = "3"
for ce in candidate_elements
    if attribute(ce, attribute_name) == attribute_value
        current_element = ce
        break
    end
end
println(current_element)

"ADDON_PHYSIEC" in readlines("macros.txt")

macro_flags = ["cat","dog","pig"]
path_to_macros = "macros.txt"
open(path_to_macros, "w") do f
    for macro_flag in macro_flags
        println(f, macro_flag)
    end
end