function runSimulation(simulation::Simulation; monad_id::Union{Missing,Int}=missing, do_full_setup::Bool=true, force_recompile::Bool=false, prune_options::PruneOptions=PruneOptions())
    DBInterface.execute(db,"UPDATE simulations SET status_code_id=$(getStatusCodeID("Running")) WHERE simulation_id=$(simulation.id);" )

    if ismissing(monad_id)
        monad = Monad(simulation)
        monad_id = monad.id
    end
    path_to_simulation_folder = joinpath(data_dir, "outputs", "simulations", string(simulation.id))
    path_to_simulation_output = joinpath(path_to_simulation_folder, "output")
    mkpath(path_to_simulation_output)

    if do_full_setup
        loadConfiguration(simulation)
        loadRulesets(simulation)
        loadICCells(simulation)
        loadCustomCode(simulation; force_recompile=force_recompile)
    end

    executable_str = joinpath(data_dir, "inputs", "custom_codes", simulation.folder_names.custom_code_folder, baseToExecutable("project")) # path to executable
    config_str = joinpath(data_dir, "inputs", "configs", simulation.folder_names.config_folder, "config_variations", "config_variation_$(simulation.variation_ids.config_variation_id).xml")
    flags = ["-o", path_to_simulation_output]
    if simulation.folder_ids.ic_cell_id != -1
        try
            append!(flags, ["-i", pathToICCell(simulation)])
        catch e
            println("\nWARNING: Simulation $(simulation.id) failed to initialize the IC cell file.\n\tCause: $e\n")
            DBInterface.execute(db,"UPDATE simulations SET status_code_id=$(getStatusCodeID("Failed")) WHERE simulation_id=$(simulation.id);" )
            eraseSimulationID(simulation.id; monad_id=monad_id)
            return false
        end
    end
    if simulation.folder_ids.ic_substrate_id != -1
        append!(flags, ["-s", joinpath(data_dir, "inputs", "ics", "substrates", simulation.folder_names.ic_substrate_folder, "substrates.csv")]) # if ic file included (id != -1), then include this in the command
    end
    if simulation.folder_ids.ic_ecm_id != -1
        append!(flags, ["-e", joinpath(data_dir, "inputs", "ics", "ecms", simulation.folder_names.ic_ecm_folder, "ecm.csv")]) # if ic file included (id != -1), then include this in the command
    end
    if simulation.variation_ids.rulesets_variation_id != -1
        path_to_rules_file = joinpath(data_dir, "inputs", "rulesets_collections", simulation.folder_names.rulesets_collection_folder, "rulesets_collections_variations", "rulesets_variation_$(simulation.variation_ids.rulesets_variation_id).xml")
        append!(flags, ["-r", path_to_rules_file])
    end
    cmd = `$executable_str $config_str $flags`
    println("\tRunning simulation: $(simulation.id)...")
    flush(stdout)
    success = false # create this here so the return statement handles it correctly
    try
        run(pipeline(cmd; stdout=joinpath(path_to_simulation_folder, "output.log"), stderr=joinpath(path_to_simulation_folder, "output.err")); wait=true)
    catch e
        println("\nWARNING: Simulation $(simulation.id) failed. Please check $(joinpath(path_to_simulation_folder, "output.err")) for more information.\n")
        # write the execution command to output.err
        lines = readlines(joinpath(path_to_simulation_folder, "output.err"))
        open(joinpath(path_to_simulation_folder, "output.err"), "w+") do io
            # read the lines of the output.err file
            println(io, "Execution command: $cmd")
            println(io, "\n---stderr from PhysiCell---")
            for line in lines
                println(io, line)
            end
        end
        DBInterface.execute(db,"UPDATE simulations SET status_code_id=$(getStatusCodeID("Failed")) WHERE simulation_id=$(simulation.id);" )
        success = false
        eraseSimulationID(simulation.id; monad_id=monad_id)
    else
        rm(joinpath(path_to_simulation_folder, "output.err"); force=true)
        DBInterface.execute(db,"UPDATE simulations SET status_code_id=$(getStatusCodeID("Completed")) WHERE simulation_id=$(simulation.id);" )
        success = true
    end

    pruneSimulationOutput(simulation; prune_options=prune_options)
    
    return success
end

function runMonad(monad::Monad; do_full_setup::Bool=true, force_recompile::Bool=false, prune_options=PruneOptions())
    mkpath(joinpath(data_dir, "outputs", "monads", string(monad.id)))

    if do_full_setup
        loadCustomCode(monad; force_recompile=force_recompile)
    end
    loadConfiguration(monad)
    loadRulesets(monad)
    loadICCells(monad)

    simulation_tasks = Task[]
    for simulation_id in monad.simulation_ids
        if isStarted(simulation_id; new_status_code="Queued")
            continue # if the simulation has already been started (or even completed), then don't run it again
        end
        simulation = Simulation(simulation_id)
       
        push!(simulation_tasks, @task runSimulation(simulation; monad_id=monad.id, do_full_setup=false, force_recompile=false, prune_options=prune_options))
    end

    return simulation_tasks
end

function runSampling(sampling::Sampling; force_recompile::Bool=false, prune_options::PruneOptions=PruneOptions())
    mkpath(joinpath(data_dir, "outputs", "samplings", string(sampling.id)))

    loadCustomCode(sampling; force_recompile=force_recompile)
    simulation_tasks = []
    for index in eachindex(sampling.variation_ids)
        monad = Monad(sampling, index) # instantiate a monad with the variation_id and the simulation ids already found
        append!(simulation_tasks, runMonad(monad, do_full_setup=false, force_recompile=false, prune_options=prune_options)) # run the monad and add the number of new simulations to the total
    end

    return simulation_tasks
end

function runTrial(trial::Trial; force_recompile::Bool=true, prune_options::PruneOptions=PruneOptions())
    mkpath(joinpath(data_dir, "outputs", "trials", string(trial.id)))

    simulation_tasks = []
    for i in eachindex(trial.sampling_ids)
        sampling = Sampling(trial, i) # instantiate a sampling with the variation_ids and the simulation ids already found
        append!(simulation_tasks, runSampling(sampling; force_recompile=force_recompile, prune_options=prune_options)) # run the sampling and add the number of new simulations to the total
    end

    return simulation_tasks
end

collectSimulationTasks(simulation::Simulation; force_recompile::Bool=false, prune_options::PruneOptions=PruneOptions()) = [@task runSimulation(simulation; do_full_setup=true, force_recompile=force_recompile, prune_options=prune_options)]
collectSimulationTasks(monad::Monad; force_recompile::Bool=false, prune_options::PruneOptions=PruneOptions()) = runMonad(monad; do_full_setup=true, force_recompile=force_recompile, prune_options=prune_options)
collectSimulationTasks(sampling::Sampling; force_recompile::Bool=false, prune_options::PruneOptions=PruneOptions()) = runSampling(sampling; force_recompile=force_recompile, prune_options=prune_options)
collectSimulationTasks(trial::Trial; force_recompile::Bool=false, prune_options::PruneOptions=PruneOptions()) = runTrial(trial; force_recompile=force_recompile, prune_options=prune_options)

function runAbstractTrial(T::AbstractTrial; force_recompile::Bool=true, prune_options::PruneOptions=PruneOptions())
    cd(()->run(pipeline(`make clean`; stdout=devnull)), physicell_dir) # remove all *.o files so that a future recompile will re-compile all the files

    simulation_tasks = collectSimulationTasks(T; force_recompile=force_recompile, prune_options=prune_options)
    n_success = Threads.Atomic{Int}(0)

    println("Running $(typeof(T)) $(T.id) requiring $(length(simulation_tasks)) simulations...")

    Threads.@threads :static for simulation_task in simulation_tasks
        schedule(simulation_task)
        success = fetch(simulation_task)

        # prevent data races on n_success
        success ? Threads.atomic_add!(n_success, 1) : nothing # shorthand for add 1 if success is true
    end

    n_asterisks = 1
    asterisks = Dict{String, Int}()
    size_T = length(T)
    println("Finished $(typeof(T)) $(T.id).")
    println("\t- Consists of $(size_T) simulations.")
    print(  "\t- Scheduled $(length(simulation_tasks)) simulations to complete this $(typeof(T)).")
    print_low_schedule_message = length(simulation_tasks) < size_T
    if print_low_schedule_message
        println(" ($(repeat("*", n_asterisks)))")
        asterisks["low_schedule_message"] = n_asterisks
        n_asterisks += 1
    else
        println()
    end
    print(  "\t- Successful completion of $(n_success[]) simulations.")
    print_low_success_warning = n_success[] < length(simulation_tasks)
    if print_low_success_warning
        println(" ($(repeat("*", n_asterisks)))")
        asterisks["low_success_warning"] = n_asterisks
        n_asterisks += 1 # in case something gets added later
    else
        println()
    end
    if print_low_schedule_message
        println("\n($(repeat("*", asterisks["low_schedule_message"]))) pcvct found matching simulations and will save you time by not re-running them!")
    end
    if print_low_success_warning
        println("\n($(repeat("*", asterisks["low_success_warning"]))) Some simulations did not complete successfully. Check the output.err files for more information.")
    end
    println("\n--------------------------------------------------\n")
    return n_success[]
end