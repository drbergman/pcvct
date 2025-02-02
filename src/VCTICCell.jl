using LightXML, CSV, DataFrames, LinearAlgebra

export createICCellXMLTemplate

function generateICCell(path_to_ic_cell_xml::String, path_to_ic_cell_file::String, domain_dict::Dict{String,Float64})
    xml_doc = openXML(path_to_ic_cell_xml)
    ic_cells = root(xml_doc)
    open(path_to_ic_cell_file, "w") do io
        println(io, "x,y,z,type")
    end
    for cell_patches in child_elements(ic_cells)
        generateCellPatches(cell_patches, path_to_ic_cell_file, domain_dict)
    end
    closeXML(xml_doc)
end

function generateCellPatches(cell_patches::XMLElement, path_to_ic_cell_file::String, domain_dict::Dict{String,Float64})
    cell_type = attribute(cell_patches, "name")
    for patch_collection in child_elements(cell_patches)
        generatePatchCollection(patch_collection, cell_type, path_to_ic_cell_file, domain_dict)
    end
end

function generatePatchCollection(patch_collection::XMLElement, cell_type::String, path_to_ic_cell_file::String, domain_dict::Dict{String,Float64})
    patch_type = attribute(patch_collection, "type")
    for patch in child_elements(patch_collection)
        generatePatch(patchType(patch_type), patch, cell_type, path_to_ic_cell_file, domain_dict)
    end
end

struct DiscPatch end
struct AnnulusPatch end
struct RectanglePatch end
struct EverywherePatch end

function patchType(patch_type::String)
    if patch_type == "disc"
        return DiscPatch
    elseif patch_type == "annulus"
        return AnnulusPatch
    elseif patch_type == "rectangle"
        return RectanglePatch
    elseif patch_type == "everywhere"
        return EverywherePatch
    else
        throw(ArgumentError("Patch type $(patch_type) is not supported."))
    end
end

function parseCenter(patch::XMLElement)
    x0 = parse(Float64, find_element(patch, "x0") |> content)
    y0 = parse(Float64, find_element(patch, "y0") |> content)
    z0 = parse(Float64, find_element(patch, "z0") |> content)
    return x0, y0, z0
end

function parseNormal(patch::XMLElement, cell_type::String)
    normal = find_element(patch, "normal")
    if isnothing(normal)
        return [0.0, 0.0, 1.0]
    else
        normal_vector = content(normal) |> x -> split(x, ",") |> x -> parse.(Float64, x)
        magnitude = sqrt(sum(normal_vector.^2))
        if magnitude == 0
            throw(ArgumentError("A normal vector provided for $(cell_type) with patch ID $(attribute(patch, "ID")) is 0. It must be non-zero."))
        end
        return normal_vector ./ magnitude
    end
end

function parseRestrictToDomain(patch::XMLElement, cell_type::String)
    restrict_to_domain = find_element(patch, "restrict_to_domain")
    if isnothing(restrict_to_domain)
        return true
    end
    restrict_string = content(restrict_to_domain)
    if restrict_string in ["0", "1", "true", "false"]
        return parse(Bool, restrict_string)
    else
        throw(ArgumentError("restrict_to_domain for $(cell_type) with patch ID $(attribute(patch, "ID")) must be a boolean."))
    end
end

function parseMaxFails(patch::XMLElement)
    max_fails = find_element(patch, "max_fails")
    if isnothing(max_fails)
        return 100
    end
    mf = parse(Int, content(max_fails))
    @assert mf >= 0 "Max fails must be >= 0."
    return parse(Int, content(max_fails))
end

function parseRectangleParameters(patch::XMLElement)
    x0, y0, z0 = parseCenter(patch)
    width = parseRectangleSize(patch, x0, "width", "x1")
    height = parseRectangleSize(patch, y0, "height", "y1")
    return x0, y0, z0, width, height
end

function parseRectangleSize(patch::XMLElement, c0::Float64, size_name::String, c1_name::String)
    size_element = find_element(patch, size_name)
    if !isnothing(size_element)
        return parse(Float64, content(size_element))
    end
    c1 = find_element(patch, c1_name)
    if isnothing(c1)
        throw(ArgumentError("Rectangle patch must have either a $(size_name) or $(c1_name) element."))
    end
    return parse(Float64, content(c1)) - c0
end

abstract type PatchCarveout end

struct DiscCarveout <: PatchCarveout
    x0::Float64
    y0::Float64
    z0::Float64
    radius::Float64
end

struct AnnulusCarveout <: PatchCarveout
    x0::Float64
    y0::Float64
    z0::Float64
    inner_radius::Float64
    outer_radius::Float64
end

struct RectangleCarveout <: PatchCarveout
    x0::Float64
    y0::Float64
    z0::Float64
    width::Float64
    height::Float64
end

function parseCarveouts(patch::XMLElement)
    carveout_patches = find_element(patch, "carveout_patches")
    if isnothing(carveout_patches)
        return PatchCarveout[]
    end
    carveouts = PatchCarveout[]
    for patch_collection in child_elements(carveout_patches)
        append!(carveouts, parseCarveoutPatchCollection(patch_collection))
    end
    return carveouts
end

function parseCarveoutPatchCollection(patch_collection::XMLElement)
    patch_type = attribute(patch_collection, "type")
    carveouts = PatchCarveout[]
    for patch in child_elements(patch_collection)
        if patch_type == "disc"
            x0, y0, z0 = parseCenter(patch)
            radius = parse(Float64, find_element(patch, "radius") |> content)
            push!(carveouts, DiscCarveout(x0, y0, z0, radius))
        elseif patch_type == "annulus"
            x0, y0, z0 = parseCenter(patch)
            inner_radius = parse(Float64, find_element(patch, "inner_radius") |> content)
            outer_radius = parse(Float64, find_element(patch, "outer_radius") |> content)
            push!(carveouts, AnnulusCarveout(x0, y0, z0, inner_radius, outer_radius))
        elseif patch_type == "rectangle"
            x0, y0, z0, width, height = parseRectangleParameters(patch)
            push!(carveouts, RectangleCarveout(x0, y0, z0, width, height))
        else
            throw(ArgumentError("Patch type $(patch_type) is not supported."))
        end
    end
    return carveouts
end

function carveOut(df::DataFrame, carveout::DiscCarveout)
        keep_ind = sqrt.((df.x .- carveout.x0).^2 + (df.y .- carveout.y0).^2 + (df.z .- carveout.z0).^2) .> carveout.radius
        return df[keep_ind, :]
end

function carveOut(df::DataFrame, carveout::AnnulusCarveout)
    keep_ind = sqrt.((df.x .- carveout.x0).^2 + (df.y .- carveout.y0).^2 + (df.z .- carveout.z0).^2) .> carveout.outer_radius .||
               sqrt.((df.x .- carveout.x0).^2 + (df.y .- carveout.y0).^2 + (df.z .- carveout.z0).^2) .< carveout.inner_radius
    return df[keep_ind, :]
end

function carveOut(df::DataFrame, carveout::RectangleCarveout)
    keep_ind = (df.x .< carveout.x0) .|| (df.x .> carveout.x0 + carveout.width) .||
               (df.y .< carveout.y0) .|| (df.y .> carveout.y0 + carveout.height)
    return df[keep_ind, :]
end

function createCellsDataFrame(number::Int, cell_coords_fn::Function, restrict_to_domain::Bool, domain_dict::Dict{String,Float64}, carveouts::Vector{PatchCarveout}, max_fails::Int)
    total_placed = 0
    df = DataFrame(x=Float64[], y=Float64[], z=Float64[])
    fails_remaining = max_fails
    while total_placed < number
        df_new = cell_coords_fn(number - total_placed)
        if restrict_to_domain
            keep_ind = df_new.x .>= domain_dict["x_min"] .&& df_new.x .<= domain_dict["x_max"] .&&
                       df_new.y .>= domain_dict["y_min"] .&& df_new.y .<= domain_dict["y_max"] .&&
                       df_new.z .>= domain_dict["z_min"] .&& df_new.z .<= domain_dict["z_max"]
            df_new = df_new[keep_ind, :]
        end
        for carveout in carveouts
            df_new = carveOut(df_new, carveout)
        end
        append!(df, df_new)
        total_placed += size(df_new, 1)
        if size(df_new, 1) == 0
            if fails_remaining == 0
                throw(ArgumentError("Failed to place a single cell after $(max_fails) consecutive attempts."))
            end
            fails_remaining -= 1
        else
            fails_remaining = max_fails
        end
    end
    return df
end

function placeAnnulus(radius_fn::Function, patch::XMLElement, cell_type::String, path_to_ic_cell_file::String, domain_dict::Dict{String,Float64})
    x0, y0, z0 = parseCenter(patch)
    number = parse(Int, find_element(patch, "number") |> content)
    normal_vector = parseNormal(patch, cell_type)
    restrict_to_domain = parseRestrictToDomain(patch, cell_type)
    max_fails = parseMaxFails(patch)

    cell_coords_fn(n::Int) = begin
        r = radius_fn(n)
        θ = 2π * rand(n)
    
        # start in the (x,y) plane at the origin
        c1 = r .* cos.(θ) 
        c2 = r .* sin.(θ)
        if normal_vector[1] != 0 || normal_vector[2] != 0
            u₁ = [normal_vector[2], -normal_vector[1], 0] / sqrt(normal_vector[1]^2 + normal_vector[2]^2) # first basis vector in the plane of the disc
            u₂ = cross(normal_vector, u₁) # second basis vector in the plane of the disc
            df = DataFrame(x=c1 * u₁[1] + c2 * u₂[1], y=c1 * u₁[2] + c2 * u₂[2], z=c1 * u₁[3] + c2 * u₂[3])
        else
            df = DataFrame(x=c1, y=c2, z=fill(z0, n))
        end
        df.x .+= x0
        df.y .+= y0
        df.z .+= z0
        return df
    end

    carveouts = parseCarveouts(patch)
    
    df = createCellsDataFrame(number, cell_coords_fn, restrict_to_domain, domain_dict, carveouts, max_fails)
    df[!, :cell_type] .= cell_type
    CSV.write(path_to_ic_cell_file, df, append=true, header=false)
end

function generatePatch(::Type{DiscPatch}, patch::XMLElement, cell_type::String, path_to_ic_cell_file::String, domain_dict::Dict{String,Float64})
    radius = parse(Float64, find_element(patch, "radius") |> content)
    r_fn(number) = radius * sqrt.(rand(number))
    placeAnnulus(r_fn, patch, cell_type, path_to_ic_cell_file, domain_dict)
end

function generatePatch(::Type{AnnulusPatch}, patch::XMLElement, cell_type::String, path_to_ic_cell_file::String, domain_dict::Dict{String,Float64})
    inner_radius = parse(Float64, find_element(patch, "inner_radius") |> content)
    outer_radius = parse(Float64, find_element(patch, "outer_radius") |> content)
    if inner_radius > outer_radius
        throw(ArgumentError("Inner radius of annulus is greater than outer radius."))
    end
    r_fn(number) = sqrt.(inner_radius^2 .+ (outer_radius^2 - inner_radius^2) * rand(number))
    placeAnnulus(r_fn, patch, cell_type, path_to_ic_cell_file, domain_dict)
end

function generatePatch(::Type{RectanglePatch}, patch::XMLElement, cell_type::String, path_to_ic_cell_file::String, domain_dict::Dict{String,Float64})
    x0, y0, z0, width, height = parseRectangleParameters(patch)
    number = parse(Int, find_element(patch, "number") |> content)
    restrict_to_domain = parseRestrictToDomain(patch, cell_type)
    max_fails = parseMaxFails(patch)

    # start in the (x,y) plane at the origin
    cell_coords_fn(n::Int) = begin
        x = x0 .+ width * rand(n)
        y = y0 .+ height * rand(n)
        return DataFrame(x=x, y=y, z=fill(z0, n))
    end

    carveouts = parseCarveouts(patch)

    df = createCellsDataFrame(number, cell_coords_fn, restrict_to_domain, domain_dict, carveouts, max_fails)
    df[!, :cell_type] .= cell_type
    CSV.write(path_to_ic_cell_file, df, append=true, header=false)
end

function generatePatch(::Type{EverywherePatch}, patch::XMLElement, cell_type::String, path_to_ic_cell_file::String, domain_dict::Dict{String,Float64})
    number = parse(Int, find_element(patch, "number") |> content)
    restrict_to_domain = false
    max_fails = parseMaxFails(patch)

    # start in the (x,y) plane at the origin
    cell_coords_fn(n::Int) = begin
        x = rand(n) .* (domain_dict["x_max"] - domain_dict["x_min"]) .+ domain_dict["x_min"]
        y = rand(n) .* (domain_dict["y_max"] - domain_dict["y_min"]) .+ domain_dict["y_min"]
        return DataFrame(x=x, y=y, z=fill(0.0, n))
    end

    carveouts = parseCarveouts(patch)

    df = createCellsDataFrame(number, cell_coords_fn, restrict_to_domain, domain_dict, carveouts, max_fails)
    df[!, :cell_type] .= cell_type
    CSV.write(path_to_ic_cell_file, df, append=true, header=false)
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

    # make disc patch
    e_discs = new_child(e_patches, "patch_collection")
    set_attribute(e_discs, "type", "disc")
    e_patch = new_child(e_discs, "patch")
    set_attribute(e_patch, "ID", "1")
    for (name, value) in [("x0", "0.0"), ("y0", "0.0"), ("z0", "0.0"), ("radius", "40.0"), ("number", "50"), ("normal", "0,0,1"), ("max_fails", "100")]
        e = new_child(e_patch, name)
        set_content(e, value)
    end

    ## make rectangle carveouts for the disc
    e_carveout_patches = new_child(e_patch, "carveout_patches")
    e_rectangle_carveouts = new_child(e_carveout_patches, "patch_collection")
    set_attribute(e_rectangle_carveouts, "type", "rectangle")
    e_carveout_patch = new_child(e_rectangle_carveouts, "patch")
    set_attribute(e_carveout_patch, "ID", "1")
    for (name, value) in [("x0", "0.0"), ("y0", "0.0"), ("z0", "0.0"), ("width", "10.0"), ("height", "10.0")]
        e = new_child(e_carveout_patch, name)
        set_content(e, value)
    end

    # make annulus patch
    e_annuli = new_child(e_patches, "patch_collection")
    set_attribute(e_annuli, "type", "annulus")
    e_patch = new_child(e_annuli, "patch")
    set_attribute(e_patch, "ID", "1")
    for (name, value) in [("x0", "50.0"), ("y0", "50.0"), ("z0", "0.0"), ("inner_radius", "10.0"), ("outer_radius", "200.0"), ("number", "50"), ("restrict_to_domain", "true")]
        e = new_child(e_patch, name)
        set_content(e, value)
    end

    # make rectangle patch
    e_rectangles = new_child(e_patches, "patch_collection")
    set_attribute(e_rectangles, "type", "rectangle")
    e_patch = new_child(e_rectangles, "patch")
    set_attribute(e_patch, "ID", "1")
    for (name, value) in [("x0", "-50.0"), ("y0", "-50.0"), ("z0", "0.0"), ("x1", "50.0"), ("y1", "50.0"), ("number", "10")]
        e = new_child(e_patch, name)
        set_content(e, value)
    end

    ## make disc carveouts for the rectangle
    e_carveout_patches = new_child(e_patch, "carveout_patches")
    e_disc_carveouts = new_child(e_carveout_patches, "patch_collection")
    set_attribute(e_disc_carveouts, "type", "disc")
    e_carveout_patch = new_child(e_disc_carveouts, "patch")
    set_attribute(e_carveout_patch, "ID", "1")
    for (name, value) in [("x0", "0.0"), ("y0", "0.0"), ("z0", "0.0"), ("radius", "10.0")]
        e = new_child(e_carveout_patch, name)
        set_content(e, value)
    end

    # make everywhere patch
    e_everywhere = new_child(e_patches, "patch_collection")
    set_attribute(e_everywhere, "type", "everywhere")
    e_patch = new_child(e_everywhere, "patch")
    set_attribute(e_patch, "ID", "1")
    e = new_child(e_patch, "number")
    set_content(e, "78")

    ## make annulus carveouts for the everywhere patch
    e_carveout_patches = new_child(e_patch, "carveout_patches")
    e_annuli_carveouts = new_child(e_carveout_patches, "patch_collection")
    set_attribute(e_annuli_carveouts, "type", "annulus")
    e_carveout_patch = new_child(e_annuli_carveouts, "patch")
    set_attribute(e_carveout_patch, "ID", "1")
    for (name, value) in [("x0", "0.0"), ("y0", "0.0"), ("z0", "0.0"), ("inner_radius", "100.0"), ("outer_radius", "400.0")]
        e = new_child(e_carveout_patch, name)
        set_content(e, value)
    end
    
    save_file(xml_doc, path_to_ic_cell_xml)
    closeXML(xml_doc)
    reinitializeDatabase()
end