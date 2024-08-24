
function deleteSimulation(simulation_ids::Vector{Int}; delete_supers::Bool=true, and_constraints::String="")
    where_stmt = "WHERE simulation_id IN ($(join(simulation_ids,","))) $(and_constraints);"
    sim_df = constructSelectQuery("simulations", where_stmt) |> queryToDataFrame
    simulation_ids = sim_df.simulation_id # update based on the constraints added
    DBInterface.execute(db,"DELETE FROM simulations WHERE simulation_id IN ($(join(simulation_ids,",")));")
    for row in eachrow(sim_df)
        rm("$(data_dir)/outputs/simulations/$(row.simulation_id)", force=true, recursive=true)
        config_folder = getConfigFolder(row.config_id)
        result_df = constructSelectQuery(
            "simulations",
            "WHERE config_id = $(row.config_id) AND variation_id = $(row.variation_id);";
            selection="COUNT(*)"
        ) |> queryToDataFrame
        if result_df.var"COUNT(*)"[1] == 0
            rm("$(data_dir)/inputs/configs/$(config_folder)/variations/variation_$(row.variation_id).xml", force=true)
        end

        rulesets_collection_folder = getRulesetsCollectionFolder(row.rulesets_collection_id)
        result_df = constructSelectQuery(
            "simulations",
            "WHERE rulesets_collection_id = $(row.rulesets_collection_id) AND rulesets_variation_id = $(row.rulesets_variation_id);";
            selection="COUNT(*)"
        ) |> queryToDataFrame
        if result_df.var"COUNT(*)"[1] == 0
            rm("$(data_dir)/inputs/rulesets_collections/$(rulesets_collection_folder)/rulesets_collections_variations/rulesets_variation_$(row.rulesets_variation_id).xml", force=true)
        end
    end

    if !delete_supers
        return nothing
    end

    monad_ids = constructSelectQuery("monads", "", selection="monad_id") |> queryToDataFrame |> x -> x.monad_id
    monad_ids_to_delete = Int[]
    for monad_id in monad_ids
        monad_simulation_ids = getMonadSimulations(monad_id)
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
deleteAllSimulations(; delete_supers::Bool=true, and_constraints::String="") = getSimulations() |> x -> deleteSimulation(x; delete_supers=delete_supers, and_constraints=and_constraints)

function deleteMonad(monad_ids::Vector{Int}; delete_subs::Bool=true, delete_supers::Bool=true)
    DBInterface.execute(db,"DELETE FROM monads WHERE monad_id IN ($(join(monad_ids,",")));")
    simulation_ids_to_delete = Int[]
    for monad_id in monad_ids
        if delete_subs
            append!(simulation_ids_to_delete, getMonadSimulations(monad_id))
        end
        rm("$(data_dir)/outputs/monads/$(monad_id)", force=true, recursive=true)
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
        sampling_monad_ids = getSamplingMonads(sampling_id)
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
            append!(monad_ids_to_delete, getSamplingMonads(sampling_id))
        end
        rm("$(data_dir)/outputs/samplings/$(sampling_id)", force=true, recursive=true)
    end
    if !isempty(monad_ids_to_delete)
        all_sampling_ids = constructSelectQuery("samplings", "", selection="sampling_id") |> queryToDataFrame |> x -> x.sampling_id
        for sampling_id in all_sampling_ids
            if sampling_id in sampling_ids
                continue # skip the samplings to be deleted (we want to delete their monads)
            end
            # this is then a sampling that we are not deleting, do not delete their monads!!
            monad_ids = getSamplingMonads(sampling_id)
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
        trial_sampling_ids = getTrialSamplings(trial_id)
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
            append!(sampling_ids_to_delete, getTrialSamplings(trial_id))
        end
        rm("$(data_dir)/outputs/trials/$(trial_id)", force=true, recursive=true)
    end
    if !isempty(sampling_ids_to_delete)
        all_trial_ids = constructSelectQuery("trials", "", selection="trial_id") |> queryToDataFrame |> x -> x.trial_id
        for trial_id in all_trial_ids
            if trial_id in trial_ids
                continue # skip the trials to be deleted (we want to delete their samplings)
            end
            # this is then a trial that we are not deleting, do not delete their samplings!!
            sampling_ids = getTrialSamplings(trial_id)
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
    rm("$(data_dir)/outputs/simulations", force=true, recursive=true)
    rm("$(data_dir)/outputs/monads", force=true, recursive=true)
    rm("$(data_dir)/outputs/samplings", force=true, recursive=true)
    rm("$(data_dir)/outputs/trials", force=true, recursive=true)

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
        rm("$(custom_code_folder)/project", force=true)
        rm("$(custom_code_folder)/compilation.log", force=true)
        rm("$(custom_code_folder)/compilation.err", force=true)
        rm("$(custom_code_folder)/macros.txt", force=true)
    end

    custom_code_folders = constructSelectQuery("custom_codes", "", selection="folder_name") |> queryToDataFrame |> x -> x.folder_name
    for custom_code_folder in custom_code_folders
        rm("$(data_dir)/inputs/custom_codes/$(custom_code_folder)/project", force=true)
    end

    if db.file == ":memory:"
        initializeDatabase()
    else
        rm("$(db.file)", force=true)
        initializeDatabase("$(db.file)")
    end
    return nothing
end

function resetConfigFolder(path_to_config_folder::String)
    if !isdir(path_to_config_folder)
        return
    end
    rm("$(path_to_config_folder)/variations.db", force=true)
    rm("$(path_to_config_folder)/variations", force=true, recursive=true)
end

function resetRulesetsCollectionFolder(path_to_rulesets_collection_folder::String)
    if !isdir(path_to_rulesets_collection_folder)
        return
    end
    rm("$(path_to_rulesets_collection_folder)/rulesets_variations.db", force=true)
    rm("$(path_to_rulesets_collection_folder)/rulesets_collections_variations", force=true, recursive=true)
end

function deleteStalledSimulations(; user_check::Bool=true)
    if user_check
        println("Are you sure you want to delete all unfinished simulations? This could delete queued simulations as well. (y/n)")
        response = readline()
        if response != "y" # make user be very specific about resetting
            println("You entered '$response'.\n\tDeleting unfinished simulations has been cancelled.")
            return
        end
    end

    # simulation folder OR in the database
    all_simulation_ids = (readdir("$(data_dir)/outputs/simulations", join=true) |> filter(x->isdir(x)) .|> x->parse(Int,basename(x))) ∪ getSimulations()

    id_check_fn(id) = getStatus(VCTClassID{Simulation}(id)) == :finished && !isfile("$(data_dir)/outputs/simulations/$(id)/output/final.xml")
    stalled_simulation_ids = [id for id in all_simulation_ids if id_check_fn(id)]

    deleteSimulation(stalled_simulation_ids)
end

function getStatus(class_id::VCTClassID)
    class_id_type = getVCTClassIDType(class_id)
    if class_id_type == Simulation
        return :finished
        # simulation_id = class_id.id
        # if !isdir("$(data_dir)/outputs/simulations/$(simulation_id)/output")
        #     return :queued
        # else
        #     return :finished
        # end
    else
        error("Only Simulation class ids are supported for calling getStatus on.")
    end
end