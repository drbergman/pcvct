module VCTModule

export initializeVCT, resetDatabase, selectTrialSimulations

using SQLite, DataFrames, LightXML, LazyGrids, Dates, CSV, Tables
include("VCTClasses.jl")
include("VCTDatabase.jl")
include("VCTConfiguration.jl")
include("VCTExtraction.jl")


# I considered doing this with a structure of parameters, but I don't think that will work well here:
#   1. the main purpose would be to make this thread safe, but one machine will not run multiple sims at once most likely
#   2. Even if we did run multiple at once, it would need to be from the same executable file, so all the global variables would be the same for all
#   3. The cost of checking the global scope is absolutely minimal compared to the simulations I'm running, so who cares about

physicell_dir::String = abspath("PhysiCell")
data_dir::String = abspath("data")
PHYSICELL_CPP::String = "/opt/homebrew/bin/g++-13"

function initializeVCT(path_to_physicell::String, path_to_data::String)
    println("----------INITIALIZING----------")
    global physicell_dir = abspath(path_to_physicell)
    global data_dir = abspath(path_to_data)
    initializeDatabase("$(data_dir)/vct.db")
end

function getSimulationCmd(simulation::Simulation; setup=true)
    return `$(physicell_dir)/project $(physicell_dir)/config/base_config_$(simulation.base_config_id)/variation_$(simulation.variation_id).xml $(path_to_simulation_folder)`
end

function runSimulation(simulation::Simulation; setup=true)
    println("------------------------------\n----------SETTING UP SIMULATION----------\n------------------------------")
    path_to_simulation_folder = "$(data_dir)/outputs/simulations/$(simulation.id)/output"
    if isfile("$(path_to_simulation_folder)/final.xml")
        ran = false
        return ran
    end
    mkpath(path_to_simulation_folder)

    if setup
        loadConfiguration!(simulation)
        loadCustomCode!(simulation)
    end

    executable_str = "$(data_dir)/inputs/custom_codes/$(simulation.custom_code_folder)/project" # path to executable
    config_str =  "$(data_dir)/inputs/base_configs/$(simulation.base_config_folder)/variations/variation_$(simulation.variation_id).xml" # path to config file
    flags = ["-o", path_to_simulation_folder]
    if simulation.ic_id != -1
        append!(flags, ["-i", "$(data_dir)/inputs/ics/$(simulation.ic_folder)/cells.csv"]) # if ic file included (id != -1), then include this in the command
    end
    if simulation.rulesets_variation_id != -1
        # for now, no rules file specified as flagged argument
        path_to_rules_file = "$(data_dir)/inputs/base_configs/$(simulation.base_config_folder)/rulesets_collections/$(simulation.rulesets_collection_folder)/rulesets_variation_$(simulation.rulesets_variation_id).xml"
        append!(flags, ["-r", path_to_rules_file])
    end
    cmd = `$executable_str $config_str $flags`
    
    println("\n----------RUNNING SIMULATION----------\n\n$cmd\n")
    run(cmd, wait=true)
    ran = true
    return ran
end

# function loadIC!(simulation::Union{Simulation,Monad,Sampling})
#     if simulation.ic_id==-1 || simulation.ic_id == current_ic_id
#         return 0
#     end
#     if isempty(simulation.ic_folder)
#         simulation.ic_folder = selectRow("folder_name", "ics", "WHERE ic_id=$(simulation.ic_id);")
#     end
#     path_to_folder = "$(data_dir)/ics/$(simulation.ic_folder)/" # source dir needs to end in / or else the dir is copied into target, not the source files
#     global current_ic_id = simulation.ic_id
#     return run(`cp -r $(path_to_folder) $(physicell_dir)/config`) 
# end

function loadCustomCode!(simulation::Union{Simulation,Monad,Sampling})
    if isfile("$(data_dir)/inputs/custom_codes/$(simulation.custom_code_folder)/project")
        return
    end
    if isempty(simulation.custom_code_folder)
        simulation.custom_code_folder = selectRow("folder_name", "custom_codes", "WHERE custom_code_id=$(simulation.custom_code_id);")
    end
    path_to_folder = "$(data_dir)/inputs/custom_codes/$(simulation.custom_code_folder)" # source dir needs to end in / or else the dir is copied into target, not the source files
    run(`cp -r $(path_to_folder)/custom_modules/ $(physicell_dir)/custom_modules`)
    run(`cp $(path_to_folder)/main.cpp $(physicell_dir)/main.cpp`)
    run(`cp $(path_to_folder)/Makefile $(physicell_dir)/Makefile`)

    cd(()->run(`make CC=$(PHYSICELL_CPP) PROGRAM_NAME=project_ccid_$(simulation.custom_code_id)`), physicell_dir) # compile the custom code in the PhysiCell directory and return to the original directory

    mv("$(physicell_dir)/project_ccid_$(simulation.custom_code_id)", "$(data_dir)/inputs/custom_codes/$(simulation.custom_code_folder)/project")
    return 
end

function deleteSimulation(simulation_ids::Vector{Int})
    DBInterface.execute(db,"DELETE FROM simulations WHERE simulation_id IN ($(join(simulation_ids,",")));")
    for simulation_id in simulation_ids
        rm("$(data_dir)/outputs/simulations/$(simulation_id)", force=true, recursive=true)
    end

    if !(DBInterface.execute(db, "SELECT name FROM sqlite_master WHERE type='table' AND name='trials';") |> isempty)
        trial_ids = DBInterface.execute(db, "SELECT trial_id FROM trials;") |> DataFrame |> x -> x.trial_id
        for trial_id in trial_ids
            trial_simulation_ids = selectTrialSimulations(trial_id)
            filter!(x -> !(x in simulation_ids), trial_simulation_ids)
            if isempty(trial_simulation_ids)
                deleteTrial([trial_id])
            else
                recordTrialSimulationIDs(trial_id, trial_simulation_ids)
            end
        end
    end

    return nothing
end

deleteSimulation(simulation_id::Int) = deleteSimulation([simulation_id])

# function trialRowToIds(r::String)
#     if !contains(r,":")
#         return parse(Int,r)
#     end
#     # otherwise has a colon and need to expand
#     s = split(r,":") .|> String .|> x->parse(Int,x)
#     return collect(s[1]:s[2])
# end

# function deleteTrial(trial_ids::Vector{Int})
#     DBInterface.execute(getDB(),"DELETE FROM trials WHERE trial_id IN ($(join(trial_ids,",")));")
#     for trial_id in trial_ids
#         selectTrialSimulations(trial_id) |> deleteSimulation
#         run(`rm -rf $(data_dir)/outputs/trials/$(trial_id)`)
#     end
#     return nothing
# end

# deleteTrial(trial_id::Int) = deleteTrial([trial_id])

function resetDatabase()

    rm("$(data_dir)/outputs/simulations", force=true, recursive=true)
    rm("$(data_dir)/outputs/monads", force=true, recursive=true)
    rm("$(data_dir)/outputs/samplings", force=true, recursive=true)
    rm("$(data_dir)/outputs/trials", force=true, recursive=true)

    for base_config_folder in (readdir("$(data_dir)/inputs/base_configs/", sort=false, join=true) |> filter(x->isdir(x)))
        resetConfigFolder(base_config_folder)
    end
    
    base_config_folders = DBInterface.execute(db, "SELECT folder_name FROM base_configs;") |> DataFrame |> x->x.folder_name
    for base_config_folder in base_config_folders
        resetConfigFolder("$(data_dir)/inputs/base_configs/$(base_config_folder)")
    end

    for custom_code_folder in (readdir("$(data_dir)/inputs/custom_codes/", sort=false, join=true) |> filter(x->isdir(x)))
        rm("$(custom_code_folder)/project", force=true)
    end

    custom_code_folders = DBInterface.execute(db, "SELECT folder_name FROM custom_codes;") |> DataFrame |> x->x.folder_name
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

function resetConfigFolder(base_config_folder::String)
    rm("$(base_config_folder)/variations.db", force=true)
    rm("$(base_config_folder)/variations", force=true, recursive=true)

    rm("$(base_config_folder)/rulesets_collections.db", force=true)

    for rulesets_collection_folder in (readdir("$(base_config_folder)/rulesets_collections/", sort=false, join=true) |> filter(x->isdir(x)))
        resetRulesetsCollectionFolder(rulesets_collection_folder)
    end

    # first check that the rulesets_collections table exists
    if DBInterface.execute(getRulesetsCollectionsDB(base_config_folder), "SELECT name FROM sqlite_master WHERE type='table' AND name='rulesets_collections';") |> isempty
        return
    end
    rulesets_collection_folders = DBInterface.execute(getRulesetsCollectionsDB(base_config_folder), "SELECT folder_name FROM rulesets_collections;") |> DataFrame |> x->x.folder_name
    for rulesets_collection_folder in rulesets_collection_folders
        resetRulesetsCollectionFolder("$(base_config_folder)/rulesets_collections/$(rulesets_collection_folder)")
    end
    return nothing
end

function resetRulesetsCollectionFolder(rulesets_collection_folder::String)
    rm("$(rulesets_collection_folder)/rulesets_variations.db", force=true)
    for rulesets_variation in (readdir("$(rulesets_collection_folder)/", sort=false, join=true) |> filter(x->occursin(r"rulesets_variation_\d+.xml", x)))
        rm(rulesets_variation, force=true)
    end
    rm("$(rulesets_collection_folder)/rulesets_variation_*", force=true)
    return nothing
end

function runMonad!(monad::Monad; use_previous_sims::Bool=false, setup::Bool=true)
    mkpath("$(data_dir)/outputs/monads/$(monad.id)")
    n_new_simulations = monad.min_length
    if use_previous_sims
        n_new_simulations -= length(monad.simulation_ids)
    end

    if n_new_simulations <= 0
        return Task[]
    end

    if setup
        loadCustomCode!(monad)
    end
    loadConfiguration!(monad)

    simulation_tasks = Task[]
    for i in 1:n_new_simulations
        simulation = Simulation(monad)
        push!(simulation_tasks, @task runSimulation(simulation, setup=false))
        push!(monad.simulation_ids, simulation.id)
    end

    recordSimulationIDs(monad)

    return simulation_tasks
end

function recordSimulationIDs(monad::Monad)
    path_to_folder = "$(data_dir)/outputs/monads/$(monad.id)/"
    mkpath(path_to_folder)
    path_to_csv = "$(path_to_folder)/simulations.csv"
    lines_table = compressSimulationIDs(monad.simulation_ids)
    CSV.write(path_to_csv, lines_table; writeheader=false)
end

function runSampling!(sampling::Sampling; use_previous_sims::Bool=false)
    mkpath("$(data_dir)/outputs/samplings/$(sampling.id)")

    loadCustomCode!(sampling)

    simulation_tasks = []
    for (variation_id, rulesets_variation_id) in zip(sampling.variation_ids, sampling.rulesets_variation_ids)
        monad = Monad(sampling, variation_id, rulesets_variation_id) # instantiate a monad with the variation_id and the simulation ids already found
        append!(simulation_tasks, runMonad!(monad, use_previous_sims=use_previous_sims, setup=false)) # run the monad and add the number of new simulations to the total
    end

    recordMonadIDs(sampling) # record the monad ids in the sampling
    return simulation_tasks
end

function recordMonadIDs(sampling_id::Int, monad_ids::Array{Int})
    recordMonadIDs("$(data_dir)/outputs/samplings/$(sampling_id)", monad_ids)
end

function recordMonadIDs(sampling::Sampling)
    recordMonadIDs("$(data_dir)/outputs/samplings/$(sampling.id)", sampling.monad_ids)
end

function recordMonadIDs(path_to_folder::String, monad_ids::Array{Int})
    path_to_size_csv = "$(path_to_folder)/size.csv"
    size_table = [string.(size(monad_ids))...] |> Tables.table
    CSV.write(path_to_size_csv, size_table; writeheader=false)

    path_to_csv = "$(path_to_folder)/monads.csv"
    lines_table = compressMonadIDs(monad_ids)
    CSV.write(path_to_csv, lines_table; writeheader=false)
end

# function compressMonadIDs(monad_ids::Array{Int})
#     lines = String[]
#     monad_ids = vec(monad_ids)
#     while !isempty(monad_ids)
#         if length(monad_ids) == 1
#             next_line = string(monad_ids[1])
#             popfirst!(monad_ids)
#         else
#             I = findfirst(diff(monad_ids) .> 1)
#             I = isnothing(I) ? length(monad_ids) : I # if none found, then all the diffs are 1 so we want to take the entire list
#             if I > 1
#                 next_line = "$(monad_ids[1]):$(monad_ids[I])"
#                 monad_ids = monad_ids[I+1:end]
#             else
#                 next_line = string(monad_ids[1])
#                 popfirst!(monad_ids)
#             end
#         end
#         push!(lines, next_line)
#     end
#     return Tables.table(lines)
# end

function runTrial!(trial::Trial; use_previous_sims::Bool=false)
    mkpath("$(data_dir)/outputs/trials/$(trial.id)")

    simulation_tasks = []
    for i in eachindex(trial.sampling_ids)
        sampling = Sampling(trial, i) # instantiate a sampling with the variation_ids and the simulation ids already found
        append!(simulation_tasks, runSampling!(sampling, use_previous_sims=use_previous_sims)) # run the sampling and add the number of new simulations to the total
    end

    recordSamplingIDs(trial) # record the sampling ids in the trial
    return simulation_tasks
end

function recordSamplingIDs(trial_id::Int, sampling_ids::Array{Int})
    recordSamplingIDs("$(data_dir)/outputs/trials/$(trial_id)", sampling_ids)
end

function recordSamplingIDs(trial::Trial)
    recordSamplingIDs("$(data_dir)/outputs/trials/$(trial.id)", trial.sampling_ids)
end

function recordSamplingIDs(path_to_folder::String, sampling_ids::Array{Int})
    path_to_size_csv = "$(path_to_folder)/size.csv"
    size_table = [string.(size(sampling_ids))...] |> Tables.table
    CSV.write(path_to_size_csv, size_table; writeheader=false)

    path_to_csv = "$(path_to_folder)/samplings.csv"
    lines_table = compressSamplingIDs(sampling_ids)
    CSV.write(path_to_csv, lines_table; writeheader=false)
end

collectSimulationTasks(simulation::Simulation; use_previous_sims::Bool=false) = [@task runSimulation(simulation, setup=false)]
collectSimulationTasks(monad::Monad; use_previous_sims::Bool=false) = runMonad!(monad, use_previous_sims=use_previous_sims)
collectSimulationTasks(sampling::Sampling; use_previous_sims::Bool=false) = runSampling!(sampling, use_previous_sims=use_previous_sims)
collectSimulationTasks(trial::Trial; use_previous_sims::Bool=false) = runTrial!(trial, use_previous_sims=use_previous_sims)

function runAbstractTrial(trial::AbstractTrial; use_previous_sims::Bool=false)
    simulation_tasks = collectSimulationTasks(trial, use_previous_sims=use_previous_sims)

    Threads.@threads :static for simulation_task in simulation_tasks
        schedule(simulation_task)
        fetch(simulation_task)
    end
end

# function runVirtualClinicalTrial(patient_ids::Union{Int,Vector{Int}}, variation_ids::Vector{Vector{Int}}, cohort_ids::Union{Int,Vector{Int}}, num_replicates::Int; use_previous_sims::Bool = false, description::String = String[])
#     time_started  = now()
#     num_patients = length(patient_ids)
#     @assert num_patients == length(variation_ids) # make sure each patient has their own variation ids assigned
#     simulation_ids = Int[]
#     for i in 1:num_patients
#         patient_id = patient_ids[i]
#         variation_table_name = "patient_variations_$(patient_id)"
#         for cohort_id in cohort_ids
#             df = DBInterface.execute(db, "SELECT folder_id,path FROM folders WHERE patient_id=$(patient_id) AND cohort_id=$(cohort_id)") |> DataFrame
#             path_to_xml = df.path[1]
#             copyMakeFolderFiles(df.folder_id[1])
#             path_to_xml = selectRow("path","folders","WHERE patient_id=$(patient_id) AND cohort_id=$(cohort_id)") * "config/PhysiCell_settings.xml"
#             for variation_id in variation_ids[i]
#                 monad = Monad(monad_id, num_replicates, Int[], patient_id, variation_id, cohort_id)
#                 variation_row = selectRow(variation_table_name,"WHERE variation_id=$(variation_id);")
#                 loadConfiguration(path_to_xml, variation_row, physicell_dir)
#                 # append!(simulation_ids, runReplicates(patient_id, variation_id, cohort_id, num_replicates; use_previous_sims=use_previous_sims))
#                 append!(simulation_ids, runMonad!(monad; use_previous_sims=use_previous_sims))
#             end
#         end
#     end
#     recordTrialInfo(simulation_ids, time_started, description)
#     return nothing
# end

# function runVirtualClinicalTrial(patient_ids::Int, variation_ids::Vector{Int}, cohort_ids::Union{Int,Vector{Int}}, num_replicates::Int; use_previous_sims::Bool=false, description::String=String[])
#     return runVirtualClinicalTrial(patient_ids, [variation_ids], cohort_ids, num_replicates; use_previous_sims=use_previous_sims, description=description)
# end

# function runVirtualClinicalTrial(patient_ids::Union{Int,Vector{Int}}, cohort_ids::Union{Int,Vector{Int}}, num_replicates::Int; use_previous_sims::Bool=false, description::String=String[])
#     variation_ids = [(DBInterface.execute(db, "SELECT variation_id FROM patient_variations_$(patient_id);") |> DataFrame |> x -> Vector(x.variation_id)) for patient_id in patient_ids]
#     return runVirtualClinicalTrial(patient_ids, variation_ids, cohort_ids, num_replicates; use_previous_sims=use_previous_sims, description=description)
# end

# function addPatient(patient_name::String,path_to_control_folder::String)
#     db = getDB()
#     df = DBInterface.execute(db, "SELECT patient_id FROM folders WHERE path='$(path_to_control_folder)';") |> DataFrame
#     if !isempty(df)
#         println("This folder location is already present. No patient added.")
#         return df.patient_id[1]
#     end
#     patient_id = DBInterface.execute(db, "INSERT INTO patients (patient_name) VALUES('$(patient_name)') RETURNING patient_id;") |> DataFrame |> x->x.patient_id[1]
#     table_name = "patient_variations_$(patient_id)"
#     DBInterface.execute(db, "CREATE TABLE $(table_name) (
#         variation_id INTEGER PRIMARY KEY
#         )
#     ")
#     DBInterface.execute(db, "INSERT INTO $(table_name) (variation_id) VALUES(0);")
#     DBInterface.execute(db, "INSERT INTO folders (patient_id, cohort_id, path) VALUES($(patient_id),$(control_cohort_id),'$(path_to_control_folder)');")
    
#     path_to_xml = path_to_control_folder * "config/PhysiCell_settings.xml"
#     path_to_default_xml = path_to_control_folder * "config/PhysiCell_settings_default.xml"
#     run(`cp $(path_to_xml) $(path_to_default_xml)`)
#     return patient_id
# end

# function addGVAX(patient_id::Int; cd4_multiplier::AbstractFloat=10., cd8_multiplier::AbstractFloat=2.)
#     db = getDB()
#     gvax_cohort_id = DBInterface.execute(db, "SELECT cohort_id FROM cohorts WHERE intervention='gvax';") |> DataFrame |> x->x.cohort_id
#     if isempty(gvax_cohort_id)
#         gvax_cohort_id = DBInterface.execute(db, "INSERT INTO cohorts (intervention) VALUES('gvax') RETURNING cohort_id;") |> DataFrame |> x->x.cohort_id[1]
#     else
#         gvax_cohort_id = gvax_cohort_id[1]
#     end
#     path_to_control_folder = DBInterface.execute(db, "SELECT path FROM folders WHERE patient_id=$(patient_id) AND cohort_id=$(control_cohort_id);") |> DataFrame |> x->x.path[1]
#     path_to_folder = path_to_control_folder[1:end-1] * "_with_gvax/"
#     folder_id = DBInterface.execute(db, "INSERT OR IGNORE INTO folders (patient_id,cohort_id,path) 
#         VALUES
#             ($(patient_id),$(gvax_cohort_id),'$(path_to_folder)')
#         RETURNING folder_id;
#     ")
#     if isempty(folder_id)
#         println("A GVAX folder for this patient has already been created.")
#         return gvax_cohort_id
#     end
#     run(`cp -r $(path_to_control_folder) $(path_to_folder)`)
#     path_to_xml = path_to_folder * "config/PhysiCell_settings.xml"
#     openXML(path_to_xml)
#     multiplyField(["user_parameters","number_of_PD-1hi_CD4_Tcell"],cd4_multiplier)
#     multiplyField(["user_parameters","number_of_PD-1lo_CD4_Tcell"],cd4_multiplier)
#     multiplyField(["user_parameters","number_of_PD-1hi_CD137hi_CD8_Tcell"],cd8_multiplier)
#     multiplyField(["user_parameters","number_of_PD-1lo_CD137hi_CD8_Tcell"],cd8_multiplier)
#     multiplyField(["user_parameters","number_of_PD-1hi_CD137lo_CD8_Tcell"],cd8_multiplier)
#     multiplyField(["user_parameters","number_of_PD-1lo_CD137lo_CD8_Tcell"],cd8_multiplier)
#     save_file(getXML(), path_to_xml)
#     closeXML()
#     return gvax_cohort_id
# end

# function addVariationColumns(base_config_id::Int, xml_paths::Vector{Vector{String}}, variable_types::Vector{DataType})
#     base_config_folder = DBInterface.execute(db, "SELECT folder_name FROM base_configs WHERE (base_config_id)=($(base_config_id));") |> DataFrame |> x->x.folder_name[1]
#     db_config = getConfigDB(base_config_id)
#     column_names = DBInterface.execute(db_config, "PRAGMA table_info(variations);") |> DataFrame |> x->x[!,:name]
#     filter!(x->x!="variation_id",column_names)
#     varied_column_names = [join(xml_path,"/") for xml_path in xml_paths]

#     is_new_column = [!(varied_column_name in column_names) for varied_column_name in varied_column_names]
#     if any(is_new_column)
#         new_column_names = varied_column_names[is_new_column]
#         new_column_data_types = variable_types[is_new_column]

#         path_to_xml = "$(data_dir)/inputs/base_configs/$(base_config_folder)/PhysiCell_settings.xml"
#         xml_doc = openXML(path_to_xml)
#         default_values_for_new = [getField(xml_doc, xml_path) for xml_path in xml_paths[is_new_column]]
#         closeXML(xml_doc)
#         # for (i, new_column_name) in enumerate(new_column_names)
#         for (new_column_name, new_column_data_type) in zip(new_column_names, new_column_data_types)
#             if new_column_data_type == Bool
#                 sqlite_data_type = "TEXT"
#             elseif new_column_data_type <: Int
#                 sqlite_data_type = "INT"
#             elseif new_column_data_type <: Real
#                 sqlite_data_type = "REAL"
#             else
#                 sqlite_data_type = "TEXT"
#             end
#             DBInterface.execute(db_config, "ALTER TABLE variations ADD COLUMN '$(new_column_name)' $(sqlite_data_type);")
#         end
#         DBInterface.execute(db_config, "UPDATE variations SET ($(join("\"".*new_column_names.*"\"",",")))=($(join("\"".*default_values_for_new.*"\"",",")));") # set newly added columns to default values

#         index_name = "variations_index"
#         SQLite.dropindex!(db_config, index_name; ifexists=true) # remove previous index
#         index_columns = deepcopy(column_names)
#         append!(index_columns, new_column_names)
#         SQLite.createindex!(db_config, "variations", index_name, index_columns; unique=true, ifnotexists=false) # add new index to make sure no variations are repeated
#     end

#     static_column_names = deepcopy(column_names)
#     old_varied_names = varied_column_names[.!is_new_column]
#     filter!( x->!(x in old_varied_names) , static_column_names)

#     return static_column_names, varied_column_names
# end

# function addRulesetsVariationsColumns(base_config_id::Int, rulesets_collection_id::Int, xml_paths::Vector{Vector{String}})
#     base_config_folder = DBInterface.execute(db, "SELECT folder_name FROM base_configs WHERE (base_config_id)=($(base_config_id));") |> DataFrame |> x->x.folder_name[1]
#     rulesets_collection_folder = getRulesetsCollectionFolder(base_config_folder, rulesets_collection_id)
#     db_rulesets_variations = getRulesetsVariationsDB(base_config_folder, rulesets_collection_folder)
#     column_names = DBInterface.execute(db_rulesets_variations, "PRAGMA table_info(rulesets_variations);") |> DataFrame |> x->x[!,:name]
#     filter!(x->x!="rulesets_variation_id",column_names)
#     varied_column_names = [join(xml_path,"/") for xml_path in xml_paths]

#     is_new_column = [!(varied_column_name in column_names) for varied_column_name in varied_column_names]
#     if any(is_new_column)
#         new_column_names = varied_column_names[is_new_column]

#         path_to_xml = "$(data_dir)/inputs/base_configs/$(base_config_folder)/rulesets_collections/$(rulesets_collection_folder)/base_rulesets.xml"
#         xml_doc = openXML(path_to_xml)
#         default_values_for_new = [getField(xml_doc, xml_path) for xml_path in xml_paths[is_new_column]]
#         closeXML(xml_doc)
#         for new_column_name in new_column_names
#             if "applies_to_dead" in new_column_name
#                 sqlite_data_type = "INT"
#             else
#                 sqlite_data_type = "REAL"
#             end
#             DBInterface.execute(db_rulesets_variations, "ALTER TABLE rulesets_variations ADD COLUMN '$(new_column_name)' $(sqlite_data_type);")
#         end
#         DBInterface.execute(db_rulesets_variations, "UPDATE rulesets_variations SET ($(join("\"".*new_column_names.*"\"",",")))=($(join("\"".*default_values_for_new.*"\"",",")));") # set newly added columns to default values

#         index_name = "rulesets_variations_index"
#         SQLite.dropindex!(db_rulesets_variations, index_name; ifexists=true) # remove previous index
#         index_columns = deepcopy(column_names)
#         append!(index_columns, new_column_names)
#         SQLite.createindex!(db_rulesets_variations, "rulesets_variations", index_name, index_columns; unique=true, ifnotexists=false) # add new index to make sure no variations are repeated
#     end

#     static_column_names = deepcopy(column_names)
#     old_varied_names = varied_column_names[.!is_new_column]
#     filter!( x->!(x in old_varied_names) , static_column_names)

#     return static_column_names, varied_column_names
# end

function addColumns(base_config_id::Int, xml_paths::Vector{Vector{String}}, table_name::String, id_column_name::String, getDB::Function, getBaseXML::Function, dataTypeRules::Function)
    base_config_folder = DBInterface.execute(db, "SELECT folder_name FROM base_configs WHERE (base_config_id)=($(base_config_id));") |> DataFrame |> x->x.folder_name[1]
    db_columns = getDB(base_config_folder)
    column_names = DBInterface.execute(db_columns, "PRAGMA table_info($(table_name));") |> DataFrame |> x->x[!,:name]
    filter!(x->x!=id_column_name,column_names)
    varied_column_names = [join(xml_path,"/") for xml_path in xml_paths]

    is_new_column = [!(varied_column_name in column_names) for varied_column_name in varied_column_names]
    if any(is_new_column)
        new_column_names = varied_column_names[is_new_column]
        path_to_xml = getBaseXML(base_config_folder)
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
    filter!( x->!(x in old_varied_names) , static_column_names)

    return static_column_names, varied_column_names
end

function addVariationColumns(base_config_id::Int, xml_paths::Vector{Vector{String}}, variable_types::Vector{DataType})
    getDB = (base_config_folder) -> getConfigDB(base_config_folder)
    getBaseXML = (base_config_folder) -> "$(data_dir)/inputs/base_configs/$(base_config_folder)/PhysiCell_settings.xml"
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
    return addColumns(base_config_id, xml_paths, "variations", "variation_id", getDB, getBaseXML, dataTypeRules)
end

function addRulesetsVariationsColumns(base_config_id::Int, rulesets_collection_id::Int, xml_paths::Vector{Vector{String}})
    rulesets_collection_folder = getRulesetsCollectionFolder(base_config_id, rulesets_collection_id)
    getDB = (base_config_folder) -> getRulesetsVariationsDB(base_config_folder, rulesets_collection_folder)
    getBaseXML = (base_config_folder) -> "$(data_dir)/inputs/base_configs/$(base_config_folder)/rulesets_collections/$(rulesets_collection_folder)/base_rulesets.xml"
    dataTypeRules = (_, name) -> "applies_to_dead" in name ? "INT" : "REAL"
    return addColumns(base_config_id, xml_paths, "rulesets_variations", "rulesets_variation_id", getDB, getBaseXML, dataTypeRules)
end



# function addVariationColumns(patient_id::Int, xml_paths::Vector{Vector{String}}, variable_types::Vector{DataType})
#     db = getDB()
#     table_name = "patient_variations_$(patient_id)"
#     column_names = DBInterface.execute(db, "PRAGMA table_info($(table_name));") |> DataFrame |> x->x[!,:name]
#     filter!(x->x!="variation_id",column_names)
#     varied_column_names = [join(xml_path,"/") for xml_path in xml_paths]

#     is_new_column = [!(varied_column_name in column_names) for varied_column_name in varied_column_names]
#     if any(is_new_column)
#         new_column_names = varied_column_names[is_new_column]

#         path_to_xml = selectRow("path", "folders", "WHERE patient_id=$(patient_id) AND cohort_id=$(control_cohort_id)")
#         path_to_xml *= "config/PhysiCell_settings.xml"
#         openXML(path_to_xml)
#         default_values_for_new = [getField(xml_path) for xml_path in xml_paths[is_new_column]]
#         closeXML()
#         for (i, new_column_name) in enumerate(new_column_names)
#             if variable_types[i] == Bool
#                 sqlite_data_type = "TEXT"
#             elseif variable_types[i] <: Int
#                 sqlite_data_type = "INT"
#             elseif variable_types[i] <: Real
#                 sqlite_data_type = "REAL"
#             else
#                 sqlite_data_type = "TEXT"
#             end
#             DBInterface.execute(db, "ALTER TABLE $(table_name) ADD COLUMN '$(new_column_name)' $(sqlite_data_type);")
#         end
#         DBInterface.execute(db, "UPDATE $(table_name) SET ($(join("\"".*new_column_names.*"\"",",")))=($(join("\"".*default_values_for_new.*"\"",",")));")

#         index_name = table_name * "_index"
#         SQLite.dropindex!(db, index_name; ifexists=true) # remove previous index
#         index_columns = deepcopy(column_names)
#         append!(index_columns, new_column_names)
#         SQLite.createindex!(db, table_name, index_name, index_columns; unique=true, ifnotexists=false) # add new index to make sure no variations are repeated
#     end

#     static_column_names = deepcopy(column_names)
#     old_varied_names = varied_column_names[.!is_new_column]
#     filter!( x->!(x in old_varied_names) , static_column_names)

#     return table_name, static_column_names, varied_column_names
# end

# function addVariationRow(base_config_id::Int, table_features::String, values::String)
#     db_config = getConfigDB(base_config_id)
#     new_variation_id = DBInterface.execute(db_config, "INSERT OR IGNORE INTO variations ($(table_features)) VALUES($(values)) RETURNING variation_id;") |> DataFrame |> x->x.variation_id
#     new_variation_added = length(new_variation_id)==1
#     if  !new_variation_added
#         new_variation_id = selectRow("variation_id", "variations", "WHERE ($(table_features))=($(values))"; db=db_config)
#     end
#     return new_variation_id[1], new_variation_added
# end

# function addRulesetsVariationRow(base_config_id::Int, rulesets_collection_id::Int, table_features::String, values::String)
#     db_rulesets_variations = getRulesetsVariationsDB(base_config_id, rulesets_collection_id)
#     new_rulesets_variation_id = DBInterface.execute(db_rulesets_variations, "INSERT OR IGNORE INTO rulesets_variations ($(table_features)) VALUES($(values)) RETURNING rulesets_variation_id;") |> DataFrame |> x->x.rulesets_variation_id
#     new_rulesets_variation_added = length(new_rulesets_variation_id)==1
#     if  !new_rulesets_variation_added
#         new_rulesets_variation_id = selectRow("rulesets_variation_id", "rulesets_variations", "WHERE ($(table_features))=($(values))"; db=db_rulesets_variations)
#     end
#     return new_rulesets_variation_id[1], new_rulesets_variation_added
# end

######

function addRow(db_columns::SQLite.DB, table_name::String, id_name::String, table_features::String, values::String)
    new_id = DBInterface.execute(db_columns, "INSERT OR IGNORE INTO $(table_name) ($(table_features)) VALUES($(values)) RETURNING $(id_name);") |> DataFrame |> x->x[!,1]
    new_added = length(new_id)==1
    if  !new_added
        new_id = selectRow(id_name, table_name, "WHERE ($(table_features))=($(values))"; db=db_columns)
    end
    return new_id[1], new_added
end

function addVariationRow(base_config_id::Int, table_features::String, values::String)
    db_columns = getConfigDB(base_config_id)
    return addRow(db_columns, "variations", "variation_id", table_features, values)
end

function addRulesetsVariationRow(base_config_id::Int, rulesets_collection_id::Int, table_features::String, values::String)
    db_columns = getRulesetsVariationsDB(base_config_id, rulesets_collection_id)
    return addRow(db_columns, "rulesets_variations", "rulesets_variation_id", table_features, values)
end

######

function addVariationRow(base_config_id::Int, table_features::String, static_values::String, varied_values::String)
    return addVariationRow(base_config_id, table_features, "$(static_values)$(varied_values)")
end

function addRulesetsVariationRow(base_config_id::Int, rulesets_collection_id::Int, table_features::String, static_values::String, varied_values::String)
    return addRulesetsVariationRow(base_config_id, rulesets_collection_id, table_features, "$(static_values)$(varied_values)")
end

"""
function addGridVariation(patient_id::Int, D::Vector{Vector{Vector}}; reference_variation_id::Int=0)
Creates a grid of parameter values defined by D to the variations tables for a specified patient.
A reference variation id can be suppplied so that any currently unvaried values are pulled from that variation.
D is a vector of parameter info.
Each entry in D has two elements: D[i][1] is the xml_path based on the config file; D[i][2] is the vector of values to use for the ith parameter.
"""

# function addGridVariation(base_config_id::Int, D::Vector{Vector{Vector}}; reference_variation_id::Int=0)
#     xml_paths = [d[1] for d in D]
#     new_values = [d[2] for d in D]
#     static_column_names, varied_column_names = addVariationColumns(base_config_id, xml_paths, [typeof(d[2][1]) for d in D])
#     static_values, table_features = prepareAddNewVariations(base_config_id, static_column_names, varied_column_names; reference_variation_id = reference_variation_id)

#     NDG = ndgrid(new_values...)
#     sz_variations = size(NDG[1])
#     variation_ids = zeros(Int, sz_variations)
#     is_new_variation_id = falses(sz_variations)
#     for i in eachindex(NDG[1])
#         varied_values = [A[i] for A in NDG] .|> string |> x -> join("\"" .* x .* "\"", ",")
#         variation_ids[i], is_new_variation_id[i] = addVariationRow(base_config_id, table_features, static_values, varied_values)
#     end
#     return variation_ids, is_new_variation_id
# end

# function addGridRulesetsVariation(base_config_id::Int, rulesets_collection_id::Int, D::Vector{Vector{Vector}}; reference_rulesets_variation_id::Int=0)
#     xml_paths = [d[1] for d in D]
#     new_values = [d[2] for d in D]
#     static_column_names, varied_column_names = addRulesetsVariationsColumns(base_config_id, rulesets_collection_id, xml_paths)
#     static_values, table_features = prepareAddNewRulesetsVariations(base_config_id, rulesets_collection_id, static_column_names, varied_column_names; reference_rulesets_variation_id = reference_rulesets_variation_id)

#     NDG = ndgrid(new_values...)
#     sz_variations = size(NDG[1])
#     variation_ids = zeros(Int, sz_variations)
#     is_new_variation_id = falses(sz_variations)
#     for i in eachindex(NDG[1])
#         varied_values = [A[i] for A in NDG] .|> string |> x -> join("\"" .* x .* "\"", ",")
#         variation_ids[i], is_new_variation_id[i] = addRulesetsVariationRow(base_config_id, rulesets_collection_id, table_features, static_values, varied_values)
#     end
#     return variation_ids, is_new_variation_id
# end

######

function addGrid(D::Vector{Vector{Vector}}, addColumns::Function, prepareAddNew::Function, addRow::Function)
    xml_paths = [d[1] for d in D]
    new_values = [d[2] for d in D]
    static_column_names, varied_column_names = addColumns(xml_paths)
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

function addGridVariation(base_config_id::Int, D::Vector{Vector{Vector}}; reference_variation_id::Int=0)
    addColumns = (paths) -> addVariationColumns(base_config_id, paths, [typeof(d[2][1]) for d in D])
    prepareAddNew = (static_column_names, varied_column_names) -> prepareAddNewVariations(base_config_id, static_column_names, varied_column_names; reference_variation_id=reference_variation_id)
    addRow = (features, static_values, varied_values) -> addVariationRow(base_config_id, features, static_values, varied_values)
    return addGrid(D, addColumns, prepareAddNew, addRow)
end

addGridVariation(base_config_folder::String, D::Vector{Vector{Vector}}; reference_variation_id::Int=0) = addGridVariation(retrieveID("base_configs", base_config_folder), D; reference_variation_id=reference_variation_id)

function addGridRulesetsVariation(base_config_id::Int, rulesets_collection_id::Int, D::Vector{Vector{Vector}}; reference_rulesets_variation_id::Int=0)
    addColumns = (paths) -> addRulesetsVariationsColumns(base_config_id, rulesets_collection_id, paths)
    prepareAddNew = (static_names, varied_names) -> prepareAddNewRulesetsVariations(base_config_id, rulesets_collection_id, static_names, varied_names; reference_rulesets_variation_id=reference_rulesets_variation_id)
    addRow = (features, static_values, varied_values) -> addRulesetsVariationRow(base_config_id, rulesets_collection_id, features, static_values, varied_values)
    return addGrid(D, addColumns, prepareAddNew, addRow)
end

# function addGridVariation(patient_id::Int, D::Vector{Vector{Vector}}; reference_variation_id::Int=0)
#     xml_paths = [d[1] for d in D]
#     new_values = [d[2] for d in D]
#     table_name, static_column_names, varied_column_names = addVariationColumns(patient_id, xml_paths, [typeof(d[2][1]) for d in D])
#     static_values, table_features = prepareAddNewVariations(table_name, static_column_names, varied_column_names; reference_variation_id = reference_variation_id)

#     NDG = ndgrid(new_values...)
#     sz_variations = size(NDG[1])
#     variation_ids = zeros(Int, sz_variations)
#     is_new_variation_id = falses(sz_variations)
#     for i in eachindex(NDG[1])
#         varied_values = [A[i] for A in NDG] .|> string |> x -> join("\"" .* x .* "\"", ",")
#         variation_ids[i], is_new_variation_id[i] = addVariationRow(table_name, table_features, static_values, varied_values)
#     end
#     return variation_ids, is_new_variation_id
# end

"""
function addGridVariation(patient_id::Int, xml_paths::Vector{Vector{String}}, new_values::Vector{Vector{T}} where {T<:Real}; reference_variation_id::Int=0)
Does the same as addGridVariation(patient_id::Int, D::Vector{Vector{Vector}}; reference_variation_id::Int=0) but first assembles D from xml_paths and new_values.
"""

# function addGridVariation(patient_id::Int, xml_paths::Vector{Vector{String}}, new_values::Vector{Vector{T}} where {T<:Real}; reference_variation_id::Int=0)
#     D = [[xml_paths[i], new_values[i]] for i in eachindex(xml_paths)]
#     return addGridVariation(patient_id, D; reference_variation_id=reference_variation_id)
# end

# function addSampleVariationToTable(patient_id::Int, xml_paths::Vector{Vector{String}}, parameter_matrix::Matrix{T} where T; reference_variation_id=0)
#     table_name, static_column_names, varied_column_names = addVariationColumns(patient_id, xml_paths, [typeof(parameter_matrix[1,i]) for i in axes(parameter_matrix,2)])
#     static_values, table_features = prepareAddNewVariations(table_name, static_column_names, varied_column_names; reference_variation_id = reference_variation_id)
    
#     sz_variations = size(parameter_matrix,1)
#     variation_ids = zeros(Int, sz_variations)
#     is_new_variation_id = falses(sz_variations)
#     for i in axes(parameter_matrix,1)
#         varied_values = [parameter_matrix[i,j] for j in axes(parameter_matrix,2)] .|> string |> x -> join("\"" .* x .* "\"", ",")
#         variation_ids[i], is_new_variation_id[i] = addVariationRow(base_config_id, table_features, static_values, varied_values)
#     end
#     return variation_ids, is_new_variation_id
# end

# function prepareAddNewVariations(base_config_id::Int, static_column_names::Vector{String}, varied_column_names::Vector{String}; reference_variation_id::Int=0)
#     static_values = selectRow(static_column_names, "variations", "WHERE variation_id=$(reference_variation_id)"; db=getConfigDB(base_config_id)) |> x -> join("\"" .* string.(x) .* "\"", ",")
#     table_features = join("\"" .* static_column_names .* "\"", ",")
#     if !isempty(static_column_names)
#         static_values *= ","
#         table_features *= ","
#     end
#     table_features *= join("\"" .* varied_column_names .* "\"", ",")
#     return static_values, table_features
# end

# function prepareAddNewRulesetsVariations(base_config_id::Int, rulesets_collection_id::Int, static_column_names::Vector{String}, varied_column_names::Vector{String}; reference_rulesets_variation_id::Int=0)
#     static_values = selectRow(static_column_names, "rulesets_variations", "WHERE rulesets_variation_id=$(reference_rulesets_variation_id)"; db=getRulesetsVariationsDB(base_config_id, rulesets_collection_id)) |> x -> join("\"" .* string.(x) .* "\"", ",")
#     table_features = join("\"" .* static_column_names .* "\"", ",")
#     if !isempty(static_column_names)
#         static_values *= ","
#         table_features *= ","
#     end
#     table_features *= join("\"" .* varied_column_names .* "\"", ",")
#     return static_values, table_features
# end

####

function prepareAddNew(db_columns::SQLite.DB, static_column_names::Vector{String}, varied_column_names::Vector{String}, table_name::String, id_name::String, reference_id::Int)
    static_values = selectRow(static_column_names, table_name, "WHERE $(id_name)=$(reference_id)"; db=db_columns) |> x -> join("\"" .* string.(x) .* "\"", ",")
    table_features = join("\"" .* static_column_names .* "\"", ",")
    if !isempty(static_column_names)
        static_values *= ","
        table_features *= ","
    end
    table_features *= join("\"" .* varied_column_names .* "\"", ",")
    return static_values, table_features
end

function prepareAddNewVariations(base_config_id::Int, static_column_names::Vector{String}, varied_column_names::Vector{String}; reference_variation_id::Int=0)
    db_columns = getConfigDB(base_config_id)
    return prepareAddNew(db_columns, static_column_names, varied_column_names, "variations", "variation_id", reference_variation_id)
end

function prepareAddNewRulesetsVariations(base_config_id::Int, rulesets_collection_id::Int, static_column_names::Vector{String}, varied_column_names::Vector{String}; reference_rulesets_variation_id::Int=0)
    db_columns = getRulesetsVariationsDB(base_config_id, rulesets_collection_id)
    return prepareAddNew(db_columns, static_column_names, varied_column_names, "rulesets_variations", "rulesets_variation_id", reference_rulesets_variation_id)
end

# function recordTrialInfo(simulation_ids::Vector{Int}, time_started::DateTime, description::String)
#     if isempty(description)
#         println("No description submitted for this trial. Do you think you can remember everything? No. Enter a description now:")
#         description = readline()
#     end
#     s =  "INSERT INTO trials (datetime,description) VALUES('$(Dates.format(time_started,"yymmddHHMM"))','$(description)') RETURNING trial_id;"
#     trial_id = DBInterface.execute(getDB(), s) |> DataFrame |> x -> x.trial_id[1]
#     recordTrialSimulationIDs(trial_id,simulation_ids)
# end

# function recordTrialSimulationIDs(trial_id::Int, simulation_ids::Vector{Int})
#     path_to_trial_folder = data_dir * "/trials/" * string(trial_id) * "/"
#     run(`mkdir -p $(path_to_trial_folder)`)
#     path_to_csv = path_to_trial_folder * "simulations.csv"
#     lines_table = compressSimulationIDs(simulation_ids)
#     CSV.write(path_to_csv, lines_table; writeheader=false)
# end

function compressSimulationIDs(simulation_ids::Vector{Int})
    sort!(simulation_ids)
    return compressIDs(simulation_ids)
end

function compressIDs(ids::Vector{Int})
    lines = String[]
    while !isempty(ids) # while there are still ids to compress
        if length(ids) == 1 # if there's only one id left
            next_line = string(ids[1]) # just add it to the list
            popfirst!(ids) # and remove it from the list of ids
        else # if there's more than one id left
            I = findfirst(diff(ids) .> 1) # find the first index where the difference between consecutive ids is greater than 1
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

function compressMonadIDs(monad_ids::Array{Int})
    monad_ids = vec(monad_ids)
    return compressIDs(monad_ids)
end

compressSamplingIDs(sampling_ids::Array{Int}) = compressIDs(sampling_ids)

# function selectTrialSimulations(trial_id::Int)
#     path_to_trial = data_dir * "/trials/" * string(trial_id) * "/"
#     df = CSV.read(path_to_trial*"simulations.csv",DataFrame; header=false,silencewarnings=true,types=String,delim=",")
#     simulation_ids = Int[]
#     for i in axes(df,1)
#         s = df.Column1[i]
#         I = split(s,":") .|> string .|> x->parse(Int,x)
#         if length(I)==1
#             push!(simulation_ids,I[1])
#         else
#             append!(simulation_ids,I[1]:I[2])
#         end
#     end
#     return simulation_ids
# end

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

getMondadSimulations(monad_id::Int) = selectConstituents("$(data_dir)/outputs/monads/$(monad_id)/simulations.csv")
getSamplingMonads(sampling_id::Int) = selectConstituents("$(data_dir)/outputs/samplings/$(sampling_id)/monads.csv")
getTrialSamplings(trial_id::Int) = selectConstituents("$(data_dir)/outputs/trials/$(trial_id)/samplings.csv")

end