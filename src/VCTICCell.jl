using LightXML, CSV, DataFrames, LinearAlgebra

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

function patchType(patch_type::String)
    if patch_type == "disc"
        return DiscPatch
    end
end


function generatePatch(::DiscPatch, patch::XMLElement, cell_type::String, path_to_ic_cell_file::String)
    x0 = parse(Float64, find_element(patch, "x0") |> content)
    y0 = parse(Float64, find_element(patch, "y0") |> content)
    z0 = parse(Float64, find_element(patch, "z0") |> content)
    radius = parse(Float64, find_element(patch, "radius") |> content)
    number = parse(Int, find_element(patch, "number") |> content)
    normal = find_element(patch, "normal")
    if isnothing(normal)
        normal_vector = [0.0, 0.0, 1.0]
    else
        normal_vector = content(normal) |> x -> split(x, ",") |> x -> parse.(Float64, x)
        magnitude = sqrt(sum(normal_vector.^2))
        if magnitude == 0
            throw(ArgumentError("Normal vector provided for $(cell_type) disc[$(attribute(patch, "ID"))] is 0. It must be non-zero."))
        end
        normal_vector = normal_vector ./ magnitude
    end
    r = radius * sqrt.(rand(number))
    θ = 2π * rand(number)
    # start in the (x,y) plane at the origin
    c1 = r .* cos.(θ) 
    c2 = r .* sin.(θ)

    if normal_vector[1] != 0 || normal_vector[2] != 0
        u₁ = [normal_vector[2], -normal_vector[1], 0] / sqrt(normal_vector[1]^2 + normal_vector[2]^2) # first basis vector in the plane of the disc
        u₂ = cross(normal_vector, u₁) # second basis vector in the plane of the disc
        df = DataFrame(x=c1*u₁[1] + c2*u₂[1], y=c1*u₁[2] + c2*u₂[2], z=c1*u₁[3] + c2*u₂[3])
    else
        df = DataFrame(x=c1, y=c2, z=z₀)
    end
    df.x .+= x0
    df.y .+= y0
    df.z .+= z0
    df[!, :cell_type] .= cell_type
    CSV.write(path_to_ic_cell_file, df, append=true, header=false)
end