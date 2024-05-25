module VCTModule

# each file (includes below) has their own export statements
export initializeVCT, resetDatabase, addGridVariation, addGridRulesetsVariation, runAbstractTrial, getTrialSamplings, getSimulations

using SQLite, DataFrames, LightXML, LazyGrids, Dates, CSV, Tables
using MAT, Statistics # files for VCTLoader.jl

include("VCTClasses.jl")
include("VCTDatabase.jl") 
include("VCTConfiguration.jl")
include("VCTExtraction.jl")
include("VCTLoader.jl")

physicell_dir::String = abspath("PhysiCell")
data_dir::String = abspath("data")
PHYSICELL_CPP::String = haskey(ENV, "PHYSICELL_CPP") ? ENV["PHYSICELL_CPP"] : "/opt/homebrew/bin/g++-13"

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
    println("Path to PhysiCell: $physicell_dir")
    println("Path to data: $data_dir")
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

function deleteSimulation(simulation_ids::Vector{Int}; delete_supers::Bool=true)
    sim_df = constructSelectQuery("simulations", "WHERE simulation_id IN ($(join(simulation_ids,",")));") |> queryToDataFrame
    DBInterface.execute(db,"DELETE FROM simulations WHERE simulation_id IN ($(join(simulation_ids,",")));")
    # for simulation_id in simulation_ids
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
    for monad_id in monad_ids
        monad_simulation_ids = getMonadSimulations(monad_id)
        if !any(x -> x in simulation_ids, monad_simulation_ids) # if none of the monad simulation ids are among those to be deleted, then nothing to do here
            continue
        end
        filter!(x -> !(x in simulation_ids), monad_simulation_ids)
        if isempty(monad_simulation_ids)
            deleteMonad([monad_id]; delete_subs=false, delete_supers=true)
        else
            recordSimulationIDs(monad_id, monad_simulation_ids)
        end
    end
    return nothing
end

deleteSimulation(simulation_id::Int; delete_supers::Bool=true) = deleteSimulation([simulation_id]; delete_supers=delete_supers)

function deleteMonad(monad_ids::Vector{Int}; delete_subs::Bool=true, delete_supers::Bool=true)
    DBInterface.execute(db,"DELETE FROM monads WHERE monad_id IN ($(join(monad_ids,",")));")
    for monad_id in monad_ids
        if delete_subs
            simulation_ids = getMonadSimulations(monad_id)
            deleteSimulation(simulation_ids; delete_supers=false)
        end
        rm("$(data_dir)/outputs/monads/$(monad_id)", force=true, recursive=true)
    end

    if !delete_supers
        return nothing
    end
    sampling_ids = constructSelectQuery("samplings", "", selection="sampling_id") |> queryToDataFrame |> x -> x.sampling_id
    for sampling_id in sampling_ids
        sampling_monad_ids = getSamplingMonads(sampling_id)
        if !any(x -> x in monad_ids, sampling_monad_ids) # if none of the sampling monad ids are among those to be deleted, then nothing to do here
            continue
        end
        filter!(x -> !(x in monad_ids), sampling_monad_ids)
        if isempty(sampling_monad_ids)
            deleteSampling([sampling_id]; delete_subs=false, delete_supers=true)
        else
            recordMonadIDs(sampling_id, sampling_monad_ids)
        end
    end
    return nothing
end

deleteMonad(monad_id::Int; delete_subs::Bool=true, delete_supers::Bool=true) = deleteMonad([monad_id]; delete_subs=delete_subs, delete_supers=delete_supers)

function deleteSampling(sampling_ids::Vector{Int}; delete_subs::Bool=true, delete_supers::Bool=true)
    DBInterface.execute(db,"DELETE FROM samplings WHERE sampling_id IN ($(join(sampling_ids,",")));")
    for sampling_id in sampling_ids
        if delete_subs
            monad_ids = getSamplingMonads(sampling_id)
            deleteMonad(monad_ids; delete_subs=true, delete_supers=false)
        end
        rm("$(data_dir)/outputs/samplings/$(sampling_id)", force=true, recursive=true)
    end

    if !delete_supers
        return nothing
    end

    trial_ids = constructSelectQuery("trials", "", selection="trial_id") |> queryToDataFrame |> x -> x.trial_id
    for trial_id in trial_ids
        trial_sampling_ids = getTrialSamplings(trial_id)
        if !any(x -> x in sampling_ids, trial_sampling_ids) # if none of the trial sampling ids are among those to be deleted, then nothing to do here
            continue
        end
        filter!(x -> !(x in sampling_ids), trial_sampling_ids)
        if isempty(trial_sampling_ids)
            deleteTrial([trial_id]; delete_subs=false)
        else
            recordSamplingIDs(trial_id, trial_sampling_ids)
        end
    end
    return nothing
end

deleteSampling(sampling_id::Int; delete_subs::Bool=true, delete_supers::Bool=true) = deleteSampling([sampling_id]; delete_subs=delete_subs, delete_supers=delete_supers)

function deleteTrial(trial_ids::Vector{Int}; delete_subs::Bool=true)
    DBInterface.execute(db,"DELETE FROM trials WHERE trial_id IN ($(join(trial_ids,",")));")
    for trial_id in trial_ids
        if delete_subs
            sampling_ids = getTrialSamplings(trial_id)
            deleteSampling(sampling_ids; delete_subs=true, delete_supers=false)
        end
        rm("$(data_dir)/outputs/trials/$(trial_id)", force=true, recursive=true)
    end
    return nothing
end

deleteTrial(trial_id::Int; delete_subs::Bool=true) = deleteTrial([trial_id]; delete_subs=delete_subs)

function resetDatabase()
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

function addColumns(xml_paths::Vector{Vector{String}}, table_name::String, id_column_name::String, db_columns::SQLite.DB, path_to_xml::String, dataTypeRules::Function)
    column_names = queryToDataFrame("PRAGMA table_info($(table_name));"; db=db_columns) |> x->x[!,:name]
    filter!(x -> x != id_column_name, column_names)
    varied_column_names = [join(xml_path,"/") for xml_path in xml_paths]

    is_new_column = [!(varied_column_name in column_names) for varied_column_name in varied_column_names]
    if any(is_new_column)
        new_column_names = varied_column_names[is_new_column]
        xml_doc = openXML(path_to_xml)
        default_values_for_new = [getField(xml_doc, xml_path) for xml_path in xml_paths[is_new_column]]
        closeXML(xml_doc)
        for (i, new_column_name) in enumerate(new_column_names)
            sqlite_data_type = dataTypeRules(i, new_column_name)
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
    dataTypeRules = (i, _) -> begin
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
    return addColumns(xml_paths, "variations", "variation_id", db_columns, path_to_xml, dataTypeRules)
end

function addRulesetsVariationsColumns(rulesets_collection_id::Int, xml_paths::Vector{Vector{String}})
    rulesets_collection_folder = getRulesetsCollectionFolder(rulesets_collection_id)
    db_columns = getRulesetsVariationsDB(rulesets_collection_folder)
    path_to_xml = "$(data_dir)/inputs/rulesets_collections/$(rulesets_collection_folder)/base_rulesets.xml"
    dataTypeRules = (_, name) -> "applies_to_dead" in name ? "INT" : "REAL"
    return addColumns(xml_paths, "rulesets_variations", "rulesets_variation_id", db_columns, path_to_xml, dataTypeRules)
end

function addRow(db_columns::SQLite.DB, table_name::String, id_name::String, table_features::String, values::String)
    new_id = DBInterface.execute(db_columns, "INSERT OR IGNORE INTO $(table_name) ($(table_features)) VALUES($(values)) RETURNING $(id_name);") |> DataFrame |> x->x[!,1]
    new_added = length(new_id)==1
    if  !new_added
        query = constructSelectQuery(table_name, "WHERE ($(table_features))=($(values))"; selection=id_name)
        new_id = queryToDataFrame(query, db=db_columns) |> x->x[!,1]
    end
    return new_id[1], new_added
end

function addVariationRow(config_id::Int, table_features::String, values::String)
    db_columns = getConfigDB(config_id)
    return addRow(db_columns, "variations", "variation_id", table_features, values)
end

function addVariationRow(config_id::Int, table_features::String, static_values::String, varied_values::String)
    return addVariationRow(config_id, table_features, "$(static_values)$(varied_values)")
end

function addRulesetsVariationRow(rulesets_collection_id::Int, table_features::String, values::String)
    db_columns = getRulesetsVariationsDB(rulesets_collection_id)
    return addRow(db_columns, "rulesets_variations", "rulesets_variation_id", table_features, values)
end

function addRulesetsVariationRow(rulesets_collection_id::Int, table_features::String, static_values::String, varied_values::String)
    return addRulesetsVariationRow(rulesets_collection_id, table_features, "$(static_values)$(varied_values)")
end

function addGrid(EV::Vector{<:ElementaryVariation}, addColumnsByPaths::Function, prepareAddNew::Function, addRow::Function)
    xml_paths = [ev.xml_path for ev in EV]
    new_values = [ev.values for ev in EV]

    static_column_names, varied_column_names = addColumnsByPaths(xml_paths)
    static_values, table_features = prepareAddNew(static_column_names, varied_column_names)

    NDG = ndgrid(new_values...)
    sz_variations = size(NDG[1])
    variation_ids = zeros(Int, sz_variations)
    is_new_variation_id = falses(sz_variations)
    for i in eachindex(NDG[1])
        varied_values = [A[i] for A in NDG] .|> string |> x -> join("\"" .* x .* "\"", ",")
        variation_ids[i], is_new_variation_id[i] = addRow(table_features, static_values, varied_values)
    end
    return variation_ids, is_new_variation_id
end

"""
    function addGridVariation(config_folder::String, EV::Vector{<:ElementaryVariation}; reference_variation_id::Int=0)

Adds a grid of parameter values defined by `EV` (a vector of `ElementaryVariation` objects) to the Variations table for a specified configuration.
A reference variation id can be supplied so that any currently unvaried values are pulled from that variation.
Each `ElementaryVariation` in `EV` represents a single parameter's variation across its range of values.
"""

function addGridVariation(config_id::Int, EV::Vector{<:ElementaryVariation}; reference_variation_id::Int=0)
    addColumnsByPaths = (paths) -> addVariationColumns(config_id, paths, [typeof(ev.values[1]) for ev in EV])
    prepareAddNew = (static_column_names, varied_column_names) -> prepareAddNewVariations(config_id, static_column_names, varied_column_names; reference_variation_id=reference_variation_id)
    addRow = (features, static_values, varied_values) -> addVariationRow(config_id, features, static_values, varied_values)
    return addGrid(EV, addColumnsByPaths, prepareAddNew, addRow)
end

addGridVariation(config_folder::String, EV::Vector{<:ElementaryVariation}; reference_variation_id::Int=0) = addGridVariation(retrieveID("configs", config_folder), EV; reference_variation_id=reference_variation_id)

# allow for passing in a single ElementaryVariation object
addGridVariation(config_id::Int, EV::ElementaryVariation; reference_variation_id::Int=0) = addGridVariation(config_id, [EV]; reference_variation_id=reference_variation_id)
addGridVariation(config_folder::String, EV::ElementaryVariation; reference_variation_id::Int=0) = addGridVariation(config_folder, [EV]; reference_variation_id=reference_variation_id)

function addGridRulesetsVariation(rulesets_collection_id::Int, EV::Vector{<:ElementaryVariation}; reference_rulesets_variation_id::Int=0)
    addColumnsByPaths = (paths) -> addRulesetsVariationsColumns(rulesets_collection_id, paths)
    prepareAddNew = (static_names, varied_names) -> prepareAddNewRulesetsVariations(rulesets_collection_id, static_names, varied_names; reference_rulesets_variation_id=reference_rulesets_variation_id)
    addRow = (features, static_values, varied_values) -> addRulesetsVariationRow(rulesets_collection_id, features, static_values, varied_values)
    return addGrid(EV, addColumnsByPaths, prepareAddNew, addRow)
end

addGridRulesetsVariation(rulesets_collection_folder::String, EV::Vector{<:ElementaryVariation}; reference_rulesets_variation_id::Int=0) = addGridRulesetsVariation(retrieveID("rulesets_collections", rulesets_collection_folder), EV; reference_rulesets_variation_id=reference_rulesets_variation_id)

# allow for passing in a single ElementaryVariation object
addGridRulesetsVariation(rulesets_collection_id::Int, EV::ElementaryVariation; reference_rulesets_variation_id::Int=0) = addGridRulesetsVariation(rulesets_collection_id, [EV]; reference_rulesets_variation_id=reference_rulesets_variation_id)
addGridRulesetsVariation(rulesets_collection_folder::String, EV::ElementaryVariation; reference_rulesets_variation_id::Int=0) = addGridRulesetsVariation(rulesets_collection_folder, [EV]; reference_rulesets_variation_id=reference_rulesets_variation_id)

function prepareAddNew(db_columns::SQLite.DB, static_column_names::Vector{String}, varied_column_names::Vector{String}, table_name::String, id_name::String, reference_id::Int)
    if isempty(static_column_names)
        static_values = ""
        table_features = ""
    else
        query = constructSelectQuery(table_name, "WHERE $(id_name)=$(reference_id);"; selection=join("\"" .* static_column_names .* "\"", ", "))
        static_values = queryToDataFrame(query, db=db_columns) |> x -> (x |> eachcol .|> c -> "\"$(string(c[1]))\"", ",")
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
    db_columns = getRulesetsVariationsDB(rulesets_collection_id)
    return prepareAddNew(db_columns, static_column_names, varied_column_names, "rulesets_variations", "rulesets_variation_id", reference_rulesets_variation_id)
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
getSamplingMonads(sampling_id::Int) = selectConstituents("$(data_dir)/outputs/samplings/$(sampling_id)/monads.csv")
getTrialSamplings(trial_id::Int) = selectConstituents("$(data_dir)/outputs/trials/$(trial_id)/samplings.csv")
getTrialSamplings(trial::Trial) = getTrialSamplings(trial.id)

function getTrialSimulations(trial_id::Int)
    sampling_ids = getTrialSamplings(trial_id)
    return vcat([getSamplingSimulations(sampling_id) for sampling_id in sampling_ids]...)
end

function getSamplingSimulations(sampling_id::Int)
    monad_ids = getSamplingMonads(sampling_id)
    return vcat([getMonadSimulations(monad_id) for monad_id in monad_ids]...)
end

getSimulations(trial::Trial) = getTrialSimulations(trial.id)
getSimulations(sampling::Sampling) = getSamplingSimulations(sampling.id)
getSimulations(monad::Monad) = getMonadSimulations(monad.id)
getSimulations(simulation::Simulation) = [simulation.id]

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