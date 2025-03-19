function recordIDs(path_to_folder::String, filename::String, ids::Array{Int})
    mkpath(path_to_folder)
    path_to_csv = joinpath(path_to_folder, "$(filename).csv")
    lines_table = compressIDs(ids)
    CSV.write(path_to_csv, lines_table; header=false)
end

function recordSimulationIDs(monad_id::Int, simulation_ids::Array{Int})
    path_to_folder = trialFolder("monad", monad_id)
    recordIDs(path_to_folder, "simulations", simulation_ids)
end

recordSimulationIDs(monad::Monad, simulation_ids::AbstractArray{Int}) = recordSimulationIDs(monad.id, simulation_ids)

function recordMonadIDs(sampling_id::Int, monad_ids::Array{Int})
    path_to_folder = trialFolder("sampling", sampling_id)
    recordIDs(path_to_folder, "monads", monad_ids)
end

function recordSamplingIDs(trial_id::Int, sampling_ids::Array{Int})
    recordSamplingIDs(trialFolder("trial", trial_id), sampling_ids)
end

function recordSamplingIDs(path_to_folder::String, sampling_ids::Array{Int})
    recordIDs(path_to_folder, "samplings", sampling_ids)
end

################## Compression Functions ##################

function compressIDs(ids::AbstractArray{Int})
    ids = ids |> vec |> unique |> sort
    lines = String[]
    while !isempty(ids) #! while there are still ids to compress
        if length(ids) == 1 #! if there's only one id left
            next_line = string(ids[1]) #! just add it to the list
            popfirst!(ids) #! and remove it from the list of ids
        else #! if there's more than one id left
            I = findfirst(diff(ids) .!= 1) #! find the first index where the difference between consecutive ids is greater than 1
            I = isnothing(I) ? length(ids) : I #! if none found, then all the diffs are 1 so we want to take the entire list
            if I > 1 #! if compressing multiple ids
                next_line = "$(ids[1]):$(ids[I])" #! add the first and last id separated by a colon
                ids = ids[I+1:end] #! remove the ids that were just compressed
            else #! if only compressing one id
                next_line = string(ids[1]) #! just add the id to the list
                popfirst!(ids) #! and remove it from the list of ids
            end
        end
        push!(lines, next_line) #! add the compressed id(s) to the list of lines
    end
    return Tables.table(lines)
end
