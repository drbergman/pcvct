function recordSimulationIDs(monad_id::Int, simulation_ids::Array{Int})
    path_to_folder = "$(data_dir)/outputs/monads/$(monad_id)/"
    mkpath(path_to_folder)
    path_to_csv = "$(path_to_folder)/simulations.csv"
    lines_table = compressSimulationIDs(simulation_ids)
    CSV.write(path_to_csv, lines_table; writeheader=false)
end

recordSimulationIDs(monad::Monad) = recordSimulationIDs(monad.id, monad.simulation_ids)

function recordMonadIDs(sampling_id::Int, monad_ids::Array{Int})
    path_to_folder = "$(data_dir)/outputs/samplings/$(sampling_id)/"
    mkpath(path_to_folder)
    path_to_csv = "$(path_to_folder)/monads.csv"
    lines_table = compressMonadIDs(monad_ids)
    CSV.write(path_to_csv, lines_table; writeheader=false)
end

recordMonadIDs(sampling::Sampling) = recordMonadIDs(sampling.id, sampling.monad_ids)

function recordSamplingIDs(trial_id::Int, sampling_ids::Array{Int})
    recordSamplingIDs("$(data_dir)/outputs/trials/$(trial_id)", sampling_ids)
end

function recordSamplingIDs(trial::Trial)
    recordSamplingIDs("$(data_dir)/outputs/trials/$(trial.id)", trial.sampling_ids)
end

function recordSamplingIDs(path_to_folder::String, sampling_ids::Array{Int})
    path_to_csv = "$(path_to_folder)/samplings.csv"
    lines_table = compressSamplingIDs(sampling_ids)
    CSV.write(path_to_csv, lines_table; writeheader=false)
end

################## Compression Functions ##################

function compressIDs(ids::Vector{Int})
    lines = String[]
    while !isempty(ids) # while there are still ids to compress
        if length(ids) == 1 # if there's only one id left
            next_line = string(ids[1]) # just add it to the list
            popfirst!(ids) # and remove it from the list of ids
        else # if there's more than one id left
            I = findfirst(diff(ids) .!= 1) # find the first index where the difference between consecutive ids is greater than 1
            I = isnothing(I) ? length(ids) : I # if none found, then all the diffs are 1 so we want to take the entire list
            if I > 1 # if compressing multiple ids
                next_line = "$(ids[1]):$(ids[I])" # add the first and last id separated by a colon
                ids = ids[I+1:end] # remove the ids that were just compressed
            else # if only compressing one id
                next_line = string(ids[1]) # just add the id to the list
                popfirst!(ids) # and remove it from the list of ids
            end
        end
        push!(lines, next_line) # add the compressed id(s) to the list of lines
    end
    return Tables.table(lines)
end

compressSimulationIDs(simulation_ids::Array{Int}) = simulation_ids |> vec |> unique |> sort |> compressIDs
compressMonadIDs(monad_ids::Array{Int}) = monad_ids |> vec |> unique |> sort |> compressIDs
compressSamplingIDs(sampling_ids::Array{Int}) = sampling_ids |> vec |> unique |> sort |> compressIDs
