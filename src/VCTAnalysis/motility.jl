export getCellPositionSequence, computeMeanSpeed

"""
    getCellPositionSequence(sequence::PhysiCellSequence; include_dead::Bool=false, include_cell_type::Bool=false)

Return a dictionary where the keys are cell IDs from the PhysiCell simulation and the values are NamedTuples containing the time and the position of the cell.

This is a convenience function for `getCellDataSequence(sequence, "position"; include_dead=include_dead, include_cell_type=include_cell_type)`.
"""
function getCellPositionSequence(sequence::PhysiCellSequence; include_dead::Bool=false, include_cell_type::Bool=false)
    return getCellDataSequence(sequence, "position"; include_dead=include_dead, include_cell_type=include_cell_type)
end

function meanSpeed(p; direction=:any)::NTuple{3,Dict{String,Float64}}
    x, y, z = [col for col in eachcol(p.position)]
    cell_type_name = p.cell_type_name
    dx = x[2:end] .- x[1:end-1]
    dy = y[2:end] .- y[1:end-1]
    dz = z[2:end] .- z[1:end-1]
    if direction == :x
        dist_fn = (dx, dy, dz) -> abs(dx)
    elseif direction == :y
        dist_fn = (dx, dy, dz) -> abs(dy)
    elseif direction == :z
        dist_fn = (dx, dy, dz) -> abs(dz)
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
    sequence = PhysiCellSequence(folder; include_cells=true)
    pos = getCellPositionSequence(sequence; include_dead=false, include_cell_type=true)
    dicts = [meanSpeed(p; direction=direction) for p in values(pos) if length(p.time) > 1]
    return [dict[1] for dict in dicts], [dict[2] for dict in dicts], [dict[3] for dict in dicts]
end

"""
    computeMeanSpeed(simulation_id::Integer[; direction=:any])

Return dictionaries containing the mean speed, total distance traveled, and total time spent for each cell type in the PhysiCell simulation.

The time is counted from when the cell first appears in simulation output until it dies or the simulation ends, whichever comes first.

To account for cells that may change cell type during the simulation, the dictionaries returned are keyed by cell type.
So, a dictionary with key "A" and value 2.0 indicates that the mean speed of this cell while it was of type "A" is 2.0.

# Arguments
- `simulation_id::Integer`: The ID of the PhysiCell simulation.
- `direction::Symbol`: The direction to compute the mean speed. Can be `:x`, `:y`, `:z`, or `:any` (default). If `:x`, for example, the mean speed is calculated using only the x component of the cell's movement.

# Returns
- `mean_speed_dicts::Vector{Dict{String,Float64}}`: A vector of dictionaries where each dictionary is specific to a single cell. The key is the cell type and the value is the mean speed of that cell.
- `distance_dicts::Vector{Dict{String,Float64}}`: A vector of dictionaries where each dictionary is specific to a single cell. The key is the cell type and the value is the total distance traveled by that cell.
- `time_dicts::Vector{Dict{String,Float64}}`: A vector of dictionaries where each dictionary is specific to a single cell. The key is the cell type and the value is the total time in the simulation for that cell.
"""
function computeMeanSpeed(simulation_id::Integer; direction=:any)::NTuple{3,Vector{Dict{String,Float64}}}
    return joinpath(outputFolder("simulation", simulation_id), "output") |> x -> computeMeanSpeed(x; direction=direction)
end