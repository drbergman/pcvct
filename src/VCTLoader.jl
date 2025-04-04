using DataFrames, MAT, Graphs, MetaGraphsNext

export getCellDataSequence, PhysiCellSnapshot, PhysiCellSequence

abstract type AbstractPhysiCellSequence end

"""
    PhysiCellSnapshot

A single snapshot of a PhysiCell simulation.

The `cells`, `substrates`, and `mesh` fields may remain empty until they are needed for analysis.

# Fields
- `simulation_id::Int`: The ID of the simulation.
- `index::Union{Int,Symbol}`: The index of the snapshot. Can be an integer or a symbol (`:initial` or `:final`).
- `time::Float64`: The time of the snapshot (in minutes).
- `cells::DataFrame`: A DataFrame containing cell data.
- `substrates::DataFrame`: A DataFrame containing substrate data.
- `mesh::Dict{String, Vector{Float64}}`: A dictionary containing mesh data.
- `attachments::MetaGraph`: A graph of cell attachment data with vertices labeled by cell IDs.
- `spring_attachments::MetaGraph`: A graph of spring attachment data with vertices labeled by cell IDs.
- `neighbors::MetaGraph`: A graph of cell neighbor data with vertices labeled by cell IDs.
"""
struct PhysiCellSnapshot <: AbstractPhysiCellSequence
    simulation_id::Int
    index::Union{Int,Symbol}
    time::Float64
    cells::DataFrame
    substrates::DataFrame
    mesh::Dict{String,Vector{Float64}}
    attachments::MetaGraph
    spring_attachments::MetaGraph
    neighbors::MetaGraph
end

function PhysiCellSnapshot(simulation_id::Int, index::Union{Integer, Symbol};
    include_cells::Bool=false,
    cell_type_to_name_dict::Dict{Int, String}=Dict{Int, String}(),
    labels::Vector{String}=String[],
    include_substrates::Bool=false,
    substrate_names::Vector{String}=String[],
    include_mesh::Bool=false,
    include_attachments::Bool=false,
    include_spring_attachments::Bool=false,
    include_neighbors::Bool=false)

    filepath_base = pathToOutputFileBase(simulation_id, index)
    path_to_xml = joinpath("$(filepath_base).xml")
    if !isfile(path_to_xml)
        println("Could not find file $path_to_xml. Returning missing.")
        return missing
    end
    xml_doc = openXML("$(filepath_base).xml")
    time = getContent(xml_doc, ["metadata","current_time"]) |> x->parse(Float64, x)
    cells = DataFrame()
    if include_cells
        if loadCells!(cells, filepath_base, cell_type_to_name_dict, labels) |> ismissing
            println("Could not load cell data for snapshot $(index) of simulation $simulation_id. Returning missing.")
            return missing
        end
    end
    substrates = DataFrame()
    if include_substrates
        if loadSubstrates!(substrates, filepath_base, substrate_names) |> ismissing
            println("Could not load substrate data for snapshot $(index) of simulation $simulation_id. Returning missing.")
            return missing
        end
    end
    mesh = Dict{String, Vector{Float64}}()
    if include_mesh
        loadMesh!(mesh, xml_doc)
    end

    attachments = physicellEmptyGraph()
    if include_attachments
        if loadGraph!(attachments, "$(filepath_base)_attached_cells_graph.txt", :attachments) |> ismissing
            println("Could not load attachments for snapshot $(index) of simulation $simulation_id. Returning missing.")
            return missing
        end
    end
    
    spring_attachments = physicellEmptyGraph()
    if include_spring_attachments
        if loadGraph!(spring_attachments, "$(filepath_base)_spring_attached_cells_graph.txt", :spring_attachments) |> ismissing
            println("Could not load spring attachments for snapshot $(index) of simulation $simulation_id. Returning missing.")
            return missing
        end
    end
    
    neighbors = physicellEmptyGraph()
    if include_neighbors
        if loadGraph!(neighbors, "$(filepath_base)_cell_neighbor_graph.txt", :neighbors) |> ismissing
            println("Could not load neighbors for snapshot $(index) of simulation $simulation_id. Returning missing.")
            return missing
        end
    end
    closeXML(xml_doc)
    return PhysiCellSnapshot(simulation_id, index, time, DataFrame(cells), substrates, mesh, attachments, spring_attachments, neighbors)
end

PhysiCellSnapshot(simulation::Simulation, index::Union{Integer,Symbol}; kwargs...) = PhysiCellSnapshot(simulation.id, index; kwargs...)

function Base.show(io::IO, ::MIME"text/plain", snapshot::PhysiCellSnapshot)
    println(io, "PhysiCellSnapshot (SimID=$(snapshot.simulation_id), Index=$(snapshot.index))")
    println(io, "  Time: $(snapshot.time)")
    println(io, "  Cells: $(isempty(snapshot.cells) ? "NOT LOADED" : "($(nrow(snapshot.cells)) cells x $(ncol(snapshot.cells)) features) DataFrame")")
    println(io, "  Substrates: $(isempty(snapshot.substrates) ? "NOT LOADED" : "($(size(snapshot.substrates, 1)) voxels x [x, y, z, volume, $(size(snapshot.substrates, 2)-4) substrates]) DataFrame")")
    println(io, "  Mesh: $(isempty(snapshot.mesh) ? "NOT LOADED" : meshInfo(snapshot))")
    println(io, "  Attachments: $(nv(snapshot.attachments)==0 ? "NOT LOADED" : graphInfo(snapshot.attachments))")
    println(io, "  Spring Attachments: $(nv(snapshot.spring_attachments)==0 ? "NOT LOADED" : graphInfo(snapshot.spring_attachments))")
    println(io, "  Neighbors: $(nv(snapshot.neighbors)==0 ? "NOT LOADED" : graphInfo(snapshot.neighbors))")
end

function indexToFilename(index::Symbol)
    @assert index in [:initial, :final] "The non-integer index must be either :initial or :final"
    return string(index)
end

indexToFilename(index::Int) = "output$(lpad(index,8,"0"))"

"""
    AgentID

A wrapper for the agent ID used in PhysiCell.

The purpose of this struct is to make it easier to interpret the data in the MetaGraphs loaded from PhysiCell.
The MetaGraphs use `Int`s to index the vertices, which could cause confusion when looking at the mappings to the agent ID metadata if also using `Int`s.
"""
struct AgentID
    id::Int
end

Base.parse(::Type{AgentID}, s::AbstractString) = AgentID(parse(Int, s))

function physicellEmptyGraph()
    return MetaGraph(SimpleDiGraph();
        label_type=AgentID,
        vertex_data_type=Nothing,
        edge_data_type=Nothing)
end

function readPhysiCellGraph!(g::MetaGraph, path_to_txt_file::String)
    lines = readlines(path_to_txt_file)
    for line in lines
        cell_id, attached_ids = split(line, ": ")
        cell_id = parse(AgentID, cell_id)
        g[cell_id] = nothing
        if attached_ids == ""
            continue
        end
        for attached_id in split(attached_ids, ",")
            attached_id = parse(AgentID, attached_id)
            g[attached_id] = nothing
            g[cell_id, attached_id] = nothing
        end
    end
end

"""
    PhysiCellSequence

A sequence of PhysiCell snapshots.

By default, only the simulation ID, index, and time are recorded for each PhysiCellSnapshot in the sequence.
To include any of `cells`, `substrates`, `mesh`, `attachments`, `spring_attachments`, or `neighbors`, pass in the corresponding keyword argument as `true` (see below).

# Fields
- `simulation_id::Int`: The ID of the simulation.
- `snapshots::Vector{PhysiCellSnapshot}`: A vector of PhysiCell snapshots.
- `cell_type_to_name_dict::Dict{Int, String}`: A dictionary mapping cell type IDs to cell type names.
- `labels::Vector{String}`: A vector of cell data labels.
- `substrate_names::Vector{String}`: A vector of substrate names.

# Examples
```julia
sequence = PhysiCellSequence(1; include_cells=true, include_substrates=true) # loads cell and substrate data for simulation ID 1
sequence = PhysiCellSequence(simulation; include_attachments=true, include_spring_attachments=true) # loads attachment data for a Simulation object
sequence = PhysiCellSequence(1; include_mesh=true, include_neighbors=true) # loads mesh and neighbor data for simulation ID 1
```
"""
struct PhysiCellSequence <: AbstractPhysiCellSequence
    simulation_id::Int
    snapshots::Vector{PhysiCellSnapshot}
    cell_type_to_name_dict::Dict{Int,String}
    labels::Vector{String}
    substrate_names::Vector{String}
end

function PhysiCellSequence(simulation_id::Integer;
    include_cells::Bool=false,
    include_substrates::Bool=false,
    include_mesh::Bool=false,
    include_attachments::Bool=false,
    include_spring_attachments::Bool=false,
    include_neighbors::Bool=false)

    path_to_xml = pathToOutputXML(simulation_id, :initial)
    cell_type_to_name_dict = getCellTypeToNameDict(path_to_xml)
    if isempty(cell_type_to_name_dict)
        println("Could not find cell type information in $path_to_xml. This means that there is no initial.xml file, possibly due to pruning. Returning missing.")
        return missing
    end
    labels = getLabels(path_to_xml)
    substrate_names = include_substrates ? getSubstrateNames(path_to_xml) : String[]
    index_to_snapshot = index -> PhysiCellSnapshot(simulation_id, index;
                                                   include_cells=include_cells,
                                                   cell_type_to_name_dict=cell_type_to_name_dict,
                                                   labels=labels,
                                                   include_substrates=include_substrates,
                                                   include_mesh=include_mesh,
                                                   include_attachments=include_attachments,
                                                   include_spring_attachments=include_spring_attachments,
                                                   include_neighbors=include_neighbors)

    snapshots = PhysiCellSnapshot[]
    index = 0
    while isfile(pathToOutputXML(simulation_id, index))
        push!(snapshots, index_to_snapshot(index))
        index += 1
    end
    return PhysiCellSequence(simulation_id, snapshots, cell_type_to_name_dict, labels, substrate_names)
end

PhysiCellSequence(simulation::Simulation; kwargs...) = PhysiCellSequence(simulation.id; kwargs...)

function Base.show(io::IO, ::MIME"text/plain", sequence::PhysiCellSequence)
    println(io, "PhysiCellSequence (SimID=$(sequence.simulation_id))")
    println(io, "  #Snapshots: $(length(sequence.snapshots))")
    println(io, "  Cell Types: $(join(values(sequence.cell_type_to_name_dict), ", "))")
    println(io, "  Substrates: $(join(sequence.substrate_names, ", "))")
    loadMesh!(sequence.snapshots[1])
    println(io, "  Mesh: $(meshInfo(sequence))")
end

pathToOutputFolder(simulation_id::Integer) = return joinpath(trialFolder("simulation", simulation_id), "output")
pathToOutputFileBase(simulation_id::Integer, index::Union{Integer,Symbol}) = joinpath(pathToOutputFolder(simulation_id), indexToFilename(index))
pathToOutputFileBase(snapshot::PhysiCellSnapshot) = pathToOutputFileBase(snapshot.simulation_id, snapshot.index)
pathToOutputXML(simulation_id::Integer, index::Union{Integer,Symbol}) = "$(pathToOutputFileBase(simulation_id, index)).xml"
pathToOutputXML(snapshot::PhysiCellSnapshot) = pathToOutputXML(snapshot.simulation_id, snapshot.index)

function getLabels(path_to_file::String)
    if !isfile(path_to_file)
        return String[]
    end
    xml_doc = openXML(path_to_file)
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

getLabels(snapshot::PhysiCellSnapshot) = pathToOutputXML(snapshot) |> getLabels
getLabels(sequence::PhysiCellSequence) = sequence.labels

function getCellTypeToNameDict(path_to_file::String)
    if !isfile(path_to_file)
        return Dict{Int,String}()
    end
    xml_doc = openXML(path_to_file)
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

getCellTypeToNameDict(snapshot::PhysiCellSnapshot) = pathToOutputXML(snapshot) |> getCellTypeToNameDict
getCellTypeToNameDict(sequence::PhysiCellSequence) = sequence.cell_type_to_name_dict

function getSubstrateNames(path_to_file::String)
    if !isfile(path_to_file)
        return String[]
    end
    xml_doc = openXML(path_to_file)
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

getSubstrateNames(snapshot::PhysiCellSnapshot) = pathToOutputXML(snapshot) |> getSubstrateNames
getSubstrateNames(sequence::PhysiCellSequence) = sequence.substrate_names

function loadCells!(cells::DataFrame, filepath_base::String, cell_type_to_name_dict::Dict{Int, String}=Dict{Int, String}(), labels::Vector{String}=String[])
    if !isempty(cells)
        return
    end

    if isempty(labels) || isempty(cell_type_to_name_dict)
        xml_doc = openXML("$(filepath_base).xml")
        if isempty(labels)
            labels = getLabels(xml_doc)
        end
        if isempty(cell_type_to_name_dict)
            cell_type_to_name_dict = getCellTypeToNameDict(xml_doc)
        end
        closeXML(xml_doc)

        #! confirm that these were both found
        @assert !isempty(labels) && !isempty(cell_type_to_name_dict) "Could not find cell type information and/or labels in $(filepath_base).xml"
    end
        
    mat_file = "$(filepath_base)_cells.mat"
    if !isfile(mat_file)
        println("When loading cells, could not find file $mat_file. Returning missing.")
        return missing
    end
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
    loadCells!(snapshot.cells, pathToOutputFileBase(snapshot), cell_type_to_name_dict, labels)
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
        substrate_names = "$(filepath_base).xml" |> getSubstrateNames
        @assert !isempty(substrate_names) "Could not find substrate names in $(filepath_base).xml"
    end

    mat_file = "$(filepath_base)_microenvironment0.mat"
    if !isfile(mat_file)
        println("When loading substrates, could not find file $mat_file. Returning missing.")
        return missing
    end
    A = matread(mat_file) |> values |> first #! julia seems to read in the multiscale_microenvironment and assign the key multiscale_microenvironmen (note the missing 't'); do this to make sure we get the data
    col_names = [:x; :y; :z; :volume; substrate_names]
    for (col_name, row) in zip(col_names, eachrow(A))
        substrates[!, col_name] = row
    end
end

function loadSubstrates!(snapshot::PhysiCellSnapshot, substrate_names::Vector{String}=String[])
    loadSubstrates!(snapshot.substrates, pathToOutputFileBase(snapshot), substrate_names)
end

function loadSubstrates!(sequence::PhysiCellSequence)
    for snapshot in sequence.snapshots
        loadSubstrates!(snapshot, sequence.substrate_names)
    end
end

function loadMesh!(mesh::Dict{String, Vector{Float64}}, xml_doc::XMLDocument)
    if !isempty(mesh)
        return
    end
    xml_path = ["microenvironment", "domain", "mesh"]
    mesh_element = retrieveElement(xml_doc, xml_path; required=true)
    mesh["bounding_box"] = parse.(Float64, split(content(find_element(mesh_element, "bounding_box")), " "))
    for tag in ["x_coordinates", "y_coordinates", "z_coordinates"]
        coord_element = find_element(mesh_element, tag)
        mesh[string(tag[1])] = parse.(Float64, split(content(coord_element), attribute(coord_element, "delimiter"; required=true)))
    end
end

function loadMesh!(snapshot::PhysiCellSnapshot)
    path_to_file = pathToOutputXML(snapshot)
    xml_doc = openXML(path_to_file)
    loadMesh!(snapshot.mesh, xml_doc)
    closeXML(xml_doc)
    return
end

function loadMesh!(sequence::PhysiCellSequence)
    for snapshot in sequence.snapshots
        loadMesh!(snapshot)
    end
end

function meshInfo(snapshot::PhysiCellSnapshot)
    mesh = snapshot.mesh
    grid_size = [length(mesh[k]) for k in ["x", "y", "z"] if length(mesh[k]) > 1]
    domain_size = [[mesh[k][1], mesh[k][end]] + 0.5*(mesh[k][2] - mesh[k][1]) * [-1, 1] for k in ["x", "y", "z"] if length(mesh[k]) > 1]
    return "$(join(grid_size, " x ")) grid on $(join(domain_size, " x "))"
end

meshInfo(sequence::PhysiCellSequence) = meshInfo(sequence.snapshots[1])

function loadGraph!(G::MetaGraph, path_to_txt_file::String, graph::Symbol)
    if nv(G) > 0
        return
    end
    if !isfile(path_to_txt_file)
        println("When loading graph $(graph), could not find file $path_to_txt_file. Returning missing.")
        return missing
    end
    readPhysiCellGraph!(G, path_to_txt_file)
end

function loadGraph!(snapshot::PhysiCellSnapshot, graph::Symbol)
    @assert graph in [:attachments, :spring_attachments, :neighbors] "Graph must be one of [:attachments, :spring_attachments, :neighbors]"
    if graph == :attachments
        path_to_txt_file = pathToOutputFileBase(snapshot) * "_attached_cells_graph.txt"
    elseif graph == :spring_attachments
        path_to_txt_file = pathToOutputFileBase(snapshot) * "_spring_attached_cells_graph.txt"
    elseif graph == :neighbors
        path_to_txt_file = pathToOutputFileBase(snapshot) * "_cell_neighbor_graph.txt"
    end
    loadGraph!(snapshot, path_to_txt_file, graph)
end

function loadGraph!(snapshot::PhysiCellSnapshot, path_to_txt_file::String, graph::Symbol)
    loadGraph!(getfield(snapshot, graph), path_to_txt_file, graph)
end

function loadGraph!(sequence::PhysiCellSequence, graph::Symbol)
    for snapshot in sequence.snapshots
        loadGraph!(snapshot, graph)
    end
end

function graphInfo(g::MetaGraph)
    return "directed graph with $(nv(g)) vertices and $(ne(g)) edges"
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
