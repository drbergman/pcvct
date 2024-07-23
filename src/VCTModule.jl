module VCTModule

# each file (includes below) has their own export statements
export initializeVCT, resetDatabase, addGridVariation, addGridRulesetsVariation, runAbstractTrial, getTrialSamplings, getSimulations, deleteSimulation
export addLHSVariation, addLHSRulesetsVariation

using SQLite, DataFrames, LightXML, LazyGrids, Dates, CSV, Tables, Distributions, Statistics, Random, QuasiMonteCarlo
using MAT # files for VCTLoader.jl

include("VCTClasses.jl")
include("VCTDatabase.jl") 
include("VCTConfiguration.jl")
include("VCTExtraction.jl")
include("VCTLoader.jl")
include("VCTSensitivity.jl")

physicell_dir::String = abspath("PhysiCell")
data_dir::String = abspath("data")
PHYSICELL_CPP::String = haskey(ENV, "PHYSICELL_CPP") ? ENV["PHYSICELL_CPP"] : "/opt/homebrew/bin/g++-14"

################## Initialization Functions ##################

function pcvctLogo()
    return """
    \n
    ▐▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▌
    ▐                                                                     ▌
    ▐   ███████████    █████████  █████   █████   █████████  ███████████  ▌
    ▐  ░░███░░░░░███  ███░░░░░███░░███   ░░███   ███░░░░░███░█░░░███░░░█  ▌
    ▐   ░███    ░███ ███     ░░░  ░███    ░███  ███     ░░░ ░   ░███  ░   ▌
    ▐   ░██████████ ░███          ░███    ░███ ░███             ░███      ▌
    ▐   ░███░░░░░░  ░███          ░░███   ███  ░███             ░███      ▌
    ▐   ░███        ░░███     ███  ░░░█████░   ░░███     ███    ░███      ▌
    ▐   █████        ░░█████████     ░░███      ░░█████████     █████     ▌
    ▐  ░░░░░          ░░░░░░░░░       ░░░        ░░░░░░░░░     ░░░░░      ▌
    ▐                                                                     ▌
    ▐▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▌
    \n
      """
end

function initializeVCT(path_to_physicell::String, path_to_data::String)
    # print big logo of PCVCT here
    println(pcvctLogo())
    println("----------INITIALIZING----------")
    global physicell_dir = abspath(path_to_physicell)
    global data_dir = abspath(path_to_data)
    println(rpad("Path to PhysiCell:", 20, ' ') * physicell_dir)
    println(rpad("Path to data:", 20, ' ') * data_dir)
    initializeDatabase("$(data_dir)/vct.db")
end

################## Compilation Functions ##################

function loadCustomCode(S::AbstractSampling; force_recompile::Bool=false)
    cflags, recompile, clean = getCompilerFlags(S)

    recompile |= force_recompile # if force_recompile is true, then recompile no matter what

    if !recompile
        return
    end

    if clean
        cd(()->run(pipeline(`make clean`, stdout=devnull)), physicell_dir)
    end

    path_to_folder = "$(data_dir)/inputs/custom_codes/$(S.folder_names.custom_code_folder)" # source dir needs to end in / or else the dir is copied into target, not the source files
    run(`cp -r $(path_to_folder)/custom_modules/ $(physicell_dir)/custom_modules`)
    run(`cp $(path_to_folder)/main.cpp $(physicell_dir)/main.cpp`)
    run(`cp $(path_to_folder)/Makefile $(physicell_dir)/Makefile`)

    cmd = `make -j 20 CC=$(PHYSICELL_CPP) PROGRAM_NAME=project_ccid_$(S.folder_ids.custom_code_id) CFLAGS=$(cflags)`

    println("Compiling custom code for $(S.folder_names.custom_code_folder) with flags: $cflags")

    cd(() -> run(pipeline(cmd, stdout="$(path_to_folder)/compilation.log", stderr="$(path_to_folder)/compilation.err")), physicell_dir) # compile the custom code in the PhysiCell directory and return to the original directory; make sure the macro ADDON_PHYSIECM is defined (should work even if multiply defined, e.g., by Makefile)
    
    # check if the error file is empty, if it is, delete it
    if filesize("$(path_to_folder)/compilation.err") == 0
        rm("$(path_to_folder)/compilation.err", force=true)
    end

    rm("$(physicell_dir)/custom_modules/custom.cpp", force=true)
    rm("$(physicell_dir)/custom_modules/custom.h", force=true)
    rm("$(physicell_dir)/main.cpp", force=true)
    run(`cp $(physicell_dir)/sample_projects/Makefile-default $(physicell_dir)/Makefile`)

    mv("$(physicell_dir)/project_ccid_$(S.folder_ids.custom_code_id)", "$(data_dir)/inputs/custom_codes/$(S.folder_names.custom_code_folder)/project", force=true)
    return 
end

function getCompilerFlags(S::AbstractSampling)
    recompile = false # only recompile if need is found
    clean = false # only clean if need is found
    cflags = "-march=native -O3 -fomit-frame-pointer -fopenmp -m64 -std=c++11"
    add_mfpmath = false
    if Sys.iswindows()
        add_mfpmath = true
    elseif Sys.isapple()
        if strip(read(`uname -s`, String)) == "Darwin"
            cc_path = strip(read(`which $(PHYSICELL_CPP)`, String))
            var = strip(read(`file $cc_path`, String))
            add_mfpmath = split(var)[end] != "arm64"
        end
    end
    if add_mfpmath
        cflags *= " -mfpmath=both"
    end

    current_macros = readMacrosFile(S) # this will get all macros already in the macros file
    updated_macros = getMacroFlags(S) # this will get all macros already in the macros file

    if length(updated_macros) != length(current_macros)
        recompile = true
        clean = true
    end

    for macro_flag in updated_macros
        cflags *= " -D $(macro_flag)"
    end

    if !recompile && !isfile("$(data_dir)/inputs/custom_codes/$(S.folder_names.custom_code_folder)/project")
        recompile = true
    end

    return cflags, recompile, clean
end

function getMacroFlags(S::AbstractSampling)
    current_macros = readMacrosFile(S)
    initializeMacros(S)
    return readMacrosFile(S)
end

function getMacroFlags(trial::Trial)
    for i in eachindex(trial.sampling_ids)
        sampling = Sampling(trial, i) # instantiate a sampling with the variation_ids and the simulation ids already found
        initializeMacros(sampling)
    end
end

function initializeMacros(S::AbstractSampling)
    # else get the macros neeeded
    checkPhysiECMMacro(S)

    # check others...
    return
end

function addMacro(S::AbstractSampling, macro_name::String)
    path_to_macros = "$(data_dir)/inputs/custom_codes/$(S.folder_names.custom_code_folder)/macros.txt"
    open(path_to_macros, "a") do f
        println(f, macro_name)
    end
    return
end

function checkPhysiECMMacro(S::AbstractSampling)
    if "ADDON_PHYSIECM" in readMacrosFile(S)
        # if the custom codes folder for the sampling already has the macro, then we don't need to do anything
        return
    end
    if S.folder_ids.ic_ecm_id != -1
        # if this sampling is providing an ic file for ecm, then we need to add the macro
        return addMacro(S, "ADDON_PHYSIECM")
    end
    # check if ecm_setup element has enabled="true" in config files
    loadConfiguration(S)
    return checkPhysiECMInConfig(S)
end

function checkPhysiECMInConfig(M::AbstractMonad)
    path_to_xml = "$(data_dir)/inputs/configs/$(M.folder_names.config_folder)/variations/variation_$(M.variation_id).xml"
    xml_path = ["microenvironment_setup", "ecm_setup"]
    ecm_setup_element = retrieveElement(path_to_xml, xml_path; required=false)
    if !isnothing(ecm_setup_element) && attribute(ecm_setup_element, "enabled") == "true" # note: attribute returns nothing if the attribute does not exist
        # if the base config file says that the ecm is enabled, then we need to add the macro
        addMacro(M, "ADDON_PHYSIECM")
        return true
    end
    return false
end

function checkPhysiECMInConfig(sampling::Sampling)
    # otherwise, no previous sampling saying to use the macro, no ic file for ecm, and the base config file does not have ecm enabled,
    # now just check that the variation is not enabling the ecm
    for index in eachindex(sampling.variation_ids)
        monad = Monad(sampling, index) # instantiate a monad with the variation_id and the simulation ids already found
        if checkPhysiECMInConfig(monad)
            return true
        end
    end
    return false
end

function readMacrosFile(S::AbstractSampling)
    path_to_macros = "$(data_dir)/inputs/custom_codes/$(S.folder_names.custom_code_folder)/macros.txt"
    if !isfile(path_to_macros)
        return []
    end
    return readlines(path_to_macros)
end

################## Deletion Functions ##################

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

function resetDatabase()

    # prompt user to confirm
    println("Are you sure you want to reset the database? (y/n)")
    response = readline()
    if response != "y" # make user be very specific about resetting
        println("You entered '$response'.\n\tResetting the database has been cancelled.\n\n\tDo you want to continue with the script? (y/n)")
        response = readline()
        if response != "y" # make user be very specific about continuing
            println("You entered '$response'.\n\tThe script has been cancelled.")
            error("Script cancelled.")
        end
        println("You entered '$response'.\n\tThe script will continue.")
        return
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

    rm("$(path_to_config_folder)/rulesets_collections.db", force=true)
end

function resetRulesetsCollectionFolder(path_to_rulesets_collection_folder::String)
    if !isdir(path_to_rulesets_collection_folder)
        return
    end
    rm("$(path_to_rulesets_collection_folder)/rulesets_variations.db", force=true)
    rm("$(path_to_rulesets_collection_folder)/rulesets_variations", force=true)

    rm("$(path_to_rulesets_collection_folder)/rulesets_variations.db", force=true)
end

################## Running Functions ##################

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
    try
        run(pipeline(cmd, stdout="$(path_to_simulation_folder)/output.log", stderr="$(path_to_simulation_folder)/output.err"), wait=true)
    catch
        success = false
    else
        rm("$(path_to_simulation_folder)/output.err", force=true)
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
    cd(()->run(pipeline(`make clean`, stdout=devnull)), physicell_dir)

    getMacroFlags(T)

    simulation_tasks = collectSimulationTasks(T; use_previous_sims=use_previous_sims, force_recompile=force_recompile)
    n_ran = 0
    n_success = 0

    Threads.@threads :static for simulation_task in simulation_tasks
        schedule(simulation_task)
        ran, success = fetch(simulation_task)
        n_ran += ran
        n_success += success
    end

    println("Finished $(typeof(T)) $(T.id).")
    print("\tRan $(n_ran) simulations of $(length(simulation_tasks)) scheduled")
    use_previous_sims ? println(" (*).") : println(".")
    println("\tSuccessful completion of $(n_success).")
    use_previous_sims && println("\n(*) Some scheduled simulations do not run because matching previous simulations were found.")
    println("\n--------------------------------------------------\n")
    return n_ran, n_success
end

################## Recording Functions ##################

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

################## Variations Functions ##################

function addColumns(xml_paths::Vector{Vector{String}}, table_name::String, id_column_name::String, db_columns::SQLite.DB, path_to_xml::String, dataTypeRulesFn::Function)
    column_names = queryToDataFrame("PRAGMA table_info($(table_name));"; db=db_columns) |> x->x[!,:name]
    filter!(x -> x != id_column_name, column_names)
    varied_column_names = [xmlPathToColumnName(xml_path) for xml_path in xml_paths]

    is_new_column = [!(varied_column_name in column_names) for varied_column_name in varied_column_names]
    if any(is_new_column)
        new_column_names = varied_column_names[is_new_column]
        xml_doc = openXML(path_to_xml)
        default_values_for_new = [getField(xml_doc, xml_path) for xml_path in xml_paths[is_new_column]]
        closeXML(xml_doc)
        for (i, new_column_name) in enumerate(new_column_names)
            sqlite_data_type = dataTypeRulesFn(i, new_column_name)
            DBInterface.execute(db_columns, "ALTER TABLE $(table_name) ADD COLUMN '$(new_column_name)' $(sqlite_data_type);")
        end
        DBInterface.execute(db_columns, "UPDATE $(table_name) SET ($(join("\"".*new_column_names.*"\"",",")))=($(join("\"".*default_values_for_new.*"\"",",")));") # set newly added columns to default values

        index_name = "$(table_name)_index"
        SQLite.dropindex!(db_columns, index_name; ifexists=true) # remove previous index
        index_columns = deepcopy(column_names)
        append!(index_columns, new_column_names)
        SQLite.createindex!(db_columns, table_name, index_name, index_columns; unique=true, ifnotexists=false) # add new index to make sure no variations are repeated
    end

    static_column_names = deepcopy(column_names)
    old_varied_names = varied_column_names[.!is_new_column]
    filter!(x -> !(x in old_varied_names), static_column_names)

    return static_column_names, varied_column_names
end

function addVariationColumns(config_id::Int, xml_paths::Vector{Vector{String}}, variable_types::Vector{DataType})
    config_folder = getConfigFolder(config_id)
    db_columns = getConfigDB(config_folder)
    path_to_xml = "$(data_dir)/inputs/configs/$(config_folder)/PhysiCell_settings.xml"
    dataTypeRulesFn = (i, _) -> begin
        if variable_types[i] == Bool
            "TEXT"
        elseif variable_types[i] <: Int
            "INT"
        elseif variable_types[i] <: Real
            "REAL"
        else
            "TEXT"
        end
    end
    return addColumns(xml_paths, "variations", "variation_id", db_columns, path_to_xml, dataTypeRulesFn)
end

function addRulesetsVariationsColumns(rulesets_collection_id::Int, xml_paths::Vector{Vector{String}})
    rulesets_collection_folder = getRulesetsCollectionFolder(rulesets_collection_id)
    db_columns = getRulesetsCollectionDB(rulesets_collection_folder)
    path_to_xml = "$(data_dir)/inputs/rulesets_collections/$(rulesets_collection_folder)/base_rulesets.xml"
    dataTypeRulesFn = (_, name) -> "applies_to_dead" in name ? "INT" : "REAL"
    return addColumns(xml_paths, "rulesets_variations", "rulesets_variation_id", db_columns, path_to_xml, dataTypeRulesFn)
end

function addRow(db_columns::SQLite.DB, table_name::String, id_name::String, table_features::String, values::String)
    new_id = DBInterface.execute(db_columns, "INSERT OR IGNORE INTO $(table_name) ($(table_features)) VALUES($(values)) RETURNING $(id_name);") |> DataFrame |> x->x[!,1]
    new_added = length(new_id)==1
    if  !new_added
        query = constructSelectQuery(table_name, "WHERE ($(table_features))=($(values))"; selection=id_name)
        new_id = queryToDataFrame(query, db=db_columns) |> x->x[!,1]
    end
    return new_id[1]
end

function addVariationRow(config_id::Int, table_features::String, values::String)
    db_columns = getConfigDB(config_id)
    return addRow(db_columns, "variations", "variation_id", table_features, values)
end

function addVariationRow(config_id::Int, table_features::String, static_values::String, varied_values::String)
    return addVariationRow(config_id, table_features, "$(static_values)$(varied_values)")
end

function addRulesetsVariationRow(rulesets_collection_id::Int, table_features::String, values::String)
    db_columns = getRulesetsCollectionDB(rulesets_collection_id)
    return addRow(db_columns, "rulesets_variations", "rulesets_variation_id", table_features, values)
end

function addRulesetsVariationRow(rulesets_collection_id::Int, table_features::String, static_values::String, varied_values::String)
    return addRulesetsVariationRow(rulesets_collection_id, table_features, "$(static_values)$(varied_values)")
end

function addGrid(EV::Vector{<:ElementaryVariation}, addColumnsByPathsFn::Function, prepareAddNewFn::Function, addRowFn::Function)
    new_values = [ev.values for ev in EV]

    static_values, table_features = setUpColumns(EV, addColumnsByPathsFn, prepareAddNewFn)

    NDG = ndgrid(new_values...)
    sz_variations = size(NDG[1])
    variation_ids = zeros(Int, sz_variations)
    for i in eachindex(NDG[1])
        varied_values = [A[i] for A in NDG] .|> string |> x -> join("\"" .* x .* "\"", ",")
        variation_ids[i] = addRowFn(table_features, static_values, varied_values)
    end
    return variation_ids
end

function setUpColumns(AV::Vector{<:AbstractVariation}, addColumnsByPathsFn::Function, prepareAddNewFn::Function)
    xml_paths = [av.xml_path for av in AV]

    static_column_names, varied_column_names = addColumnsByPathsFn(xml_paths)
    return prepareAddNewFn(static_column_names, varied_column_names)
end

"""
    function addGridVariation(config_folder::String, EV::Vector{<:ElementaryVariation}; reference_variation_id::Int=0)

Adds a grid of parameter values defined by `EV` (a vector of `ElementaryVariation` objects) to the Variations table for a specified configuration.
A reference variation id can be supplied so that any currently unvaried values are pulled from that variation.
Each `ElementaryVariation` in `EV` represents a single parameter's variation across its range of values.
"""

function addGridVariation(config_id::Int, EV::Vector{<:ElementaryVariation}; reference_variation_id::Int=0)
    addColumnsByPathsFn = (paths) -> addVariationColumns(config_id, paths, [typeof(ev.values[1]) for ev in EV])
    prepareAddNewFn = (static_column_names, varied_column_names) -> prepareAddNewVariations(config_id, static_column_names, varied_column_names; reference_variation_id=reference_variation_id)
    addRowFn = (features, static_values, varied_values) -> addVariationRow(config_id, features, static_values, varied_values)
    return addGrid(EV, addColumnsByPathsFn, prepareAddNewFn, addRowFn)
end

addGridVariation(config_folder::String, EV::Vector{<:ElementaryVariation}; reference_variation_id::Int=0) = addGridVariation(retrieveID("configs", config_folder), EV; reference_variation_id=reference_variation_id)

addGridVariation(config_id::Int, EV::ElementaryVariation; reference_variation_id::Int=0) = addGridVariation(config_id, [EV]; reference_variation_id=reference_variation_id)
addGridVariation(config_folder::String, EV::ElementaryVariation; reference_variation_id::Int=0) = addGridVariation(config_folder, [EV]; reference_variation_id=reference_variation_id)

function addGridRulesetsVariation(rulesets_collection_id::Int, EV::Vector{<:ElementaryVariation}; reference_rulesets_variation_id::Int=0)
    addColumnsByPathsFn = (paths) -> addRulesetsVariationsColumns(rulesets_collection_id, paths)
    prepareAddNewFn = (static_names, varied_names) -> prepareAddNewRulesetsVariations(rulesets_collection_id, static_names, varied_names; reference_rulesets_variation_id=reference_rulesets_variation_id)
    addRowFn = (features, static_values, varied_values) -> addRulesetsVariationRow(rulesets_collection_id, features, static_values, varied_values)
    return addGrid(EV, addColumnsByPathsFn, prepareAddNewFn, addRowFn)
end

addGridRulesetsVariation(rulesets_collection_folder::String, EV::Vector{<:ElementaryVariation}; reference_rulesets_variation_id::Int=0) = addGridRulesetsVariation(retrieveID("rulesets_collections", rulesets_collection_folder), EV; reference_rulesets_variation_id=reference_rulesets_variation_id)

addGridRulesetsVariation(rulesets_collection_id::Int, EV::ElementaryVariation; reference_rulesets_variation_id::Int=0) = addGridRulesetsVariation(rulesets_collection_id, [EV]; reference_rulesets_variation_id=reference_rulesets_variation_id)
addGridRulesetsVariation(rulesets_collection_folder::String, EV::ElementaryVariation; reference_rulesets_variation_id::Int=0) = addGridRulesetsVariation(rulesets_collection_folder, [EV]; reference_rulesets_variation_id=reference_rulesets_variation_id)

function prepareAddNew(db_columns::SQLite.DB, static_column_names::Vector{String}, varied_column_names::Vector{String}, table_name::String, id_name::String, reference_id::Int)
    if isempty(static_column_names)
        static_values = ""
        table_features = ""
    else
        query = constructSelectQuery(table_name, "WHERE $(id_name)=$(reference_id);"; selection=join("\"" .* static_column_names .* "\"", ", "))
        static_values = queryToDataFrame(query, db=db_columns) |> x -> join(x |> eachcol .|> c -> "\"$(string(c[1]))\"", ",")
        static_values *= ","
        table_features = join("\"" .* static_column_names .* "\"", ",")
        table_features *= ","
    end
    table_features *= join("\"" .* varied_column_names .* "\"", ",")
    return static_values, table_features
end

function prepareAddNewVariations(config_id::Int, static_column_names::Vector{String}, varied_column_names::Vector{String}; reference_variation_id::Int=0)
    db_columns = getConfigDB(config_id)
    return prepareAddNew(db_columns, static_column_names, varied_column_names, "variations", "variation_id", reference_variation_id)
end

function prepareAddNewRulesetsVariations(rulesets_collection_id::Int, static_column_names::Vector{String}, varied_column_names::Vector{String}; reference_rulesets_variation_id::Int=0)
    db_columns = getRulesetsCollectionDB(rulesets_collection_id)
    return prepareAddNew(db_columns, static_column_names, varied_column_names, "rulesets_variations", "rulesets_variation_id", reference_rulesets_variation_id)
end

################## Latin Hypercube Sampling Functions ##################

function orthogonalLHS(k::Int, d::Int)
    n = k^d
    lhs_inds = zeros(Int, (n, d))
    for i in 1:d
        n_bins = k^(i - 1) # number of bins from previous dims (a bin has sampled points that are in the same subelement up through i-1 dim and need to be separated in subsequent dims)
        bin_size = k^(d-i+1) # number of sampled points in each bin
        if i == 1
            lhs_inds[:, 1] = 1:n
        else
            bin_inds_gps = [(j - 1) * bin_size .+ (1:bin_size) |> collect for j in 1:n_bins] # the indices belonging to each of the bins (this relies on the sorting step below to easily find which points are currently in the same box and need to be separated along the ith dimension)
            for pt_ind = 1:bin_size # pick ith coordinate for each point in the bin; each iter here will work up the ith coordinates assigning one to each bin at each iter
                ind = zeros(Int, n_bins) # indices where the next set of ith coordinates will go
                for (j, bin_inds) in enumerate(bin_inds_gps) # pick a random, remaining element for each bin
                    rand_ind_of_ind = rand(1:length(bin_inds)) # pick the index of a remaining index
                    ind[j] = popat!(bin_inds, rand_ind_of_ind) # get the random index and remove it so we don't pick it again
                end
                lhs_inds[ind,i] = shuffle(1:n_bins) .+ (pt_ind - 1) * n_bins # for the selected inds, shuffle the next set of ith coords into them
            end
        end
        lhs_inds[:, 1:i] = sortslices(lhs_inds[:, 1:i], dims=1, by=x -> (x ./ (n / k) .|> ceil .|> Int)) # sort the found values so that sampled points in the same box upon projection into the 1:i dims are adjacent
    end
    return lhs_inds
end

function orthogonalLHS_relaxed(k::Int, d::Int)
    # I have this here because this technically gives all possible orthogonal lhs samples, but my orthogonalLHS gives a more uniform LHS
    n = k^d
    lhs_inds = zeros(Int, (n, d))
    for i in 1:d
        bin_size = n / (k^(i - 1)) |> ceil |> Int # number of sampled points grouped by all previous dims
        n_bins = k^(i - 1) # number of bins in this dimension
        if i == 1
            lhs_inds[:, 1] = 1:n
            continue
        else
            bin_inds_gps = [(j - 1) * bin_size .+ (1:bin_size) |> collect for j in 1:n_bins] # the indexes in y corresponding to each of the bins (this relies on the sorting step below to easily find which points are currently in the same box and need to be separated along the ith dimension)
            for pt_ind = 1:k
                y_vals = shuffle((pt_ind - 1) * Int(n / k) .+ (1:Int(n / k)))
                inds = zeros(Int, Int(n / k))
                for (j, bin_inds) in enumerate(bin_inds_gps)
                    for s in 1:Int(n / k^(i))
                        rand_ind_of_ind = rand(1:length(bin_inds))
                        rand_ind = popat!(bin_inds, rand_ind_of_ind) # random value remaining in bin, remove it so we don't pick it again
                        inds[(j-1)*Int(n / k^(i))+s] = rand_ind # record the index
                    end
                end
                lhs_inds[inds, i] = y_vals
            end
        end
        lhs_inds[:, 1:i] = sortslices(lhs_inds[:, 1:i], dims=1, by=x -> (x ./ (n / k) .|> ceil .|> Int)) # sort the found values so that sampled points in the same box upon projection into the 1:i dims are adjacent
    end
end

function addLHS(n::Integer, DV::Vector{DistributedVariation}, addColumnsByPathsFn::Function, prepareAddNewFn::Function, addRowFn::Function; add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG, orthogonalize::Bool=true)
    icdfs = (Float64.(1:n) .- (add_noise ? rand(rng, Float64, n) : 0.5)) / n # permute below for each parameter separately
    d = length(DV)
    k = n ^ (1 / length(DV)) |> round |> Int
    if orthogonalize && (n == k^d)
        # then good to do the orthogonalization
        lhs_inds = orthogonalLHS(k, d)
    else
        lhs_inds = hcat([shuffle(rng, 1:n) for _ in 1:d]...)
    end
    all_icdfs = icdfs[lhs_inds]

    return icdfsToVariations(n, all_icdfs, DV, addColumnsByPathsFn, prepareAddNewFn, addRowFn)
end

function addLHSVariation(n::Integer, config_id::Int, DV::Vector{DistributedVariation}; reference_variation_id::Int=0, add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG)
    fns = prepareVariationFunctions(config_id, DV; reference_variation_id=reference_variation_id)
    return addLHS(n, DV, fns...; add_noise=add_noise, rng=rng)
end

addLHSVariation(n::Integer, config_folder::String, DV::Vector{DistributedVariation}; reference_variation_id::Int=0, add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG) = addLHSVariation(n, retrieveID("configs", config_folder), DV; reference_variation_id=reference_variation_id, add_noise=add_noise, rng=rng)
addLHSVariation(n::Integer, config_id::Int, DV::DistributedVariation; reference_variation_id::Int=0, add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG) = addLHSVariation(n, config_id, [DV]; reference_variation_id=reference_variation_id, add_noise=add_noise, rng=rng)
addLHSVariation(n::Integer, config_folder::String, DV::DistributedVariation; reference_variation_id::Int=0, add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG) = addLHSVariation(n, config_folder, [DV]; reference_variation_id=reference_variation_id, add_noise=add_noise, rng=rng)

function addLHSRulesetsVariation(n::Integer, rulesets_collection_id::Int, DV::Vector{DistributedVariation}; reference_rulesets_variation_id::Int=0, add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG)
    fns = prepareRulesetsVariationFunctions(rulesets_collection_id)
    return addLHS(n, DV, fns...; add_noise=add_noise, rng=rng)
end

addLHSRulesetsVariation(n::Integer, rulesets_collection_folder::String, DV::Vector{DistributedVariation}; reference_variation_id::Int=0, add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG) = addLHSRulesetsVariation(n, retrieveID("rulesets_collections", rulesets_collection_folder), DV; reference_variation_id=reference_variation_id, add_noise=add_noise, rng=rng)
addLHSRulesetsVariation(n::Integer, rulesets_collection_id::Int, DV::DistributedVariation; reference_variation_id::Int=0, add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG) = addLHSRulesetsVariation(n, rulesets_collection_id, [DV]; reference_variation_id=reference_variation_id, add_noise=add_noise, rng=rng)
addLHSRulesetsVariation(n::Integer, rulesets_collection_folder::String, DV::DistributedVariation; reference_variation_id::Int=0, add_noise::Bool=false, rng::AbstractRNG=Random.GLOBAL_RNG) = addLHSRulesetsVariation(n, rulesets_collection_folder, [DV]; reference_variation_id=reference_variation_id, add_noise=add_noise, rng=rng)

################## Sobol Sequence Sampling Functions ##################

function addSobol(n::Integer, DV::Vector{DistributedVariation}, addColumnsByPathsFn::Function, prepareAddNewFn::Function, addRowFn::Function; n_matrices::Int=1)
    d = length(DV)
    icdfs = QuasiMonteCarlo.sample(n, d * n_matrices, SobolSample()) # this returns a matrix of size (d * n_matrices) x n, i.e. each column is n_matrices samples of the d parameters
    total_samples = n_matrices * n # total number of samples represented here
    icdfs_reshaped = reshape(icdfs, (d, total_samples)) # split each column into n_matrices columns (note: every group of consecutive n_matrices columns has a representative of each of the n_matrices samples)
    variation_ids = icdfsToVariations(total_samples, icdfs_reshaped', DV, addColumnsByPathsFn, prepareAddNewFn, addRowFn) # a vector of all variation_ids grouped as above
    variation_ids = reshape(variation_ids, (n_matrices, n))' # first, pull out the n_matrices groupings into columns and then the n samples for each matrix into rows; return such that each column is a sobol sample
    return variation_ids, icdfs
end

function addSobolVariation(n::Integer, config_id::Int, DV::Vector{DistributedVariation}; reference_variation_id::Int=0, n_matrices::Int=1)
    fns = prepareVariationFunctions(config_id, DV; reference_variation_id=reference_variation_id)
    return addSobol(n, DV, fns...; n_matrices=n_matrices)
end
addSobolVariation(n::Integer, config_folder::String, DV::Vector{DistributedVariation}; reference_variation_id::Int=0, n_matrices::Int=1) = addSobolVariation(n, retrieveID("configs", config_folder), DV; reference_variation_id=reference_variation_id, n_matrices=n_matrices)
addSobolVariation(n::Integer, config_id::Int, DV::DistributedVariation; reference_variation_id::Int=0, n_matrices::Int=1) = addSobolVariation(n, config_id, [DV]; reference_variation_id=reference_variation_id, n_matrices=n_matrices)
addSobolVariation(n::Integer, config_folder::String, DV::DistributedVariation; reference_variation_id::Int=0, n_matrices::Int=1) = addSobolVariation(n, config_folder, [DV]; reference_variation_id=reference_variation_id, n_matrices=n_matrices)

function addSobolRulesetsVariation(n::Integer, rulesets_collection_id::Int, DV::Vector{DistributedVariation}; reference_rulesets_variation_id::Int=0, n_matrices::Int=1)
    fns = prepareRulesetsVariationFunctions(rulesets_collection_id)
    return addSobol(n, DV, fns...; n_matrices=n_matrices)
end

addSobolRulesetsVariation(n::Integer, rulesets_collection_folder::String, DV::Vector{DistributedVariation}; reference_rulesets_variation_id::Int=0, n_matrices::Int=1) = addSobolRulesetsVariation(n, retrieveID("rulesets_collections", rulesets_collection_folder), DV; reference_rulesets_variation_id=reference_rulesets_variation_id, n_matrices=n_matrices)
addSobolRulesetsVariation(n::Integer, rulesets_collection_id::Int, DV::DistributedVariation; reference_rulesets_variation_id::Int=0, n_matrices::Int=1) = addSobolRulesetsVariation(n, rulesets_collection_id, [DV]; reference_rulesets_variation_id=reference_rulesets_variation_id, n_matrices=n_matrices)
addSobolRulesetsVariation(n::Integer, rulesets_collection_folder::String, DV::DistributedVariation; reference_rulesets_variation_id::Int=0, n_matrices::Int=1) = addSobolRulesetsVariation(n, rulesets_collection_folder, [DV]; reference_rulesets_variation_id=reference_rulesets_variation_id, n_matrices=n_matrices)

################## Sampling Helper Functions ##################

function icdfsToVariations(n::Int, icdfs::AbstractMatrix{Float64}, DV::Vector{DistributedVariation}, addColumnsByPathsFn::Function, prepareAddNewFn::Function, addRowFn::Function)
    new_values = []
    for (i,d) in enumerate([dv.distribution for dv in DV])
        new_value = Statistics.quantile(d, icdfs[:,i]) # ok, all the new values for the given parameter
        push!(new_values, new_value)
    end

    static_values, table_features = setUpColumns(DV, addColumnsByPathsFn, prepareAddNewFn)

    variation_ids = zeros(Int, n)

    for i in 1:n
        varied_values = [new_value[i] for new_value in new_values] .|> string |> x -> join("\"" .* x .* "\"", ",")
        variation_ids[i] = addRowFn(table_features, static_values, varied_values)
    end
    return variation_ids
end

function prepareVariationFunctions(config_id::Int, DV::Vector{DistributedVariation}; reference_variation_id=0)
    addColumnsByPathsFn = (paths) -> addVariationColumns(config_id, paths, [eltype(dv.distribution) for dv in DV])
    prepareAddNewFn = (static_column_names, varied_column_names) -> prepareAddNewVariations(config_id, static_column_names, varied_column_names; reference_variation_id=reference_variation_id)
    addRowFn = (features, static_values, varied_values) -> addVariationRow(config_id, features, static_values, varied_values)
    return addColumnsByPathsFn, prepareAddNewFn, addRowFn
end

function prepareRulesetsVariationFunctions(rulesets_collection_id::Int)
    addColumnsByPathsFn = (paths) -> addRulesetsVariationsColumns(rulesets_collection_id, paths)
    prepareAddNewFn = (static_column_names, varied_column_names) -> prepareAddNewRulesetsVariations(rulesets_collection_id, static_column_names, varied_column_names)
    addRowFn = (features, static_values, varied_values) -> addRulesetsVariationRow(rulesets_collection_id, features, static_values, varied_values)
    return addColumnsByPathsFn, prepareAddNewFn, addRowFn
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

compressSimulationIDs(simulation_ids::Array{Int}) = simulation_ids |> vec |> sort |> compressIDs
compressMonadIDs(monad_ids::Array{Int}) = monad_ids |> vec |> sort |> compressIDs
compressSamplingIDs(sampling_ids::Array{Int}) = sampling_ids |> vec |> sort |> compressIDs

################## Selection Functions ##################

function selectConstituents(path_to_csv::String)
    if !isfile(path_to_csv)
        return Int[]
    end
    df = CSV.read(path_to_csv, DataFrame; header=false, silencewarnings=true, types=String, delim=",")
    ids = Int[]
    for i in axes(df,1)
        s = df.Column1[i]
        I = split(s,":") .|> string .|> x->parse(Int,x)
        if length(I)==1
            push!(ids,I[1])
        else
            append!(ids,I[1]:I[2])
        end
    end
    return ids
end

getMonadSimulations(monad_id::Int) = selectConstituents("$(data_dir)/outputs/monads/$(monad_id)/simulations.csv")
getMonadSimulations(monad::Monad) = getMonadSimulations(monad.id)
getSamplingMonads(sampling_id::Int) = selectConstituents("$(data_dir)/outputs/samplings/$(sampling_id)/monads.csv")
getSamplingMonads(sampling::Sampling) = getSamplingMonads(sampling.id)
getTrialSamplings(trial_id::Int) = selectConstituents("$(data_dir)/outputs/trials/$(trial_id)/samplings.csv")
getTrialSamplings(trial::Trial) = getTrialSamplings(trial.id)

function getSamplingSimulations(sampling_id::Int)
    monad_ids = getSamplingMonads(sampling_id)
    return vcat([getMonadSimulations(monad_id) for monad_id in monad_ids]...)
end

function getTrialSimulations(trial_id::Int)
    sampling_ids = getTrialSamplings(trial_id)
    return vcat([getSamplingSimulations(sampling_id) for sampling_id in sampling_ids]...)
end

getSimulations() = constructSelectQuery("simulations", "", selection="simulation_id") |> queryToDataFrame |> x -> x.simulation_id
getSimulations(simulation::Simulation) = [simulation.id]
getSimulations(monad::Monad) = getMonadSimulations(monad)
getSimulations(sampling::Sampling) = getSamplingSimulations(sampling)
getSimulations(trial::Trial) = getTrialSimulations(trial)

function getSimulations(class_id::VCTClassID) 
    class_id_type = getVCTClassIDType(class_id)
    if class_id_type == Simulation
        return [class_id.id]
    elseif class_id_type == Monad
        return getMonadSimulations(class_id.id)
    elseif class_id_type == Sampling
        return getSamplingSimulations(class_id.id)
    elseif class_id_type == Trial
        return getTrialSimulations(class_id.id)
    else
        error(error_string)
    end
end

end