using DataFrames, MAT

export getCellDataSequence

abstract type AbstractPhysiCellSequence end

"""
    PhysiCellSnapshot

A single snapshot of a PhysiCell simulation.

The `cells`, `substrates`, and `mesh` fields may remain empty until they are needed for analysis.

# Fields
- `folder::String`: The folder containing the PhysiCell simulation output.
- `index::Union{Int, Symbol}`: The index of the snapshot. Can be an integer or a symbol (`:initial` or `:final`).
- `time::Float64`: The time of the snapshot.
- `cells::DataFrame`: A DataFrame containing cell data.
- `substrates::DataFrame`: A DataFrame containing substrate data.
- `mesh::Dict{String, Vector{Float64}}`: A dictionary containing mesh data.
"""
struct PhysiCellSnapshot <: AbstractPhysiCellSequence
    folder::String
    index::Union{Int, Symbol}
    time::Float64
    cells::DataFrame
    substrates::DataFrame
    mesh::Dict{String, Vector{Float64}}
end

"""
    PhysiCellSequence

A sequence of PhysiCell snapshots.

# Fields
- `folder::String`: The folder containing the PhysiCell simulation output.
- `snapshots::Vector{PhysiCellSnapshot}`: A vector of PhysiCell snapshots.
- `cell_type_to_name_dict::Dict{Int, String}`: A dictionary mapping cell type IDs to cell type names.
- `substrate_names::Vector{String}`: A vector of substrate names.
"""
struct PhysiCellSequence <: AbstractPhysiCellSequence
    folder::String
    snapshots::Vector{PhysiCellSnapshot}
    cell_type_to_name_dict::Dict{Int, String}
    substrate_names::Vector{String}
end

function getLabels!(labels::Vector{String}, xml_doc::XMLDocument)
    if !isempty(labels)
        return
    end
    xml_path = ["cellular_information", "cell_populations", "cell_population", "custom", "simplified_data", "labels"]
    labels_element = retrieveElement(xml_doc, xml_path; required=true)

    for label in child_elements(labels_element)
        label_name = content(label)
        label_ind_width = attribute(label, "size"; required=true) |> x -> parse(Int, x)
        if label_ind_width > 1
            label_name = [label_name * "_$i" for i in 1:label_ind_width]
            append!(labels, label_name)
        else
            if label_name == "elapsed_time_in_phase" && label_name in labels
                label_name = "elapsed_time_in_phase_2" # hack to get around a MultiCellDS duplicate?
            end
            push!(labels, label_name)
        end
    end
end

function getLabels!(labels::Vector{String}, folder::String)
    if !isempty(labels)
        return
    end
    xml_doc = openXML(joinpath(folder, "initial.xml"))
    getLabels!(labels, xml_doc)
    closeXML(xml_doc)
end

function getLabels(folder::String)
    xml_doc = openXML(joinpath(folder, "initial.xml"))
    labels = String[]
    getLabels!(labels, xml_doc)
    closeXML(xml_doc)
    return labels
end

function getCellTypeToNameDict!(cell_type_to_name_dict::Dict{Int, String}, xml_doc::XMLDocument)
    if !isempty(cell_type_to_name_dict)
        return
    end
    xml_path = ["cellular_information", "cell_populations", "cell_population", "custom", "simplified_data", "cell_types"]
    cell_types_element = retrieveElement(xml_doc, xml_path; required=true)

    for cell_type_element in child_elements(cell_types_element)
        cell_type_id = attribute(cell_type_element, "ID"; required=true) |> x -> parse(Int, x)
        cell_type_name = content(cell_type_element)
        cell_type_to_name_dict[cell_type_id] = cell_type_name
    end
end

function getCellTypeToNameDict!(cell_type_to_name_dict::Dict{Int, String}, folder::String)
    if !isempty(cell_type_to_name_dict)
        return
    end
    xml_doc = openXML(joinpath(folder, "initial.xml"))
    getCellTypeToNameDict!(cell_type_to_name_dict, xml_doc)
    closeXML(xml_doc)
end

getCellTypeToNameDict!(cell_type_to_name_dict::Dict{Int, String}, snapshot::PhysiCellSnapshot) = getCellTypeToNameDict!(cell_type_to_name_dict, snapshot.folder)

function getSubstrateNames!(substrate_names::Vector{String}, xml_doc::XMLDocument)
    if !isempty(substrate_names)
        return
    end
    xml_path = ["microenvironment", "domain", "variables"]
    variables_element = retrieveElement(xml_doc, xml_path; required=true)
    substrate_dict = Dict{Int, String}()
    for element in child_elements(variables_element)
        if name(element) != "variable"
            continue
        end
        variable_id = attribute(element, "ID"; required=true) |> x -> parse(Int, x)
        substrate_name = attribute(element, "name"; required=true)
        substrate_dict[variable_id] = substrate_name
    end
    for i in (substrate_dict |> keys |> collect |> sort)
        push!(substrate_names, substrate_dict[i])
    end
end

function getSubstrateNames!(substrate_names::Vector{String}, filepath::String)
    if !isempty(substrate_names)
        return
    end
    xml_doc = openXML(filepath)
    getSubstrateNames!(substrate_names, xml_doc)
    closeXML(xml_doc)
end

function getSubstrateNames(xml_doc::XMLDocument)
    substrate_names = String[]
    getSubstrateNames!(substrate_names, xml_doc)
    return substrate_names
end

function getSubstrateNames(folder::String)
    filepath = joinpath(folder, "initial.xml")
    xml_doc = openXML(filepath)
    substrate_names = getSubstrateNames(xml_doc)
    closeXML(xml_doc)
    return substrate_names
end

getSubstrateNames(aps::AbstractPhysiCellSequence) = getSubstrateNames(aps.folder)

function indexToFilename(index::Symbol)
    @assert index in [:initial, :final] "The non-integer index must be either :initial or :final"
    return string(index)
end

indexToFilename(index::Int) = "output$(lpad(index,8,"0"))"

function PhysiCellSnapshot(folder::String, index::Union{Int, Symbol}; include_cells::Bool=false, cell_type_to_name_dict::Dict{Int, String}=Dict{Int, String}(), labels::Vector{String}=String[], include_substrates::Bool=false, substrate_names::Vector{String}=String[], include_mesh::Bool=false)
    filepath_base = joinpath(folder, indexToFilename(index))
    xml_doc = openXML("$(filepath_base).xml")
    time = getField(xml_doc, ["metadata","current_time"]) |> x->parse(Float64, x)
    cells = DataFrame()
    if include_cells
        loadCells!(cells, filepath_base, cell_type_to_name_dict, labels)
    end
    substrates = DataFrame()
    if include_substrates
        loadSubstrates!(substrates, filepath_base, substrate_names)
    end
    mesh = Dict{String, Vector{Float64}}()
    if include_mesh
        loadMesh!(mesh, xml_doc)
    end
    closeXML(xml_doc)
    return PhysiCellSnapshot(folder, index, time, DataFrame(cells), substrates, mesh)
end

PhysiCellSnapshot(simulation_id::Integer, index::Union{Int, Symbol}; kwargs...) = PhysiCellSnapshot(joinpath(outputFolder("simulation", simulation_id), "output"), index; kwargs...)

function loadCells!(cells::DataFrame, filepath_base::String, cell_type_to_name_dict::Dict{Int, String}=Dict{Int, String}(), labels::Vector{String}=String[])
    if !isempty(cells)
        return
    end
    xml_doc = openXML("$(filepath_base).xml")
    mat_file = "$(filepath_base)_cells.mat"
    getLabels!(labels, xml_doc)
    A = matread(mat_file)["cell"]
    convert_to = Dict(:ID => Int, :dead => Bool, :cell_type => Int)
    for (label, row) in zip(labels, eachrow(A))
        conversion_fn = Symbol(label) in keys(convert_to) ? x->convert.(convert_to[Symbol(label)], x) : x->x
        cells[!, label] = conversion_fn(row)
    end
    getCellTypeToNameDict!(cell_type_to_name_dict, xml_doc)
    cells[!, :cell_type_name] = [cell_type_to_name_dict[ct] for ct in cells[!, :cell_type]]
    closeXML(xml_doc)
    return
end

function loadCells!(snapshot::PhysiCellSnapshot, cell_type_to_name_dict::Dict{Int, String}=Dict{Int, String}(), labels::Vector{String}=String[])
    loadCells!(snapshot.cells, joinpath(snapshot.folder, "$(indexToFilename(snapshot.index))"), cell_type_to_name_dict, labels)
end

function loadSubstrates(filepath_base::String, substrate_names::Vector{String})
    getSubstrateNames!(substrate_names, "$(filepath_base).xml")
    mat_file = "$(filepath_base)_microenvironment0.mat"
    A = matread(mat_file) |> values |> first # julia seems to read in the multiscale_microenvironment and assign the key multiscale_microenvironmen (note the missing 't'); do this to make sure we get the data
    substrates = DataFrame(A', [:x; :y; :z; :volume; substrate_names])
    return substrates, substrate_names
end

function loadSubstrates!(substrates::DataFrame, filepath_base::String, substrate_names::Vector{String})
    if !isempty(substrates)
        return
    end
    getSubstrateNames!(substrate_names, "$(filepath_base).xml")
    mat_file = "$(filepath_base)_microenvironment0.mat"
    A = matread(mat_file) |> values |> first # julia seems to read in the multiscale_microenvironment and assign the key multiscale_microenvironmen (note the missing 't'); do this to make sure we get the data
    labels = [:x; :y; :z; :volume; substrate_names]
    for (label, row) in zip(labels, eachrow(A))
        substrates[!, label] = row
    end
end
    
function loadSubstrates!(snapshot::PhysiCellSnapshot, substrate_names::Vector{String}=String[])
    loadSubstrates!(snapshot.substrates, joinpath(snapshot.folder, "$(indexToFilename(snapshot.index))"), substrate_names)
end

function loadMesh!(mesh::Dict{String, Vector{Float64}}, xml_doc::XMLDocument)
    xml_path = ["microenvironment", "domain", "mesh"]
    mesh_element = retrieveElement(xml_doc, xml_path; required=true)
    mesh["bounding_box"] = parse.(Float64, split(content(find_element(mesh_element, "bounding_box")), " "))
    for tag in ["x_coordinates", "y_coordinates", "z_coordinates"]
        coord_element = find_element(mesh_element, tag)
        mesh[string(tag[1])] = parse.(Float64, split(content(coord_element), attribute(coord_element, "delimiter"; required=true)))
    end
end

function loadMesh!(snapshot::PhysiCellSnapshot)
    xml_doc = openXML(joinpath(snapshot.folder, "$(indexToFilename(snapshot.index)).xml"))
    loadMesh!(snapshot.mesh, xml_doc)
    closeXML(xml_doc)
end


function PhysiCellSequence(folder::String; include_cells::Bool=false, include_substrates::Bool=false, include_mesh::Bool=false)
    cell_type_to_name_dict = Dict{Int, String}()
    if include_cells
        getCellTypeToNameDict!(cell_type_to_name_dict, folder)
    end
    labels = getLabels(folder)
    substrate_names = include_substrates ? getSubstrateNames(folder) : String[]
    index_to_snapshot = index -> PhysiCellSnapshot(folder, index; include_cells=include_cells, cell_type_to_name_dict=cell_type_to_name_dict, labels=labels, include_substrates=include_substrates, include_mesh=include_mesh)
    snapshots = PhysiCellSnapshot[index_to_snapshot(0)]
    index = 1
    while isfile(joinpath(folder, "output$(lpad(index,8,"0")).xml"))
        push!(snapshots, index_to_snapshot(index))
        index += 1
    end
    return PhysiCellSequence(folder, snapshots, cell_type_to_name_dict, substrate_names)
end

function getCellDataSequence(sequence::PhysiCellSequence, label::String; include_dead::Bool=false, include_cell_type::Bool=false)
    return getCellDataSequence(sequence, [label]; include_dead=include_dead, include_cell_type=include_cell_type)
end

"""
    getCellDataSequence(sequence::PhysiCellSequence, labels::Vector{String}; include_dead::Bool=false, include_cell_type::Bool=false)

Return a dictionary where the keys are cell IDs from the PhysiCell simulation and the values are NamedTuples containing the time and the values of the specified labels for that cell.
In the case of a label that has multiple columns, such as `position`, the values are concatenated into a length(snapshots) x number of columns array.

# Examples
```
data = getCellDataSequence(sequence, ["position", "elapsed_time_in_phase"]; include_dead=true, include_cell_type=true)
data[1] # the first cell's data
data[1].position # an Nx3 array of the cell's position over time
data[1].elapsed_time_in_phase # an Nx1 array of the cell's elapsed time in phase over time
data[1].cell_type_name # the cell type name of the first cell
```
"""
function getCellDataSequence(sequence::PhysiCellSequence, labels::Vector{String}; include_dead::Bool=false, include_cell_type::Bool=false)
    cell_features = sequence.snapshots[1].cells |> names
    label_features = Symbol[]
    temp_dict = Dict{Symbol, Vector{Symbol}}()
    for label in labels
        if label in cell_features
            L = Symbol(label)
            push!(label_features, L)
            temp_dict[L] = [L]
        else
            index = 1
            while "$(label)_$index" in cell_features
                index += 1
            end
            new_labels = [Symbol(label * "_$i") for i in 1:(index-1)]
            append!(label_features, new_labels)
            temp_dict[Symbol(label)] = new_labels
        end
    end
    labels = Symbol.(labels)
    if include_cell_type && !(:cell_type_name in labels)
        push!(labels, :cell_type_name)
        push!(label_features, :cell_type_name)
        temp_dict[:cell_type_name] = [:cell_type_name]
    end
    types = eltype.(eachcol(sequence.snapshots[1].cells)[label_features])
    data = Dict{Int, NamedTuple{(:time, label_features...), Tuple{Vector{Float64}, [Vector{type} for type in types]...}}}()
    for snapshot in sequence.snapshots
        for row in eachrow(snapshot.cells)
            if !include_dead && row[:dead]
                continue
            end
            if row.ID in keys(data)
                push!(data[row.ID].time, snapshot.time)
                for label_feature in label_features
                    push!(data[row.ID][label_feature], row[label_feature])
                end
            else
                data[row.ID] = NamedTuple{(:time, label_features...)}([[snapshot.time], [[row[label_feature]] for label_feature in label_features]...])
            end
        end
    end

    if all(length.(values(temp_dict)) .== 1)
        return data
    end
    C(v, label) = begin # Concatenation of columns that belong together
        if length(temp_dict[label]) == 1
            return v[temp_dict[label][1]]
        end
        return hcat(v[temp_dict[label]]...)
    end
    return [ID => NamedTuple{(:time, labels...)}([[v.time]; [C(v,label) for label in labels]]) for (ID, v) in data] |> Dict
end