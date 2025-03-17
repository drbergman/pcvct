using DataFrames, MAT

export getCellDataSequence

abstract type AbstractPhysiCellSequence end

"""
    PhysiCellSnapshot

A single snapshot of a PhysiCell simulation.

The `cells`, `substrates`, and `mesh` fields may remain empty until they are needed for analysis.

# Fields
- `path_to_folder::String`: The path to the folder containing the PhysiCell simulation output.
- `index::Union{Int, Symbol}`: The index of the snapshot. Can be an integer or a symbol (`:initial` or `:final`).
- `time::Float64`: The time of the snapshot (in minutes).
- `cells::DataFrame`: A DataFrame containing cell data.
- `substrates::DataFrame`: A DataFrame containing substrate data.
- `mesh::Dict{String, Vector{Float64}}`: A dictionary containing mesh data.
"""
struct PhysiCellSnapshot <: AbstractPhysiCellSequence
    path_to_folder::String
    index::Union{Int,Symbol}
    time::Float64
    cells::DataFrame
    substrates::DataFrame
    mesh::Dict{String,Vector{Float64}}
end

function indexToFilename(index::Symbol)
    @assert index in [:initial, :final] "The non-integer index must be either :initial or :final"
    return string(index)
end

indexToFilename(index::Int) = "output$(lpad(index,8,"0"))"

"""
    PhysiCellSequence

A sequence of PhysiCell snapshots.

# Fields
- `path_to_folder::String`: The path to the folder containing the PhysiCell-defined simulation output.
- `snapshots::Vector{PhysiCellSnapshot}`: A vector of PhysiCell snapshots.
- `cell_type_to_name_dict::Dict{Int, String}`: A dictionary mapping cell type IDs to cell type names.
- `labels::Vector{String}`: A vector of cell data labels.
- `substrate_names::Vector{String}`: A vector of substrate names.
"""
struct PhysiCellSequence <: AbstractPhysiCellSequence
    path_to_folder::String
    snapshots::Vector{PhysiCellSnapshot}
    cell_type_to_name_dict::Dict{Int,String}
    labels::Vector{String}
    substrate_names::Vector{String}
end

function getLabels(path_to_folder::String)
    xml_doc = openXML(joinpath(path_to_folder, "initial.xml"))
    labels = getLabels(xml_doc)
    closeXML(xml_doc)
    return labels
end

function getLabels(xml_doc::XMLDocument)
    labels = String[]
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
                label_name = "elapsed_time_in_phase_2" #! hack to get around a MultiCellDS duplicate?
            end
            push!(labels, label_name)
        end
    end
    return labels
end

getLabels(snapshot::PhysiCellSnapshot) = getLabels(snapshot.path_to_folder)
getLabels(sequence::PhysiCellSequence) = sequence.labels

function getCellTypeToNameDict(path_to_folder::String)
    xml_doc = openXML(joinpath(path_to_folder, "initial.xml"))
    cell_type_to_name_dict = getCellTypeToNameDict(xml_doc)
    closeXML(xml_doc)
    return cell_type_to_name_dict
end

function getCellTypeToNameDict(xml_doc::XMLDocument)
    cell_type_to_name_dict = Dict{Int, String}()
    xml_path = ["cellular_information", "cell_populations", "cell_population", "custom", "simplified_data", "cell_types"]
    cell_types_element = retrieveElement(xml_doc, xml_path; required=true)

    for cell_type_element in child_elements(cell_types_element)
        cell_type_id = attribute(cell_type_element, "ID"; required=true) |> x -> parse(Int, x)
        cell_type_name = content(cell_type_element)
        cell_type_to_name_dict[cell_type_id] = cell_type_name
    end
    return cell_type_to_name_dict
end

getCellTypeToNameDict(snapshot::PhysiCellSnapshot) = getCellTypeToNameDict(snapshot.path_to_folder)
getCellTypeToNameDict(sequence::PhysiCellSequence) = sequence.cell_type_to_name_dict

function getSubstrateNames(path_to_folder::String)
    xml_doc = openXML(joinpath(path_to_folder, "initial.xml"))
    substrate_names = getSubstrateNames(xml_doc)
    closeXML(xml_doc)
    return substrate_names
end

function getSubstrateNames(xml_doc::XMLDocument)
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
    substrate_names = String[]
    for i in (substrate_dict |> keys |> collect |> sort)
        push!(substrate_names, substrate_dict[i])
    end
    return substrate_names
end

getSubstrateNames(snapshot::PhysiCellSnapshot) = getSubstrateNames(snapshot.path_to_folder)
getSubstrateNames(sequence::PhysiCellSequence) = sequence.substrate_names

function loadCells!(cells::DataFrame, filepath_base::String, cell_type_to_name_dict::Dict{Int, String}=Dict{Int, String}(), labels::Vector{String}=String[])
    if !isempty(cells)
        return
    end

    xml_doc = openXML("$(filepath_base).xml")
    if isempty(labels)
        labels = getLabels(xml_doc)
    end
    if isempty(cell_type_to_name_dict)
        cell_type_to_name_dict = getCellTypeToNameDict(xml_doc)
    end
    closeXML(xml_doc)

    mat_file = "$(filepath_base)_cells.mat"
    A = matread(mat_file)["cell"]
    conversion_dict = Dict("ID" => Int, "dead" => Bool, "cell_type" => Int)
    for (label, row) in zip(labels, eachrow(A))
        if label in keys(conversion_dict)
            cells[!, label] = convert.(conversion_dict[label], row)
        else
            cells[!, label] = row
        end
    end
    cells[!, :cell_type_name] = [cell_type_to_name_dict[ct] for ct in cells[!, :cell_type]]
    return
end

function loadCells!(snapshot::PhysiCellSnapshot, cell_type_to_name_dict::Dict{Int, String}=Dict{Int, String}(), labels::Vector{String}=String[])
    loadCells!(snapshot.cells, joinpath(snapshot.path_to_folder, "$(indexToFilename(snapshot.index))"), cell_type_to_name_dict, labels)
end

function loadCells!(sequence::PhysiCellSequence)
    cell_type_to_name_dict = getCellTypeToNameDict(sequence)
    labels = getLabels(sequence)
    for snapshot in sequence.snapshots
        loadCells!(snapshot, cell_type_to_name_dict, labels)
    end
end

function loadSubstrates!(substrates::DataFrame, filepath_base::String, substrate_names::Vector{String})
    if !isempty(substrates)
        return
    end

    if isempty(substrate_names)
        substrate_names = getSubstrateNames(dirname(filepath_base))
    end

    mat_file = "$(filepath_base)_microenvironment0.mat"
    A = matread(mat_file) |> values |> first #! julia seems to read in the multiscale_microenvironment and assign the key multiscale_microenvironmen (note the missing 't'); do this to make sure we get the data
    col_names = [:x; :y; :z; :volume; substrate_names]
    for (col_name, row) in zip(col_names, eachrow(A))
        substrates[!, col_name] = row
    end
end

function loadSubstrates!(snapshot::PhysiCellSnapshot, substrate_names::Vector{String}=String[])
    loadSubstrates!(snapshot.substrates, joinpath(snapshot.path_to_folder, "$(indexToFilename(snapshot.index))"), substrate_names)
end

function loadSubstrates!(sequence::PhysiCellSequence)
    for snapshot in sequence.snapshots
        loadSubstrates!(snapshot, sequence.substrate_names)
    end
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
    xml_doc = openXML(joinpath(snapshot.path_to_folder, "$(indexToFilename(snapshot.index)).xml"))
    loadMesh!(snapshot.mesh, xml_doc)
    closeXML(xml_doc)
end

function loadMesh!(sequence::PhysiCellSequence)
    for snapshot in sequence.snapshots
        loadMesh!(snapshot)
    end
end

function PhysiCellSnapshot(path_to_folder::String, index::Union{Int, Symbol}; include_cells::Bool=false, cell_type_to_name_dict::Dict{Int, String}=Dict{Int, String}(), labels::Vector{String}=String[], include_substrates::Bool=false, substrate_names::Vector{String}=String[], include_mesh::Bool=false)
    filepath_base = joinpath(path_to_folder, indexToFilename(index))
    xml_doc = openXML("$(filepath_base).xml")
    time = getContent(xml_doc, ["metadata","current_time"]) |> x->parse(Float64, x)
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
    return PhysiCellSnapshot(path_to_folder, index, time, DataFrame(cells), substrates, mesh)
end

PhysiCellSnapshot(simulation_id::Integer, index::Union{Int, Symbol}; kwargs...) = PhysiCellSnapshot(joinpath(outputFolder("simulation", simulation_id), "output"), index; kwargs...)

function PhysiCellSequence(path_to_folder::String; include_cells::Bool=false, include_substrates::Bool=false, include_mesh::Bool=false)
    cell_type_to_name_dict = getCellTypeToNameDict(path_to_folder)
    labels = getLabels(path_to_folder)
    substrate_names = include_substrates ? getSubstrateNames(path_to_folder) : String[]
    index_to_snapshot = index -> PhysiCellSnapshot(path_to_folder, index; include_cells=include_cells, cell_type_to_name_dict=cell_type_to_name_dict, labels=labels, include_substrates=include_substrates, include_mesh=include_mesh)
    snapshots = PhysiCellSnapshot[index_to_snapshot(0)]
    index = 1
    while isfile(joinpath(path_to_folder, "output$(lpad(index,8,"0")).xml"))
        push!(snapshots, index_to_snapshot(index))
        index += 1
    end
    return PhysiCellSequence(path_to_folder, snapshots, cell_type_to_name_dict, labels, substrate_names)
end

function PhysiCellSequence(simulation_id::Integer; kwargs...)
    return PhysiCellSequence(joinpath(outputFolder("simulation", simulation_id), "output"); kwargs...)
end

function PhysiCellSequence(simulation::Simulation; kwargs...)
    return PhysiCellSequence(simulation.id; kwargs...)
end

"""
    getCellDataSequence(simulation_id::Integer, labels::Vector{String}; include_dead::Bool=false, include_cell_type::Bool=false)

Return a dictionary where the keys are cell IDs from the PhysiCell simulation and the values are NamedTuples containing the time and the values of the specified labels for that cell.
For scalar values, such as `volume`, the values are in a length `N` vector, where `N` is the number of snapshots in the simulation.
In the case of a label that has multiple columns, such as `position`, the values are concatenated into a length(snapshots) x number of columns array.

# Arguments
- `simulation_id::Integer`: The ID of the PhysiCell simulation. Alternatively, can be a `Simulation` object or a `PhysiCellSequence` object.
- `labels::Vector{String}`: The labels to extract from the cell data. If a label has multiple columns, such as `position`, the columns are concatenated into a single array. Alternatively, a single label string can be passed.
- `include_dead::Bool=false`: Whether to include dead cells in the data.
- `include_cell_type::Bool=false`: Whether to include the cell type name in the data. Equivalent to including `\"cell_type_name\"` in `labels`.

# Examples
```
data = getCellDataSequence(sequence, ["position", "elapsed_time_in_phase"]; include_dead=true, include_cell_type=true)
data[1] # the first cell's data
data[1].position # an Nx3 array of the cell's position over time
data[1].elapsed_time_in_phase # an Nx1 array of the cell's elapsed time in phase over time
data[1].cell_type_name # an Nx1 array of the cell type name of the first cell over time
```
"""
function getCellDataSequence(simulation_id::Integer, labels::Vector{String}; kwargs...)
    sequence = PhysiCellSequence(simulation_id)
    return getCellDataSequence(sequence, labels; kwargs...)
end

function getCellDataSequence(simulation_id::Integer, label::String; kwargs...)
    return getCellDataSequence(simulation_id, [label]; kwargs...)
end

function getCellDataSequence(simulation::Simulation, labels::Vector{String}; kwargs...)
    sequence = PhysiCellSequence(simulation)
    return getCellDataSequence(sequence, labels; kwargs...)
end

function getCellDataSequence(simulation::Simulation, label::String; kwargs...)
    return getCellDataSequence(simulation, [label]; kwargs...)
end

function getCellDataSequence(sequence::PhysiCellSequence, label::String; kwargs...)
    return getCellDataSequence(sequence, [label]; kwargs...)
end

function getCellDataSequence(sequence::PhysiCellSequence, labels::Vector{String}; include_dead::Bool=false, include_cell_type::Bool=false)
    loadCells!(sequence)
    cell_features = getLabels(sequence)
    label_features = Symbol[]
    temp_dict = Dict{Symbol, Vector{Symbol}}()
    for label in labels
        if label in cell_features
            L = Symbol(label)
            push!(label_features, L)
            temp_dict[L] = [L]
        else
            index = 1
            while "$(label)_$(index)" in cell_features
                index += 1
            end
            @assert index > 1 "Label $label not found in cell data"
            new_labels = [Symbol("$(label)_$(i)") for i in 1:(index-1)]
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
    C(v, label) = begin #! Concatenation of columns that belong together
        if length(temp_dict[label]) == 1
            return v[temp_dict[label][1]]
        end
        return hcat(v[temp_dict[label]]...)
    end
    return [ID => NamedTuple{(:time, labels...)}([[v.time]; [C(v,label) for label in labels]]) for (ID, v) in data] |> Dict
end
