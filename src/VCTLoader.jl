using DataFrames

export PhysiCellSnapshot, PhysiCellSequence, getCellPositionSequence, getCellDataSequence, computeMeanSpeed, finalPopulationCount, populationTimeSeries

abstract type AbstractPhysiCellSequence end

struct PhysiCellSnapshot <: AbstractPhysiCellSequence
    folder::String
    index::Union{Int, Symbol}
    time::Float64
    cells::DataFrame
end

struct PhysiCellSequence <: AbstractPhysiCellSequence
    folder::String
    snapshots::Vector{PhysiCellSnapshot}
    cell_type_to_name_dict::Dict{Int, String}
end

function getLabels(xml_doc::XMLDocument)
    xml_path = ["cellular_information", "cell_populations", "cell_population", "custom", "simplified_data", "labels"]
    labels_element = retrieveElement(xml_doc, xml_path; required=true)

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

getLabels(folder::String) = joinpath(folder, "initial.xml") |> openXML |> getLabels

function getCellTypeToNameDict(xml_doc::XMLDocument)
    xml_path = ["cellular_information", "cell_populations", "cell_population", "custom", "simplified_data", "cell_types"]
    cell_types_element = retrieveElement(xml_doc, xml_path; required=true)

    cell_type_to_name_dict = Dict{Int, String}()
    for cell_type_element in child_elements(cell_types_element)
        cell_type_id = attribute(cell_type_element, "ID"; required=true) |> x -> parse(Int, x)
        name = content(cell_type_element)
        cell_type_to_name_dict[cell_type_id] = name
    end
    return cell_type_to_name_dict
end

getCellTypeToNameDict(folder::String) = joinpath(folder, "initial.xml") |> openXML |> getCellTypeToNameDict

function indexToFilename(index::Symbol)
    @assert index in [:initial, :final] "The non-integer index must be either :initial or :final"
    return string(index)
end
indexToFilename(index::Int) = "output$(lpad(index,8,"0"))"

function PhysiCellSnapshot(folder::String, index::Union{Int, Symbol}; cell_type_to_name_dict::Dict{Int, String}=Dict{Int, String}(), labels::Vector{String}=String[])
    filepath_base = joinpath(folder, indexToFilename(index))
    xml_doc = openXML("$(filepath_base).xml")
    mat_file = "$(filepath_base)_cells.mat"
    time = getField(xml_doc, ["metadata","current_time"]) |> x->parse(Float64, x)
    if isempty(labels)
        labels = getLabels(xml_doc)
    end
    cells = DataFrame(matread(mat_file)["cell"]', labels)
    cells[!,:ID] = convert.(Int,cells[!,:ID])
    cells[!,:dead] = convert.(Bool,cells[!,:dead])
    cells[!,:cell_type] = convert.(Int,cells[!,:cell_type])
    if isempty(cell_type_to_name_dict)
        cell_type_to_name_dict = getCellTypeToNameDict(xml_doc)
    end
    cells[!,:cell_type_name] = [cell_type_to_name_dict[ct] for ct in cells[!,:cell_type]]
    closeXML(xml_doc)
    return PhysiCellSnapshot(folder, index, time, DataFrame(cells))
end

function PhysiCellSequence(folder::String)
    cell_type_to_name_dict = getCellTypeToNameDict(folder)
    labels = getLabels(folder)
    snapshots = PhysiCellSnapshot[PhysiCellSnapshot(folder, 0; cell_type_to_name_dict=cell_type_to_name_dict, labels=labels)]
    index = 1
    while isfile(joinpath(folder, "output$(lpad(index,8,"0")).xml"))
        push!(snapshots, PhysiCellSnapshot(folder, index; cell_type_to_name_dict=cell_type_to_name_dict, labels=labels))
        index += 1
    end
    return PhysiCellSequence(folder, snapshots, cell_type_to_name_dict)
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

# population functions

function populationCount(snapshot::PhysiCellSnapshot; include_dead::Bool=false, cell_type_to_name_dict::Dict{Int, String}=Dict{Int, String}())
    data = Dict{String, Int}()
    if include_dead
        cell_df = snapshot.cells
    else
        cell_df = @view snapshot.cells[snapshot.cells.dead .== false, :]
    end
    if isempty(cell_type_to_name_dict)
        cell_type_to_name_dict = getCellTypeToNameDict(snapshot.folder)
    end
    cell_type_names = values(cell_type_to_name_dict)
    for cell_type_name in cell_type_names
        data[cell_type_name] = count(x -> x == cell_type_name, cell_df.cell_type_name)
    end
    return data
end

function populationTimeSeries(sequence::PhysiCellSequence; include_dead::Bool=false)
    df = DataFrame(time = [snapshot.time for snapshot in sequence.snapshots])
    for (i, snapshot) in enumerate(sequence.snapshots)
        population_count = populationCount(snapshot; include_dead=include_dead, cell_type_to_name_dict=sequence.cell_type_to_name_dict)
        for (ID, count) in pairs(population_count)
            if string(ID) in names(df)
                df[i, Symbol(ID)] = count
            else
                df[!, Symbol(ID)] = zeros(Int, nrow(df))
                df[i, Symbol(ID)] = count
            end
        end
    end
    return df
end

function populationTimeSeries(folder::String; include_dead::Bool=false)
    return PhysiCellSequence(folder) |> x -> populationTimeSeries(x; include_dead=include_dead)
end

function populationTimeSeries(simulation_id::Int; include_dead::Bool=false)
    df = joinpath(data_dir, "outputs", "simulations", string(simulation_id), "output") |> x -> populationTimeSeries(x; include_dead=include_dead)
    println("Finished populationTimeSeries for simulation_id: $simulation_id")
    return df
end

function finalPopulationCount(folder::String; include_dead::Bool=false)
    final_snapshot = PhysiCellSnapshot(folder, :final)
    return populationCount(final_snapshot; include_dead=include_dead)
end

function finalPopulationCount(simulation_id::Int; include_dead::Bool=false)
    return joinpath(data_dir, "outputs", "simulations", string(simulation_id), "output") |> x -> finalPopulationCount(x; include_dead=include_dead)
end

# speed functions

function getCellPositionSequence(sequence::PhysiCellSequence; include_dead::Bool=false, include_cell_type::Bool=true)
    return getCellDataSequence(sequence, "position"; include_dead=include_dead, include_cell_type=include_cell_type)
end

function meanSpeed(p; direction=:any)::NTuple{3,Dict{String,Float64}}
    x, y, z = [col for col in eachcol(p.position)]
    cell_type_name = p.cell_type_name
    dx = x[2:end] .- x[1:end-1]
    dy = y[2:end] .- y[1:end-1]
    dz = z[2:end] .- z[1:end-1]
    if direction == :x
        dist_fn = (dx, dy, dz) -> dx
    elseif direction == :y
        dist_fn = (dx, dy, dz) -> dy
    elseif direction == :z
        dist_fn = (dx, dy, dz) -> dz
    elseif direction == :any
        dist_fn = (dx, dy, dz) -> sqrt(dx ^ 2 + dy ^ 2 + dz ^ 2)
    else
        error("Invalid direction: $direction")
    end
    type_change = cell_type_name[2:end] .!= cell_type_name[1:end-1]
    start_ind = 1
    cell_type_names = unique(cell_type_name)
    distance_dict = Dict{String, Float64}(zip(cell_type_names, zeros(Float64, length(cell_type_names))))
    time_dict = Dict{String, Float64}(zip(cell_type_names, zeros(Float64, length(cell_type_names))))
    while start_ind <= length(type_change) 
        I = findfirst(type_change[start_ind:end]) # from s to I, cell_type_name is constant. at I+1 it changes
        I = isnothing(I) ? length(type_change)+2-start_ind : I # if the cell_type_name is constant till the end, set I to be at the end
        # If start_ind = 1 (at start of sim) and I = 2 (so cell_type_name[3] != cell_type_name[2], meaning that for steps [1,2] cell_type_name is constnat), only use dx in stepping from 1->2 since somewhere in 2->3 the type changes. That is, use dx[1]
        distance_dict[cell_type_name[start_ind]] += sum(dist_fn.(dx[start_ind:I-1], dy[start_ind:I-1], dz[start_ind:I-1]))  # only count distance travelled while remaining in the initial cell_type_name
        time_dict[cell_type_name[start_ind]] += p.time[start_ind+I-1] - p.time[start_ind] # record time spent in this cell_type_name (note p.time is not diffs like dx and dy are, hence the difference in indices)
        start_ind += I # advance the start to the first instance of a new cell_type_name
    end
    speed_dict = [k => distance_dict[k] / time_dict[k] for k in cell_type_names] |> Dict{String,Float64} # convert to speed
    return speed_dict, distance_dict, time_dict
end

function computeMeanSpeed(folder::String; direction=:any)::NTuple{3,Vector{Dict{String,Float64}}}
    sequence = PhysiCellSequence(folder)
    pos = getCellPositionSequence(sequence; include_dead=false, include_cell_type=true)
    dicts = [meanSpeed(p; direction=direction) for p in values(pos) if length(p.time) > 1]
    return [dict[1] for dict in dicts], [dict[2] for dict in dicts], [dict[3] for dict in dicts]
end

function computeMeanSpeed(simulation_id::Int; direction=:any)::NTuple{3,Vector{Dict{String,Float64}}}
    return joinpath(data_dir, "outputs", "simulations", string(simulation_id), "output") |> x -> computeMeanSpeed(x; direction=direction)
end

function computeMeanSpeed(class_id::Union{VCTClassID,AbstractTrial}; direction=:any)
    simulation_ids = getSimulationIDs(class_id)
    return [simulation_id => computeMeanSpeed(simulation_id; direction=direction) for simulation_id in simulation_ids] |> Dict
end