using LightXML, CSV, DataFrames, LinearAlgebra

export createICCellXMLTemplate

function generateICCell(path_to_ic_cell_xml::String, path_to_ic_cell_file::String)
    xml_doc = openXML(path_to_ic_cell_xml)
    ic_cells = root(xml_doc)
    open(path_to_ic_cell_file, "w") do io
        println(io, "x,y,z,type")
    end
    for cell_patches in child_elements(ic_cells)
        generateCellPatches(cell_patches, path_to_ic_cell_file)
    end
    closeXML(xml_doc)
end

function generateCellPatches(cell_patches::XMLElement, path_to_ic_cell_file::String)
    cell_type = attribute(cell_patches, "name")
    for patch_collection in child_elements(cell_patches)
        generatePatchCollection(patch_collection, cell_type, path_to_ic_cell_file)
    end
end

function generatePatchCollection(patch_collection::XMLElement, cell_type::String, path_to_ic_cell_file::String)
    patch_type = attribute(patch_collection, "type")
    for patch in child_elements(patch_collection)
        generatePatch(patchType(patch_type), patch, cell_type, path_to_ic_cell_file)
    end
end

struct DiscPatch end
struct AnnulusPatch end

function patchType(patch_type::String)
    if patch_type == "disc"
        return DiscPatch
    elseif patch_type == "annulus"
        return AnnulusPatch
    else
        throw(ArgumentError("Patch type $(patch_type) is not supported."))
    end
end

function parse_center(patch::XMLElement)
    x0 = parse(Float64, find_element(patch, "x0") |> content)
    y0 = parse(Float64, find_element(patch, "y0") |> content)
    z0 = parse(Float64, find_element(patch, "z0") |> content)
    return x0, y0, z0
end

function parse_normal(patch::XMLElement, cell_type::String)
    normal = find_element(patch, "normal")
    if isnothing(normal)
        return [0.0, 0.0, 1.0]
    else
        normal_vector = content(normal) |> x -> split(x, ",") |> x -> parse.(Float64, x)
        magnitude = sqrt(sum(normal_vector.^2))
        if magnitude == 0
            throw(ArgumentError("Normal vector provided for $(cell_type) disc[$(attribute(patch, "ID"))] is 0. It must be non-zero."))
        end
        return normal_vector ./ magnitude
    end
end

function place_annulus(radius_fn, patch, cell_type, path_to_ic_cell_file)
    x0, y0, z0 = parse_center(patch)
    number = parse(Int, find_element(patch, "number") |> content)
    normal_vector = parse_normal(patch, cell_type)
    r = radius_fn(number)
    θ = 2π * rand(number)
    # start in the (x,y) plane at the origin
    c1 = r .* cos.(θ) 
    c2 = r .* sin.(θ)
    
    if normal_vector[1] != 0 || normal_vector[2] != 0
        u₁ = [normal_vector[2], -normal_vector[1], 0] / sqrt(normal_vector[1]^2 + normal_vector[2]^2) # first basis vector in the plane of the disc
        u₂ = cross(normal_vector, u₁) # second basis vector in the plane of the disc
        df = DataFrame(x=c1*u₁[1] + c2*u₂[1], y=c1*u₁[2] + c2*u₂[2], z=c1*u₁[3] + c2*u₂[3])
    else
        df = DataFrame(x=c1, y=c2, z=zeros(Float64, number))
    end
    df.x .+= x0
    df.y .+= y0
    df.z .+= z0
    df[!, :cell_type] .= cell_type
    CSV.write(path_to_ic_cell_file, df, append=true, header=false)
end

function generatePatch(::Type{DiscPatch}, patch::XMLElement, cell_type::String, path_to_ic_cell_file::String)
    radius = parse(Float64, find_element(patch, "radius") |> content)
    r_fn(number) = radius * sqrt.(rand(number))
    place_annulus(r_fn, patch, cell_type, path_to_ic_cell_file)
end

function generatePatch(::Type{AnnulusPatch}, patch::XMLElement, cell_type::String, path_to_ic_cell_file::String)
    inner_radius = parse(Float64, find_element(patch, "inner_radius") |> content)
    outer_radius = parse(Float64, find_element(patch, "outer_radius") |> content)
    if inner_radius > outer_radius
        throw(ArgumentError("Inner radius of annulus is greater than outer radius."))
    end
    r_fn(number) = sqrt.(inner_radius^2 .+ (outer_radius^2 - inner_radius^2) * rand(number))
    place_annulus(r_fn, patch, cell_type, path_to_ic_cell_file)
end

"""
    createICCellXMLTemplate(folder::String)

Create folder `data/inputs/ics/cells/folder` and create a template XML file for IC cells.

pcvct introduces a new way to initialize cells in a simulation, wholly contained within pcvct.
It will not work in PhysiCell!
This function creates a template XML file for IC cells, showing all the current functionality of this initialization scheme.
It uses the cell type \"default\".
Create ICs for more cell types by copying the `cell_patches` element.
The `ID` attribute in `patch` elements is there exactly to allow variations to target specific patches.
Manually maintain these or you will not be able to vary specific patches effectively.

Each time a simulation is run that is using a cells.xml file, a new CSV file will be created, drawing randomly from the patches defined in the XML file.
These will all be stored with `data/inputs/ics/cells/folder/ic_cell_variations` as `ic_cell_variation_#_s#.csv` where the first `#` is the variation ID associated with variation on the XML file and the second `#` is the simulation ID.
Importantly, no two simulations will use the same CSV file.
"""
function createICCellXMLTemplate(folder::String)
    if length(splitpath(folder)) == 1
        # then the folder is just the name of the ics/cells/folder folder
        folder = joinpath(data_dir, "inputs", "ics", "cells", folder)
    end
    path_to_ic_cell_xml = joinpath(folder, "cells.xml")
    mkpath(dirname(path_to_ic_cell_xml))
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
    save_file(xml_doc, path_to_ic_cell_xml)
    closeXML(xml_doc)
end