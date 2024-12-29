using LightXML
filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

project_dir = "./test-project"
pcvct.createProject(project_dir)

path_to_data_folder = joinpath(".", "test-project", "data")

mkdir(joinpath(path_to_data_folder, "inputs", "ics", "cells", "1_xml"))
xml_doc = XMLDocument()
xml_root = create_root(xml_doc, "ic_cells")

e_patches = new_child(xml_root, "cell_patches")
set_attribute(e_patches, "name", "default")

e_discs = new_child(e_patches, "patch_collection")
set_attribute(e_discs, "type", "disc")
e_patch = new_child(e_discs, "patch")
set_attribute(e_patch, "ID", "1")
for (name, value) in [("x0", "0.0"), ("y0", "0.0"), ("z0", "0.0"), ("radius", "10.0"), ("number", "50")]
    e = new_child(e_patch, name)
    set_content(e, value)
end

e_annuli = new_child(e_patches, "patch_collection")
set_attribute(e_annuli, "type", "annulus")
e_patch = new_child(e_annuli, "patch")
set_attribute(e_patch, "ID", "1")
for (name, value) in [("x0", "50.0"), ("y0", "50.0"), ("z0", "0.0"), ("inner_radius", "10.0"), ("outer_radius", "200.0"), ("number", "50")]
    e = new_child(e_patch, name)
    set_content(e, value)
end

save_file(xml_doc, joinpath(path_to_data_folder, "inputs", "ics", "cells", "1_xml", "cells.xml"))