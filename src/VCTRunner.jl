function runSimulation(simulation::Simulation; do_full_setup::Bool=true, force_recompile::Bool=false)
    path_to_simulation_folder = "$(data_dir)/outputs/simulations/$(simulation.id)"
    path_to_simulation_output = "$(path_to_simulation_folder)/output"
    if isfile("$(path_to_simulation_output)/final.xml")
        ran = false
        success = true
        return ran, success
    end
    mkpath(path_to_simulation_output)

    if do_full_setup
        loadConfiguration(simulation)
        loadRulesets(simulation)
        loadCustomCode(simulation; force_recompile=force_recompile)
    end

    executable_str = "$(data_dir)/inputs/custom_codes/$(simulation.folder_names.custom_code_folder)/project" # path to executable
    config_str =  "$(data_dir)/inputs/configs/$(simulation.folder_names.config_folder)/variations/variation_$(simulation.variation_id).xml" # path to config file
    flags = ["-o", path_to_simulation_output]
    if simulation.folder_ids.ic_cell_id != -1
        append!(flags, ["-i", "$(data_dir)/inputs/ics/cells/$(simulation.folder_names.ic_cell_folder)/cells.csv"]) # if ic file included (id != -1), then include this in the command
    end
    if simulation.folder_ids.ic_substrate_id != -1
        append!(flags, ["-s", "$(data_dir)/inputs/ics/substrates/$(simulation.folder_names.ic_substrate_folder)/substrates.csv"]) # if ic file included (id != -1), then include this in the command
    end
    if simulation.folder_ids.ic_ecm_id != -1
        append!(flags, ["-e", "$(data_dir)/inputs/ics/ecms/$(simulation.folder_names.ic_ecm_folder)/ecm.csv"]) # if ic file included (id != -1), then include this in the command
    end
    if simulation.rulesets_variation_id != -1
        path_to_rules_file = "$(data_dir)/inputs/rulesets_collections/$(simulation.folder_names.rulesets_collection_folder)/rulesets_collections_variations/rulesets_variation_$(simulation.rulesets_variation_id).xml"
        append!(flags, ["-r", path_to_rules_file])
    end
    cmd = `$executable_str $config_str $flags`
    println("\tRunning simulation: $(simulation.id)...")
    flush(stdout)
    try
        run(pipeline(cmd; stdout="$(path_to_simulation_folder)/output.log", stderr="$(path_to_simulation_folder)/output.err"); wait=true)
    catch
        println("\tSimulation $(simulation.id) failed.")
        println("\tCompile command: $cmd")
        println("\tCheck $(path_to_simulation_folder)/output.err for more information.")
        success = false
    else
        rm("$(path_to_simulation_folder)/output.err"; force=true)
        success = true
    end
    ran = true
    
    return ran, success
end

function runMonad(monad::Monad; use_previous_sims::Bool=false, do_full_setup::Bool=true, force_recompile::Bool=false)
    mkpath("$(data_dir)/outputs/monads/$(monad.id)")
    n_new_simulations = monad.min_length
    if use_previous_sims
        n_new_simulations -= length(monad.simulation_ids)
    end

    if n_new_simulations <= 0
        return Task[]
    end

    if do_full_setup
        loadCustomCode(monad; force_recompile=force_recompile)
    end
    loadConfiguration(monad)
    loadRulesets(monad)

    simulation_tasks = Task[]
    for i in 1:n_new_simulations
        simulation = Simulation(monad)
        push!(simulation_tasks, @task runSimulation(simulation; do_full_setup=false, force_recompile=false))
        push!(monad.simulation_ids, simulation.id)
    end

    recordSimulationIDs(monad)

    return simulation_tasks
end

function runSampling(sampling::Sampling; use_previous_sims::Bool=false, force_recompile::Bool=false)
    mkpath("$(data_dir)/outputs/samplings/$(sampling.id)")

    loadCustomCode(sampling; force_recompile=force_recompile)

    simulation_tasks = []
    for index in eachindex(sampling.variation_ids)
        monad = Monad(sampling, index) # instantiate a monad with the variation_id and the simulation ids already found
        append!(simulation_tasks, runMonad(monad, use_previous_sims=use_previous_sims, do_full_setup=false, force_recompile=false)) # run the monad and add the number of new simulations to the total
    end

    recordMonadIDs(sampling) # record the monad ids in the sampling
    return simulation_tasks
end

function runTrial(trial::Trial; use_previous_sims::Bool=false, force_recompile::Bool=true)
    mkpath("$(data_dir)/outputs/trials/$(trial.id)")

    simulation_tasks = []
    for i in eachindex(trial.sampling_ids)
        sampling = Sampling(trial, i) # instantiate a sampling with the variation_ids and the simulation ids already found
        append!(simulation_tasks, runSampling(sampling; use_previous_sims=use_previous_sims, force_recompile=force_recompile)) # run the sampling and add the number of new simulations to the total
    end

    recordSamplingIDs(trial) # record the sampling ids in the trial
    return simulation_tasks
end

collectSimulationTasks(simulation::Simulation; use_previous_sims::Bool=false, force_recompile::Bool=false) = [@task runSimulation(simulation; do_full_setup=true, force_recompile=force_recompile)]
collectSimulationTasks(monad::Monad; use_previous_sims::Bool=false, force_recompile::Bool=false) = runMonad(monad; use_previous_sims=use_previous_sims, do_full_setup=true, force_recompile=force_recompile)
collectSimulationTasks(sampling::Sampling; use_previous_sims::Bool=false, force_recompile::Bool=false) = runSampling(sampling; use_previous_sims=use_previous_sims, force_recompile=force_recompile)
collectSimulationTasks(trial::Trial; use_previous_sims::Bool=false, force_recompile::Bool=false) = runTrial(trial; use_previous_sims=use_previous_sims, force_recompile=force_recompile)

function runAbstractTrial(T::AbstractTrial; use_previous_sims::Bool=false, force_recompile::Bool=true)
    cd(()->run(pipeline(`make clean`; stdout=devnull)), physicell_dir) # remove all *.o files so that a future recompile will re-compile all the files

    getMacroFlags(T) # make sure all the macros files are up-to-date

    simulation_tasks = collectSimulationTasks(T; use_previous_sims=use_previous_sims, force_recompile=force_recompile)
    n_ran = Threads.Atomic{Int}(0)
    n_success = Threads.Atomic{Int}(0)

    println("Running $(typeof(T)) $(T.id) requiring $(length(simulation_tasks)) simulations...")

    Threads.@threads :static for simulation_task in simulation_tasks
        schedule(simulation_task)
        ran, success = fetch(simulation_task)

        # prevent data races on n_ran and n_success
        ran ? Threads.atomic_add!(n_ran, 1) : nothing # shorthand for add 1 if ran is true
        success ? Threads.atomic_add!(n_success, 1) : nothing # shorthand for add 1 if success is true
    end

    n_asterisks = 1
    asterisks = Dict{String, Int}()
    size_T = length(T)
    println("Finished $(typeof(T)) $(T.id).")
    println("\t- Consists of $(size_T) simulations.")
    print(  "\t- Scheduled $(length(simulation_tasks)) simulations to complete this $(typeof(T)).")
    print_low_schedule_message = use_previous_sims && length(simulation_tasks) < size_T
    if print_low_schedule_message
        println(" ($(repeat("*", n_asterisks))).")
        asterisks["low_schedule_message"] = n_asterisks
        n_asterisks += 1
    else
        println(".")
    end
    print(  "\t- Ran $(n_ran[]) simulations.")
    print_low_ran_warning = n_ran[] < length(simulation_tasks)
    if print_low_ran_warning
        println(" ($(repeat("*", n_asterisks))).")
        asterisks["low_ran_warning"] = n_asterisks
        n_asterisks += 1
    else
        println(".")
    end
    print(  "\t- Successful completion of $(n_success[]) simulations.")
    print_low_success_warning = n_success[] < n_ran[]
    if print_low_success_warning
        println(" ($(repeat("*", n_asterisks))).")
        asterisks["low_success_warning"] = n_asterisks
        n_asterisks += 1 # in case something gets added later
    else
        println(".")
    end
    if print_low_schedule_message
        println("\n($(repeat("*", asterisks["low_schedule_message"]))) pcvct found matching simulations and will save you time by not re-running them!")
    end
    if print_low_ran_warning
        println("\n($(repeat("*", asterisks["low_ran_warning"]))) Some scheduled simulations did not run. This would happen because a simulation had run previously, but no been recorded with the monad.")
    end
    if print_low_success_warning
        println("\n($(repeat("*", asterisks["low_success_warning"]))) Some simulations did not complete successfully. Check the output.err files for more information.")
    end
    println("\n--------------------------------------------------\n")
    return n_ran[], n_success[]
end