
function deleteSimulation(simulation_ids::Vector{Int}; delete_supers::Bool=true, and_constraints::String="")
    where_stmt = "WHERE simulation_id IN ($(join(simulation_ids,","))) $(and_constraints);"
    sim_df = constructSelectQuery("simulations", where_stmt) |> queryToDataFrame
    simulation_ids = sim_df.simulation_id # update based on the constraints added
    DBInterface.execute(db,"DELETE FROM simulations WHERE simulation_id IN ($(join(simulation_ids,",")));")
    for row in eachrow(sim_df)
        rm("$(data_dir)/outputs/simulations/$(row.simulation_id)"; force=true, recursive=true)
        config_folder = getConfigFolder(row.config_id)
        result_df = constructSelectQuery(
            "simulations",
            "WHERE config_id = $(row.config_id) AND variation_id = $(row.variation_id);";
            selection="COUNT(*)"
        ) |> queryToDataFrame
        if result_df.var"COUNT(*)"[1] == 0
            rm("$(data_dir)/inputs/configs/$(config_folder)/variations/variation_$(row.variation_id).xml"; force=true)
        end

        rulesets_collection_folder = getRulesetsCollectionFolder(row.rulesets_collection_id)
        result_df = constructSelectQuery(
            "simulations",
            "WHERE rulesets_collection_id = $(row.rulesets_collection_id) AND rulesets_variation_id = $(row.rulesets_variation_id);";
            selection="COUNT(*)"
        ) |> queryToDataFrame
        if result_df.var"COUNT(*)"[1] == 0
            rm("$(data_dir)/inputs/rulesets_collections/$(rulesets_collection_folder)/rulesets_collections_variations/rulesets_variation_$(row.rulesets_variation_id).xml"; force=true)
        end
    end

    if !delete_supers
        return nothing
    end

    monad_ids = constructSelectQuery("monads", "", selection="monad_id") |> queryToDataFrame |> x -> x.monad_id
    monad_ids_to_delete = Int[]
    for monad_id in monad_ids
        monad_simulation_ids = readMonadSimulationIDs(monad_id)
        if !any(x -> x in simulation_ids, monad_simulation_ids) # if none of the monad simulation ids are among those to be deleted, then nothing to do here
            continue
        end
        filter!(x -> !(x in simulation_ids), monad_simulation_ids)
        if isempty(monad_simulation_ids)
            push!(monad_ids_to_delete, monad_id)
        else
            recordSimulationIDs(monad_id, monad_simulation_ids)
        end
    end
    if !isempty(monad_ids_to_delete)
        deleteMonad(monad_ids_to_delete; delete_subs=false, delete_supers=true)
    end
    return nothing
end

deleteSimulation(simulation_id::Int; delete_supers::Bool=true, and_constraints::String="") = deleteSimulation([simulation_id]; delete_supers=delete_supers, and_constraints=and_constraints)
deleteAllSimulations(; delete_supers::Bool=true, and_constraints::String="") = getSimulationIDs() |> x -> deleteSimulation(x; delete_supers=delete_supers, and_constraints=and_constraints)

function deleteMonad(monad_ids::Vector{Int}; delete_subs::Bool=true, delete_supers::Bool=true)
    DBInterface.execute(db,"DELETE FROM monads WHERE monad_id IN ($(join(monad_ids,",")));")
    simulation_ids_to_delete = Int[]
    for monad_id in monad_ids
        if delete_subs
            append!(simulation_ids_to_delete, readMonadSimulationIDs(monad_id))
        end
        rm("$(data_dir)/outputs/monads/$(monad_id)"; force=true, recursive=true)
    end
    if !isempty(simulation_ids_to_delete)
        deleteSimulation(simulation_ids_to_delete; delete_supers=false)
    end

    if !delete_supers
        return nothing
    end

    sampling_ids = constructSelectQuery("samplings", "", selection="sampling_id") |> queryToDataFrame |> x -> x.sampling_id
    sampling_ids_to_delete = Int[]
    for sampling_id in sampling_ids
        sampling_monad_ids = readSamplingMonadIDs(sampling_id)
        if !any(x -> x in monad_ids, sampling_monad_ids) # if none of the sampling monad ids are among those to be deleted, then nothing to do here
            continue
        end
        filter!(x -> !(x in monad_ids), sampling_monad_ids)
        if isempty(sampling_monad_ids)
            push!(sampling_ids_to_delete, sampling_id)
        else
            recordMonadIDs(sampling_id, sampling_monad_ids)
        end
    end
    if !isempty(sampling_ids_to_delete)
        deleteSampling(sampling_ids_to_delete; delete_subs=false, delete_supers=true)
    end
    return nothing
end

deleteMonad(monad_id::Int; delete_subs::Bool=true, delete_supers::Bool=true) = deleteMonad([monad_id]; delete_subs=delete_subs, delete_supers=delete_supers)

function deleteSampling(sampling_ids::Vector{Int}; delete_subs::Bool=true, delete_supers::Bool=true)
    DBInterface.execute(db,"DELETE FROM samplings WHERE sampling_id IN ($(join(sampling_ids,",")));")
    monad_ids_to_delete = Int[]
    for sampling_id in sampling_ids
        if delete_subs
            append!(monad_ids_to_delete, readSamplingMonadIDs(sampling_id))
        end
        rm("$(data_dir)/outputs/samplings/$(sampling_id)"; force=true, recursive=true)
    end
    if !isempty(monad_ids_to_delete)
        all_sampling_ids = constructSelectQuery("samplings", "", selection="sampling_id") |> queryToDataFrame |> x -> x.sampling_id
        for sampling_id in all_sampling_ids
            if sampling_id in sampling_ids
                continue # skip the samplings to be deleted (we want to delete their monads)
            end
            # this is then a sampling that we are not deleting, do not delete their monads!!
            monad_ids = readSamplingMonadIDs(sampling_id)
            filter!(x -> !(x in monad_ids), monad_ids_to_delete) # if a monad to delete is in the sampling to keep, then do not delete it!! (or more in line with logic here: if a monad marked for deletion is not in this sampling we are keeping, then leave it in the deletion list)
        end
        deleteMonad(monad_ids_to_delete; delete_subs=true, delete_supers=false)
    end

    if !delete_supers
        return nothing
    end

    trial_ids = constructSelectQuery("trials", "", selection="trial_id") |> queryToDataFrame |> x -> x.trial_id
    trial_ids_to_delete = Int[]
    for trial_id in trial_ids
        trial_sampling_ids = readTrialSamplingIDs(trial_id)
        if !any(x -> x in sampling_ids, trial_sampling_ids) # if none of the trial sampling ids are among those to be deleted, then nothing to do here
            continue
        end
        filter!(x -> !(x in sampling_ids), trial_sampling_ids)
        if isempty(trial_sampling_ids)
            push!(trial_ids_to_delete, trial_id)
        else
            recordSamplingIDs(trial_id, trial_sampling_ids)
        end
    end
    if !isempty(trial_ids_to_delete)
        deleteTrial(trial_ids_to_delete; delete_subs=false)
    end
    return nothing
end

deleteSampling(sampling_id::Int; delete_subs::Bool=true, delete_supers::Bool=true) = deleteSampling([sampling_id]; delete_subs=delete_subs, delete_supers=delete_supers)

function deleteTrial(trial_ids::Vector{Int}; delete_subs::Bool=true)
    DBInterface.execute(db,"DELETE FROM trials WHERE trial_id IN ($(join(trial_ids,",")));")
    sampling_ids_to_delete = Int[]
    for trial_id in trial_ids
        if delete_subs
            append!(sampling_ids_to_delete, readTrialSamplingIDs(trial_id))
        end
        rm("$(data_dir)/outputs/trials/$(trial_id)"; force=true, recursive=true)
    end
    if !isempty(sampling_ids_to_delete)
        all_trial_ids = constructSelectQuery("trials", "", selection="trial_id") |> queryToDataFrame |> x -> x.trial_id
        for trial_id in all_trial_ids
            if trial_id in trial_ids
                continue # skip the trials to be deleted (we want to delete their samplings)
            end
            # this is then a trial that we are not deleting, do not delete their samplings!!
            sampling_ids = readTrialSamplingIDs(trial_id)
            filter!(x -> !(x in sampling_ids), sampling_ids_to_delete) # if a sampling to delete is in the trial to keep, then do not delete it!! (or more in line with logic here: if a sampling marked for deletion is not in this trial we are keeping, then leave it in the deletion list)
        end
        deleteSampling(sampling_ids_to_delete; delete_subs=true, delete_supers=false)
    end
    return nothing
end

deleteTrial(trial_id::Int; delete_subs::Bool=true) = deleteTrial([trial_id]; delete_subs=delete_subs)

function resetDatabase(; force_reset::Bool=false, force_continue::Bool=false)
    if !force_reset
        # prompt user to confirm
        println("Are you sure you want to reset the database? (y/n)")
        response = readline()
        if response != "y" # make user be very specific about resetting
            println("\tYou entered '$response'.\n\tResetting the database has been cancelled.")
            if !force_continue
                println("\nDo you want to continue with the script? (y/n)")
                response = readline()
                if response != "y" # make user be very specific about continuing
                    println("\tYou entered '$response'.\n\tThe script has been cancelled.")
                    error("Script cancelled.")
                end
                println("You entered '$response'.\n\tThe script will continue.")
            end
            return
        end
    end
    for folder in ["simulations", "monads", "samplings", "trials"]
        rm("$(data_dir)/outputs/$(folder)"; force=true, recursive=true)
    end

    for config_folder in (readdir("$(data_dir)/inputs/configs/", sort=false, join=true) |> filter(x->isdir(x)))
        resetConfigFolder(config_folder)
    end
    
    config_folders = constructSelectQuery("configs", "", selection="folder_name") |> queryToDataFrame |> x -> x.folder_name
    for config_folder in config_folders
        resetConfigFolder("$(data_dir)/inputs/configs/$(config_folder)")
    end

    for path_to_rulesets_collection_folder in (readdir("$(data_dir)/inputs/rulesets_collections/", sort=false, join=true) |> filter(x->isdir(x)))
        resetRulesetsCollectionFolder(path_to_rulesets_collection_folder)
    end

    rulesets_collection_folders = constructSelectQuery("rulesets_collections", "", selection="folder_name") |> queryToDataFrame |> x -> x.folder_name
    for rulesets_collection_folder in rulesets_collection_folders
        resetRulesetsCollectionFolder("$(data_dir)/inputs/rulesets_collections/$(rulesets_collection_folder)")
    end

    for custom_code_folder in (readdir("$(data_dir)/inputs/custom_codes/", sort=false, join=true) |> filter(x->isdir(x)))
        files = ["project", "compilation.log", "compilation.err", "macros.txt"]
        for file in files
            rm("$(custom_code_folder)/$(file)"; force=true)
        end
    end

    custom_code_folders = constructSelectQuery("custom_codes", "", selection="folder_name") |> queryToDataFrame |> x -> x.folder_name
    for custom_code_folder in custom_code_folders
        rm("$(data_dir)/inputs/custom_codes/$(custom_code_folder)/project"; force=true)
    end

    if db.file == ":memory:"
        initializeDatabase()
    else
        rm("$(db.file)"; force=true)
        initializeDatabase("$(db.file)")
    end
    return nothing
end

function resetConfigFolder(path_to_config_folder::String)
    if !isdir(path_to_config_folder)
        return
    end
    rm("$(path_to_config_folder)/variations.db"; force=true)
    rm("$(path_to_config_folder)/variations"; force=true, recursive=true)
end

function resetRulesetsCollectionFolder(path_to_rulesets_collection_folder::String)
    if !isdir(path_to_rulesets_collection_folder)
        return
    end
    rm("$(path_to_rulesets_collection_folder)/rulesets_variations.db"; force=true)
    rm("$(path_to_rulesets_collection_folder)/rulesets_collections_variations"; force=true, recursive=true)
end

"""
    deleteStalledSimulationsByStatus(status_codes_to_delete::Vector{String}=["Failed"]; user_check::Bool=true)

    Delete simulations from the database based on their status codes.

    # Arguments
    - `status_codes_to_delete::Vector{String}`: A vector of status codes for which simulations should be deleted. Default is `["Failed"]`.
    - `user_check::Bool`: If `true`, prompts the user for confirmation before deleting simulations. Default is `true`.

    # Description
    This function performs the following steps:
    1. Queries the database to retrieve simulation IDs and their corresponding status codes.
    2. Iterates over the provided `status_codes_to_delete`.
    3. For each status code, retrieves the simulation IDs that match the status code.
    4. If no simulations match the status code, it continues to the next status code.
    5. If `user_check` is `true`, prompts the user for confirmation before deleting the simulations.
    6. If the user confirms, deletes the simulations with the matching status code.

    # Returns
    - Nothing. The function performs database operations and deletes records as needed.
"""
function deleteStalledSimulationsByStatus(status_codes_to_delete::Vector{String}=["Failed"]; user_check::Bool=true)
    df = """
        SELECT simulations.simulation_id, simulations.status_code_id, status_codes.status_code
        FROM simulations
        JOIN status_codes
        ON simulations.status_code_id = status_codes.status_code_id;
    """ |> queryToDataFrame

    for status_code in status_codes_to_delete
        simulation_ids = df.simulation_id[df.status_code .== status_code]
        if isempty(simulation_ids)
            continue
        end
        if user_check
            println("Are you sure you want to delete all $(length(simulation_ids)) simulations with status code '$status_code'? (y/n)")
            response = readline()
            if response != "y" # make user be very specific about resetting
                println("You entered '$response'.\n\tDeleting simulations with status code '$status_code' has been cancelled.")
                continue
            else
                println("You entered '$response'.")
            end
        end
        println("\tDeleting $(length(simulation_ids)) simulations with status code '$status_code'.")
        deleteSimulation(simulation_ids)
    end
end

"""
    eraseSimulationID(simulation_id::Int; monad_id::Union{Missing,Int}=missing, T::Union{Missing,AbstractTrial}=missing)

    Erase a simulation ID from the monad(s) it belongs to. Used when a simulation fails to run and needs to be removed from the monad's `simulations.csv`.

    # Arguments
    - `simulation_id::Int`: The ID of the simulation to be erased.
    - `monad_id::Union{Missing,Int}`: The ID of the monad associated with the simulation. If not provided, it will be inferred from the simulation ID. Default is `missing`.
    - `T::Union{Missing,AbstractTrial}`: An optional parameter for additional context. Default is `missing`.

    # Description
    This function performs the following steps:
    1. If `monad_id` is missing, it constructs a query to find the monad ID associated with the given `simulation_id`.
    2. Retrieves the list of simulation IDs associated with the monad.
    3. Finds the index of the given `simulation_id` in the list.
    4. If the `simulation_id` is not found, the function returns early.
    5. If the monad contains only the given `simulation_id`, it deletes the monad and any dependent records, but retains the simulation in the database for output file checks.
    6. If the monad contains multiple simulations, it removes the given `simulation_id` from the list and updates the records.

    # Returns
    - Nothing. The function performs database operations and updates records as needed.
"""
function eraseSimulationID(simulation_id::Int; monad_id::Union{Missing,Int}=missing, T::Union{Missing,AbstractTrial}=missing)
    if ismissing(monad_id)
        query = constructSelectQuery("simulations", "WHERE simulation_id = $(simulation_id);")
        df = queryToDataFrame(query)
        query = constructSelectQuery("monads", "WHERE (config_id, variation_id, rulesets_collection_id, rulesets_variation_id) = ($(df.config_id[1]), $(df.variation_id[1]), $(df.rulesets_collection_id[1]), $(df.rulesets_variation_id[1]));"; selection="monad_id")
        df = queryToDataFrame(query)
        monad_id = df.monad_id[1]
    end
    simulation_ids = readMonadSimulationIDs(monad_id)
    index = findfirst(x->x==simulation_id, simulation_ids)
    if isnothing(index)
        return # maybe this could happen? so let's check just in case
    end
    if length(simulation_ids)==1
        # then this was the only simulation in this monad; delete the monad and any samplings, etc. that depend on it
        # do not delete the given simulation from the database so that we can check the output files
        deleteMonad(monad_id; delete_subs=false, delete_supers=true)
        return
    end
    deleteat!(simulation_ids, index)
    recordSimulationIDs(monad_id, simulation_ids)
end