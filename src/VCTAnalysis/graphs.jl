using Graphs, MetaGraphsNext

export connectedComponents

function connectedComponents(snapshot::PhysiCellSnapshot, graph::Symbol=:neighbors; include_cell_types=:all_in_one, exclude_cell_types=String[])
    is_all_in_one = include_cell_types == :all_in_one
    cell_type_to_name_dict = getCellTypeToNameDict(snapshot)
    cell_type_names = values(cell_type_to_name_dict) |> collect
    include_cell_types = processIncludeCellTypes(include_cell_types, cell_type_names)
    exclude_cell_types = processExcludeCellTypes(exclude_cell_types)
    loadGraph!(snapshot, graph)
    if is_all_in_one
        return Dict(include_cell_types => (getfield(snapshot, graph) |> copy |> connectedComponents))
    end

    loadCells!(snapshot)

    #! if not all_in_one, then we need to manage the cells carefully
    data = Dict{Any,Any}()

    for output_key in include_cell_types
        if output_key isa String
            internal_keys = [output_key] #! standardize so that all are vectors
        else
            internal_keys = output_key
        end
        setdiff!(internal_keys, exclude_cell_types) #! remove any cell types that are to be excluded (also removes duplicates)
        if isempty(internal_keys)
            continue
        end
        G = getfield(snapshot, graph) |> deepcopy
        vertices_to_remove = Int[]
        for v in vertices(G)
            agent_id = G.vertex_labels[v]
            row_log = snapshot.cells.ID .== agent_id.id
            cell_type = cell_type_to_name_dict[snapshot.cells.cell_type[row_log][1]]
            if !(cell_type in internal_keys)
                push!(vertices_to_remove, v)
            end
        end
        sort!(vertices_to_remove; rev=true)
        for v in vertices_to_remove
            rem_vertex!(G, v)
        end
        data[output_key] = connectedComponents(G)
    end
    return data
end

function connectedComponents(G::MetaGraph)
    transitiveclosure!(G.graph)
    for e in edges(G.graph)
        edge_datum = (G.vertex_labels[e.src], G.vertex_labels[e.dst])
        G.edge_data[edge_datum] = nothing
    end
    remaining_labels = Set(G.vertex_labels |> values)
    components = []
    while !isempty(remaining_labels)
        next_label = pop!(remaining_labels)
        next_label_ind = G.vertex_properties[next_label][1]
        neighbor_inds = all_neighbors(G.graph, next_label_ind)
        neighbor_labels = [G.vertex_labels[i] for i in neighbor_inds]
        component = vcat(next_label, neighbor_labels)
        push!(components, component)
        setdiff!(remaining_labels, component)
    end
    return components
end

connectedComponents(snapshot::PhysiCellSnapshot, graph::String; kwargs...) = connectedComponents(snapshot, Symbol(graph); kwargs...)