export PhysiCellSnapshot, PhysiCellSequence, getCellPositionSequence, getCellDataSequence, computeMeanSpeed

abstract type AbstractPhysiCellSequence end

struct PhysiCellSnapshot <: AbstractPhysiCellSequence
    folder::String
    index::Int
    time::Float64
    cells::DataFrame
end

struct PhysiCellSequence <: AbstractPhysiCellSequence
    folder::String
    snapshots::Vector{PhysiCellSnapshot}
end

function getLabels(xml_doc::XMLDocument)
    xml_path = ["cellular_information", "cell_populations", "cell_population", "custom", "simplified_data", "labels"]
    labels_element = VCTModule.retrieveElement(xml_doc, xml_path; required=true)

    labels = String[]
    for label in child_elements(labels_element)
        name = content(label)
        label_ind_width = attribute(label, "size"; required=true) |> x -> parse(Int, x)
        if label_ind_width > 1
            name = [name * "_$i" for i in 1:label_ind_width]
            append!(labels, name)
        else
            if name == "elapsed_time_in_phase" && name in labels
                name = "elapsed_time_in_phase_2" # hack to get around a MultiCellDS duplicate?
            end
            push!(labels, name)
        end
    end
    return labels
end

function PhysiCellSnapshot(folder::String, index::Int; labels::Vector{String}=String[])
    xml_doc = VCTModule.openXML("$(folder)/output$(lpad(index,8,"0")).xml")
    mat_file = "$(folder)/output$(lpad(index,8,"0"))_cells.mat"
    time = VCTModule.getField(xml_doc, ["metadata","current_time"]) |> x->parse(Float64, x)
    if isempty(labels)
        labels = getLabels(xml_doc)
    end
    cells = DataFrame(matread(mat_file)["cell"]', labels)
    cells[!,:ID] = convert.(Int,cells[!,:ID])
    cells[!,:dead] = convert.(Bool,cells[!,:dead])
    cells[!,:cell_type] = convert.(Int,cells[!,:cell_type])
    VCTModule.closeXML(xml_doc)
    return PhysiCellSnapshot(folder, index, time, DataFrame(cells))
end

function PhysiCellSequence(folder::String)
    snapshots = PhysiCellSnapshot[PhysiCellSnapshot(folder, 0)]
    labels = snapshots[1].cells |> names
    index = 1
    while isfile("$(folder)/output$(lpad(index,8,"0")).xml")
        push!(snapshots, PhysiCellSnapshot(folder, index; labels=labels))
        index += 1
    end
    return PhysiCellSequence(folder, snapshots)
end

function getCellDataSequence(sequence::PhysiCellSequence, label::String; include_dead::Bool=false, include_cell_type::Bool=false)
    return getCellDataSequence(sequence, [label]; include_dead=include_dead, include_cell_type=include_cell_type)
end

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
    if include_cell_type && !(:cell_type in labels)
        push!(labels, :cell_type)
        push!(label_features, :cell_type)
        temp_dict[:cell_type] = [:cell_type]
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

function getCellPositionSequence(sequence::PhysiCellSequence; include_dead::Bool=false, include_cell_type::Bool=true)
    return getCellDataSequence(sequence, "position"; include_dead=include_dead, include_cell_type=include_cell_type)
end

function meanSpeed(p)
    x = p.position[:, 1]
    y = p.position[:, 2]
    cell_type = p.cell_type
    dx = x[2:end] .- x[1:end-1]
    dy = y[2:end] .- y[1:end-1]
    type_change = cell_type[2:end] .!= cell_type[1:end-1]
    start_ind = 1
    cell_types = unique(cell_type)
    distance_dict = Dict{Int, Float64}(zip(cell_types, zeros(Float64, length(cell_types))))
    time_dict = Dict{Int, Float64}(zip(cell_types, zeros(Float64, length(cell_types))))
    while start_ind <= length(type_change) 
        I = findfirst(type_change[start_ind:end]) # from s to I, cell_type is constant. at I+1 it changes
        I = isnothing(I) ? length(type_change)+2-start_ind : I # if the cell_type is constant till the end, set I to be at the end
        # If start_ind = 1 (at start of sim) and I = 2 (so cell_type[3] != cell_type[2], meaning that for steps [1,2] cell_type is constnat), only use dx in stepping from 1->2 since somewhere in 2->3 the type changes. That is, use dx[1]
        distance_dict[cell_type[start_ind]] += sum(sqrt.(dx[start_ind:start_ind+I-2] .^ 2 + dy[start_ind:start_ind+I-2] .^ 2)) # only count distance travelled while remaining in the initial cell_type
        time_dict[cell_type[start_ind]] += p.time[start_ind+I-1] - p.time[start_ind] # record time spent in this cell_type (note p.time is not diffs like dx and dy are, hence the difference in indices)
        start_ind += I # advance the start to the first instance of a new cell_type
    end
    return [k => distance_dict[k] / time_dict[k] for k in cell_types] |> Dict # convert to speed
end

function computeMeanSpeed(simulation_id::Int)
    return "$(data_dir)/outputs/simulations/$(simulation_id)/output" |> computeMeanSpeed
end

function computeMeanSpeed(folder::String)
    sequence = PhysiCellSequence(folder)
    pos = getCellDataSequence(sequence, "position"; include_dead=false, include_cell_type=true)
    return [meanSpeed(p) for p in values(pos) if length(p.time) > 1]
end

function computeMeanSpeed(class_id::VCTClassID)
    simulation_ids = getSimulations(class_id)
    return [simulation_id => computeMeanSpeed(simulation_id) for simulation_id in simulation_ids] |> Dict
end

computeMeanSpeed(T::AbstractTrial) = computeMeanSpeed((typeof(T), T.id))