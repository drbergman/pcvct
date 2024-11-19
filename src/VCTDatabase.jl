export printSimulationsTable, printVariationsTable, simulationsTable

db::SQLite.DB = SQLite.DB()

################## Database Initialization Functions ##################

function initializeDatabase(path_to_database::String; auto_upgrade::Bool=false)
    println(rpad("Path to database:", 20, ' ') * path_to_database)
    is_new_db = !isfile(path_to_database)
    global db = SQLite.DB(path_to_database)
    SQLite.transaction(db, "EXCLUSIVE")
    success = createSchema(is_new_db; auto_upgrade=auto_upgrade)
    SQLite.commit(db)
    return success
end

function initializeDatabase()
    global db = SQLite.DB()
    is_new_db = true
    return createSchema(is_new_db)
end

function createSchema(is_new_db::Bool; auto_upgrade::Bool=false)
    # make sure necessary directories are present
    data_dir_contents = readdir(joinpath(data_dir, "inputs"); sort=false)
    if !necessaryInputsPresent(data_dir_contents)
        return false
    end

    # start with pcvct version info
    if !resolvePCVCTVersion(is_new_db, auto_upgrade)
        println("Could not successfully upgrade database. Please check the logs for more information.")
        return false
    end

    # initialize and populate physicell_versions table
    createPCVCTTable("physicell_versions", physicellVersionsSchema())

    # initialize and populate custom_codes table
    custom_codes_schema = """
        custom_code_id INTEGER PRIMARY KEY,
        folder_name UNIQUE,
        description TEXT
    """
    createPCVCTTable("custom_codes", custom_codes_schema)
        
    custom_codes_folders = readdir(joinpath(data_dir, "inputs", "custom_codes"); sort=false) |> filter(x->isdir(joinpath(data_dir, "inputs", "custom_codes", x)))
    if isempty(custom_codes_folders)
        println("No folders in $(joinpath(data_dir, "inputs", "custom_codes")) found. Add custom_modules, main.cpp, and Makefile to a folder here to move forward.")
        return false
    end
    for custom_codes_folder in custom_codes_folders
        DBInterface.execute(db, "INSERT OR IGNORE INTO custom_codes (folder_name) VALUES ('$(custom_codes_folder)');")
    end
    
    # initialize and populate ics tables
    createICTable("cells"; data_dir_contents=data_dir_contents)
    createICTable("substrates"; data_dir_contents=data_dir_contents)
    createICTable("ecms"; data_dir_contents=data_dir_contents)

    # initialize and populate configs table
    configs_schema = """
        config_id INTEGER PRIMARY KEY,
        folder_name UNIQUE,
        description TEXT
    """
    createPCVCTTable("configs", configs_schema)
        
    config_folders = readdir(joinpath(data_dir, "inputs", "configs"); sort=false) |> filter(x -> isdir(joinpath(data_dir, "inputs", "configs", x)))
    if isempty(config_folders)
        println("No folders in $(joinpath(data_dir, "inputs", "configs")) found. Add PhysiCell_settings.xml and rules files here.")
        return false
    end
    for config_folder in config_folders
        DBInterface.execute(db, "INSERT OR IGNORE INTO configs (folder_name) VALUES ('$(config_folder)');")
        db_config_variations = joinpath(data_dir, "inputs", "configs", config_folder, "config_variations.db") |> SQLite.DB
        createPCVCTTable("config_variations", "config_variation_id INTEGER PRIMARY KEY"; db=db_config_variations)
        DBInterface.execute(db_config_variations, "INSERT OR IGNORE INTO config_variations (config_variation_id) VALUES(0);")
    end

    # initialize and populate rulesets_collections table
    rulesets_collections_schema = """
        rulesets_collection_id INTEGER PRIMARY KEY,
        folder_name UNIQUE,
        description TEXT
    """
    createPCVCTTable("rulesets_collections", rulesets_collections_schema)

    if "rulesets_collections" in data_dir_contents
        rulesets_collections_folders = readdir(joinpath(data_dir, "inputs", "rulesets_collections"); sort=false) |> filter(x -> isdir(joinpath(data_dir, "inputs", "rulesets_collections", x)))
        for rulesets_collection_folder in rulesets_collections_folders
            DBInterface.execute(db, "INSERT OR IGNORE INTO rulesets_collections (folder_name) VALUES ('$(rulesets_collection_folder)');")
            db_rulesets_variations = joinpath(data_dir, "inputs", "rulesets_collections", rulesets_collection_folder, "rulesets_variations.db") |> SQLite.DB
            createPCVCTTable("rulesets_variations", "rulesets_variation_id INTEGER PRIMARY KEY"; db=db_rulesets_variations)
            DBInterface.execute(db_rulesets_variations, "INSERT OR IGNORE INTO rulesets_variations (rulesets_variation_id) VALUES(0);")
        end
    end

    # initialize and populate ic_cells variations dbs
    path_to_ics = joinpath(data_dir, "inputs", "ics")
    path_to_ic_cells = joinpath(path_to_ics, "cells")
    if "ics" in data_dir_contents && "cells" in readdir(path_to_ics, sort=false)
        ic_cells_folders = readdir(path_to_ic_cells, sort=false) |> filter(x -> isdir(joinpath(path_to_ic_cells, x)))
        for ic_cell_folder in ic_cells_folders
            DBInterface.execute(db, "INSERT OR IGNORE INTO ic_cells (folder_name) VALUES ('$(ic_cell_folder)');")
            path_to_folder = joinpath(path_to_ic_cells, ic_cell_folder)
            is_csv = isfile(joinpath(path_to_folder, "cells.csv"))
            # ⊻ = XOR (make sure exactly one of the files is present)
            @assert is_csv ⊻ isfile(joinpath(path_to_folder, "cells.xml")) "Must have one of cells.csv or cells.xml in $(joinpath(path_to_folder))" 
            if is_csv
                continue # no variations allowed on csv files
            end
            db_ic_cell = joinpath(path_to_folder, "ic_cell_variations.db") |> SQLite.DB
            createPCVCTTable("ic_cell_variations", "ic_cell_variation_id INTEGER PRIMARY KEY"; db=db_ic_cell)
            DBInterface.execute(db_ic_cell, "INSERT OR IGNORE INTO ic_cell_variations (ic_cell_variation_id) VALUES(0) RETURNING ic_cell_variation_id;")
        end
    end
            
    # initialize simulations table
    simulations_schema = """
        simulation_id INTEGER PRIMARY KEY,
        physicell_version_id INTEGER,
        custom_code_id INTEGER,
        ic_cell_id INTEGER,
        ic_substrate_id INTEGER,
        ic_ecm_id INTEGER,
        config_id INTEGER,
        rulesets_collection_id INTEGER,
        config_variation_id INTEGER,
        rulesets_variation_id INTEGER,
        ic_cell_variation_id INTEGER,
        status_code_id INTEGER,
        FOREIGN KEY (physicell_version_id)
            REFERENCES physicell_versions (physicell_version_id),
        FOREIGN KEY (custom_code_id)
            REFERENCES custom_codes (custom_code_id),
        FOREIGN KEY (ic_cell_id)
            REFERENCES ic_cells (ic_cell_id),
        FOREIGN KEY (ic_substrate_id)
            REFERENCES ic_substrates (ic_substrate_id),
        FOREIGN KEY (ic_ecm_id)
            REFERENCES ic_ecms (ic_ecm_id),
        FOREIGN KEY (config_id)
            REFERENCES configs (config_id),
        FOREIGN KEY (rulesets_collection_id)
            REFERENCES rulesets_collections (rulesets_collection_id),
        FOREIGN KEY (status_code_id)
            REFERENCES status_codes (status_code_id)
    """
    createPCVCTTable("simulations", simulations_schema)

    # initialize monads table
    createPCVCTTable("monads", monadsSchema())

    # initialize samplings table
    samplings_schema = """
        sampling_id INTEGER PRIMARY KEY,
        physicell_version_id INTEGER,
        custom_code_id INTEGER,
        ic_cell_id INTEGER,
        ic_substrate_id INTEGER,
        ic_ecm_id INTEGER,
        config_id INTEGER,
        rulesets_collection_id INTEGER,
        FOREIGN KEY (physicell_version_id)
            REFERENCES physicell_versions (physicell_version_id),
        FOREIGN KEY (custom_code_id)
            REFERENCES custom_codes (custom_code_id),
        FOREIGN KEY (ic_cell_id)
            REFERENCES ic_cells (ic_cell_id),
        FOREIGN KEY (ic_substrate_id)
            REFERENCES ic_substrates (ic_substrate_id),
        FOREIGN KEY (ic_ecm_id)
            REFERENCES ic_ecms (ic_ecm_id),
        FOREIGN KEY (config_id)
            REFERENCES configs (config_id),
        FOREIGN KEY (rulesets_collection_id)
            REFERENCES rulesets_collections (rulesets_collection_id)
    """
    createPCVCTTable("samplings", samplings_schema)

    # initialize trials table
    trials_schema = """
        trial_id INTEGER PRIMARY KEY,
        datetime TEXT,
        description TEXT
    """
    createPCVCTTable("trials", trials_schema)

    createDefaultStatusCodesTable()

    return true
end

function necessaryInputsPresent(data_dir_contents::Vector{String})
    success = true
    if "custom_codes" ∉ data_dir_contents
        println("No $(joinpath(data_dir, "inputs", "custom_codes")) found. This is where to put the folders for custom_modules, main.cpp, and Makefile.")
        success = false
    end
    if "configs" ∉ data_dir_contents
        println("No $(joinpath(data_dir, "inputs", "configs")) found. This is where to put the folders for config files and rules files.")
        success = false
    end
    return success
end

function physicellVersionsSchema()
    return """
        physicell_version_id INTEGER PRIMARY KEY,
        repo_owner TEXT,
        tag TEXT,
        commit_hash TEXT UNIQUE,
        date TEXT
    """
end

function monadsSchema()
    return """
        monad_id INTEGER PRIMARY KEY,
        physicell_version_id INTEGER,
        custom_code_id INTEGER,
        ic_cell_id INTEGER,
        ic_substrate_id INTEGER,
        ic_ecm_id INTEGER,
        config_id INTEGER,
        rulesets_collection_id INTEGER,
        config_variation_id INTEGER,
        rulesets_variation_id INTEGER,
        ic_cell_variation_id INTEGER,
        FOREIGN KEY (physicell_version_id)
            REFERENCES physicell_versions (physicell_version_id),
        FOREIGN KEY (custom_code_id)
            REFERENCES custom_codes (custom_code_id),
        FOREIGN KEY (ic_cell_id)
            REFERENCES ic_cells (ic_cell_id),
        FOREIGN KEY (ic_substrate_id)
            REFERENCES ic_substrates (ic_substrate_id),
        FOREIGN KEY (ic_ecm_id)
            REFERENCES ic_ecms (ic_ecm_id),
        FOREIGN KEY (config_id)
            REFERENCES configs (config_id),
        FOREIGN KEY (rulesets_collection_id)
            REFERENCES rulesets_collections (rulesets_collection_id),
        UNIQUE (physicell_version_id,custom_code_id,ic_cell_id,ic_substrate_id,ic_ecm_id,config_id,rulesets_collection_id,config_variation_id,rulesets_variation_id,ic_cell_variation_id)
   """
end

function createICTable(ic_name::String; data_dir_contents=String[])
    table_name = "ic_$(ic_name)"
    schema = """
        $(table_name[1:end-1])_id INTEGER PRIMARY KEY,
        folder_name UNIQUE,
        description TEXT
    """
    createPCVCTTable(table_name, schema)
    if "ics" in data_dir_contents && ic_name in readdir(joinpath(data_dir, "inputs", "ics"), sort=false)
        ic_folders = readdir(joinpath(data_dir, "inputs", "ics", ic_name), sort=false) |> filter(x -> isdir(joinpath(data_dir, "inputs", "ics", ic_name, x)))
        if !isempty(ic_folders)
            for ic_folder in ic_folders
                if !isfile(joinpath(data_dir, "inputs", "ics", ic_name, ic_folder, icFilename(ic_name)))
                    continue
                end
                if isfile(joinpath(data_dir, "inputs", "ics", ic_name, ic_folder, "metadata.xml"))
                    metadata = parse_file(joinpath(data_dir, "inputs", "ics", ic_name, ic_folder, "metadata.xml")) |> root
                    description = content(find_element(metadata, "description"))
                else
                    description = ""
                end
                DBInterface.execute(db, "INSERT OR IGNORE INTO $(table_name) (folder_name, description) VALUES ('$(ic_folder)', '$description');")
            end
        end
    end
    return
end

function icFilename(table_name::String)
    if table_name == "cells"
        return "cells.csv"
    elseif table_name == "substrates"
        return "substrates.csv"
    elseif table_name == "ecms"
        return "ecm.csv"
    else
        error("table_name must be 'cells', 'substrates', or 'ecms'.")
    end
end

function createPCVCTTable(table_name::String, schema::String; db::SQLite.DB=db)
    # check that table_name ends in "s"
    if last(table_name) != 's'
        s = "Table name must end in 's'."
        s *= "\n\tThis helps to normalize what the id names are for these entries."
        s *= "\n\tYour table $(table_name) does not end in 's'."
        s *= "\n\tSee retrieveID(table_name::String, folder_name::String; db::SQLite.DB=db)."
        error(s)
    end
    # check that schema has PRIMARY KEY named as table_name without the s followed by _id
    if !occursin("$(table_name[1:end-1])_id INTEGER PRIMARY KEY", schema)
        s = "Schema must have PRIMARY KEY named as $(table_name[1:end-1])_id."
        s *= "\n\tThis helps to normalize what the id names are for these entries."
        s *= "\n\tYour schema $(schema) does not have \"$(table_name[1:end-1])_id INTEGER PRIMARY KEY\"."
        s *= "\n\tSee retrieveID(table_name::String, folder_name::String; db::SQLite.DB=db)."
        error(s)
    end
    SQLite.execute(db, "CREATE TABLE IF NOT EXISTS $(table_name) (
        $(schema)
        )
    ")
    return
end

function createDefaultStatusCodesTable()
    status_codes_schema = """
        status_code_id INTEGER PRIMARY KEY,
        status_code TEXT UNIQUE
    """
    createPCVCTTable("status_codes", status_codes_schema)
    status_codes = ["Not Started", "Queued", "Running", "Completed", "Failed"]
    for status_code in status_codes
        DBInterface.execute(db, "INSERT OR IGNORE INTO status_codes (status_code) VALUES ('$status_code');")
    end
end

function getStatusCodeID(status_code::String)
    query = constructSelectQuery("status_codes", "WHERE status_code='$status_code';"; selection="status_code_id")
    return queryToDataFrame(query; is_row=true) |> x -> x[1,:status_code_id]
end

function isStarted(simulation_id::Int; new_status_code::Union{Missing,String}=missing)
    query = constructSelectQuery("simulations", "WHERE simulation_id=$(simulation_id);"; selection="status_code_id")
    mode = ismissing(new_status_code) ? "DEFERRED" : "EXCLUSIVE" # if we are possibly going to update, then set to exclusive mode
    SQLite.transaction(db, mode)
    status_code = queryToDataFrame(query; is_row=true) |> x -> x[1,:status_code_id]
    is_started = status_code != getStatusCodeID("Not Started")
    if !ismissing(new_status_code) && !is_started
        query = "UPDATE simulations SET status_code_id=$(getStatusCodeID(new_status_code)) WHERE simulation_id=$(simulation_id);"
        DBInterface.execute(db, query)
    end
    SQLite.commit(db)

    return is_started
end

isStarted(simulation::Simulation; new_status_code::Union{Missing,String}=missing) = isStarted(simulation.id; new_status_code=new_status_code)

################## DB Interface Functions ##################

configDB(config_folder::String) = joinpath(data_dir, "inputs", "configs", config_folder, "config_variations.db") |> SQLite.DB
configDB(config_id::Int) = configFolder(config_id) |> configDB
configDB(S::AbstractSampling) = configDB(S.folder_names.config_folder)

function rulesetsCollectionDB(rulesets_collection_folder::String)
    if rulesets_collection_folder == ""
        return missing
    end
    path_to_folder = joinpath(data_dir, "inputs", "rulesets_collections", rulesets_collection_folder)
    return joinpath(path_to_folder, "rulesets_variations.db") |> SQLite.DB
end
rulesetsCollectionDB(M::AbstractMonad) = rulesetsCollectionDB(M.folder_names.rulesets_collection_folder)
rulesetsCollectionDB(rulesets_collection_id::Int) = rulesetsCollectionFolder(rulesets_collection_id) |> rulesetsCollectionDB

function icCellDB(ic_cell_folder::String)
    if ic_cell_folder == ""
        return missing
    end
    path_to_folder = joinpath(data_dir, "inputs", "ics", "cells", ic_cell_folder)
    if isfile(joinpath(path_to_folder, "cells.csv"))
        return missing
    end
    return joinpath(path_to_folder, "ic_cell_variations.db") |> SQLite.DB
end
icCellDB(ic_cell_id::Int) = icCellFolder(ic_cell_id) |> icCellDB
icCellDB(S::AbstractSampling) = icCellDB(S.folder_names.ic_cell_folder)

########### Retrieving Database Information Functions ###########

vctDBQuery(query::String; db::SQLite.DB=db) = DBInterface.execute(db, query)

function queryToDataFrame(query::String; db::SQLite.DB=db, is_row::Bool=false) 
    df = vctDBQuery(query; db=db) |> DataFrame
    if is_row
        @assert size(df,1)==1 "Did not find exactly one row matching the query:\n\tDatabase file: $(db)\n\tQuery: $(query)\nResult: $(df)"
    end
    return df
end

constructSelectQuery(table_name::String, condition_stmt::String=""; selection::String="*") = "SELECT $(selection) FROM $(table_name) $(condition_stmt);"

function getFolder(table_name::String, id_name::String, id::Int; db::SQLite.DB=db)
    query = constructSelectQuery(table_name, "WHERE $(id_name)=$(id);"; selection="folder_name")
    return queryToDataFrame(query; is_row=true) |> x -> x.folder_name[1]
end

getOptionalFolder(table_name::String, id_name::String, id::Int; db::SQLite.DB=db) = id == -1 ? "" : getFolder(table_name, id_name, id; db=db)

configFolder(config_id::Int) = getFolder("configs", "config_id", config_id)
icCellFolder(ic_cell_id::Int) = getOptionalFolder("ic_cells", "ic_cell_id", ic_cell_id)
getICSubstrateFolder(ic_substrate_id::Int) = getOptionalFolder("ic_substrates", "ic_substrate_id", ic_substrate_id)
getICECMFolder(ic_ecm_id::Int) = getOptionalFolder("ic_ecms", "ic_ecm_id", ic_ecm_id)
rulesetsCollectionFolder(rulesets_collection_id::Int) = getOptionalFolder("rulesets_collections", "rulesets_collection_id", rulesets_collection_id)
getCustomCodesFolder(custom_code_id::Int) = getFolder("custom_codes", "custom_code_id", custom_code_id)

function retrievePathInfo(config_id::Int, rulesets_collection_id::Int, ic_cell_id::Int, ic_substrate_id::Int, ic_ecm_id::Int, custom_code_id::Int)
    config_folder = configFolder(config_id)
    rulesets_collection_folder = rulesetsCollectionFolder(rulesets_collection_id)
    ic_cell_folder = icCellFolder(ic_cell_id)
    ic_substrate_folder = getICSubstrateFolder(ic_substrate_id)
    ic_ecm_folder = getICECMFolder(ic_ecm_id)
    custom_code_folder = getCustomCodesFolder(custom_code_id)
    return config_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder, custom_code_folder
end

function retrieveID(table_name::String, folder_name::String; db::SQLite.DB=db)
    if folder_name == ""
        return -1
    end
    primary_key_string = "$(rstrip(table_name,'s'))_id"
    return constructSelectQuery(table_name, "WHERE folder_name='$(folder_name)'"; selection=primary_key_string) |> queryToDataFrame |> x -> x[1, primary_key_string]
end

function retrieveID(folder_names::AbstractSamplingFolders)
    config_id = retrieveID("configs", folder_names.config_folder)
    rulesets_collection_id = retrieveID("rulesets_collections", folder_names.rulesets_collection_folder)
    ic_cell_id = retrieveID("ic_cells", folder_names.ic_cell_folder)
    ic_substrate_id = retrieveID("ic_substrates", folder_names.ic_substrate_folder)
    ic_ecm_id = retrieveID("ic_ecms", folder_names.ic_ecm_folder)
    custom_code_id = retrieveID("custom_codes", folder_names.custom_code_folder)
    return config_id, rulesets_collection_id, ic_cell_id, ic_substrate_id, ic_ecm_id, custom_code_id
end

########### Summarizing Database Functions ###########

configVariationIDs(M::AbstractMonad) = [M.variation_ids.config_variation_id]
configVariationIDs(sampling::Sampling) = [vid.config_variation_id for vid in sampling.variation_ids]

rulesetsVariationIDs(M::AbstractMonad) = [M.variation_ids.rulesets_variation_id]
rulesetsVariationIDs(sampling::Sampling) = [vid.rulesets_variation_id for vid in sampling.variation_ids]

icCellVariationIDs(M::AbstractMonad) = [M.variation_ids.ic_cell_variation_id]
icCellVariationIDs(sampling::Sampling) = [vid.ic_cell_variation_id for vid in sampling.variation_ids]

getAbstractTrial(class_id::VCTClassID) = class_id.id |> getVCTClassIDType(class_id)

function variationsTable(query::String, db::SQLite.DB; remove_constants::Bool = false)
    df = queryToDataFrame(query, db=db)
    if remove_constants && size(df, 1) > 1
        col_names = names(df)
        filter!(n -> length(unique(df[!,n])) > 1, col_names)
        select!(df, col_names)
    end
    return df
end

function configVariationsTable(config_variations_db::SQLite.DB, config_variation_ids::AbstractVector{<:Integer}; remove_constants::Bool = false)
    query = constructSelectQuery("config_variations", "WHERE config_variation_id IN ($(join(config_variation_ids,",")));")
    df = variationsTable(query, config_variations_db; remove_constants = remove_constants)
    rename!(simpleConfigVariationNames, df)
    return df
end

configVariationsTable(S::AbstractSampling; remove_constants::Bool=false) = configVariationsTable(configDB(S), configVariationIDs(S); remove_constants = remove_constants)
configVariationsTable(class_id::VCTClassID{<:AbstractSampling}; remove_constants::Bool = false) = getAbstractTrial(class_id) |> x -> configVariationsTable(x; remove_constants = remove_constants)

function rulesetsVariationsTable(rulesets_variations_db::SQLite.DB, rulesets_variation_ids::AbstractVector{<:Integer}; remove_constants::Bool = false)
    rulesets_variation_ids = filter(x -> x != -1, rulesets_variation_ids) # rulesets_variation_id = -1 means no ruleset being used
    query = constructSelectQuery("rulesets_variations", "WHERE rulesets_variation_id IN ($(join(rulesets_variation_ids,",")));")
    df = variationsTable(query, rulesets_variations_db; remove_constants = remove_constants)
    rename!(simpleRulesetsVariationNames, df)
    return df
end

function rulesetsVariationsTable(::Missing, rulesets_variation_ids::AbstractVector{<:Integer}; remove_constants::Bool = false)
    @assert all(x -> x == -1, rulesets_variation_ids) "If the rulesets_variation_id is missing, then all rulesets_variation_ids must be -1."
    return DataFrame(RulesVarID=rulesets_variation_ids)
end

rulesetsVariationsTable(S::AbstractSampling; remove_constants::Bool=false) = rulesetsVariationsTable(rulesetsCollectionDB(S), rulesetsVariationIDs(S); remove_constants = remove_constants)
rulesetsVariationsTable(class_id::VCTClassID{<:AbstractSampling}; remove_constants::Bool = false) = getAbstractTrial(class_id) |> x -> rulesetsVariationsTable(x; remove_constants = remove_constants)

function icCellVariationsTable(ic_cell_variations_db::SQLite.DB, ic_cell_variation_ids::AbstractVector{<:Integer}; remove_constants::Bool = false)
    query = constructSelectQuery("ic_cell_variations", "WHERE ic_cell_variation_id IN ($(join(ic_cell_variation_ids,",")));")
    df = variationsTable(query, ic_cell_variations_db; remove_constants = remove_constants)
    rename!(simpleICCellVariationNames, df)
    return df
end

function icCellVariationsTable(::Missing, ic_cell_variation_ids::AbstractVector{<:Integer}; remove_constants::Bool = false)
    @assert all(x -> x == -1, ic_cell_variation_ids) "If the ic_cell_variation_id is missing, then all ic_cell_variation_ids must be -1."
    return DataFrame(ICCellVarID=ic_cell_variation_ids)
end

icCellVariationsTable(S::AbstractSampling; remove_constants::Bool=false) = icCellVariationsTable(icCellDB(S), icCellVariationIDs(S); remove_constants = remove_constants)
icCellVariationsTable(class_id::VCTClassID{<:AbstractSampling}; remove_constants::Bool = false) = getAbstractTrial(class_id) |> x -> icCellVariationsTable(x; remove_constants = remove_constants)

function variationsTableFromSimulations(query::String, id_name::Symbol, getVariationsTableFn::Function; remove_constants::Bool = false)
    df = queryToDataFrame(query)
    unique_tuples = [(row[1], row[2]) for row in eachrow(df)] |> unique
    var_df = DataFrame(id_name=>Int[])
    for unique_tuple in unique_tuples
        append!(var_df, getVariationsTableFn(unique_tuple), cols=:union)
    end
    if remove_constants && size(var_df, 1) > 1
        col_names = names(var_df)
        filter!(n -> length(unique(var_df[!,n])) > 1, col_names)
        select!(var_df, col_names)
    end
    return var_df
end

function configVariationsTable(simulation_ids::AbstractVector{<:Integer}; remove_constants::Bool = false)
    query = constructSelectQuery("simulations", "WHERE simulation_id IN ($(join(simulation_ids,",")));", selection="config_id, config_variation_id")
    getVariationsTableFn = x -> configVariationsTable(configDB(x[1]), [x[2]]; remove_constants = false)
    return variationsTableFromSimulations(query, :ConfigVarID, getVariationsTableFn)
end


function rulesetsVariationsTable(simulation_ids::AbstractVector{<:Integer}; remove_constants::Bool = false)
    query = constructSelectQuery("simulations", "WHERE simulation_id IN ($(join(simulation_ids,",")));", selection="rulesets_collection_id, rulesets_variation_id")
    getVariationsTableFn = x -> rulesetsVariationsTable(rulesetsCollectionDB(x[1]), [x[2]]; remove_constants = false)
    return variationsTableFromSimulations(query, :RulesVarID, getVariationsTableFn)
end

function icCellVariationsTable(simulation_ids::AbstractVector{<:Integer}; remove_constants::Bool = false)
    query = constructSelectQuery("simulations", "WHERE simulation_id IN ($(join(simulation_ids,",")));", selection="ic_cell_id, ic_cell_variation_id")
    getVariationsTableFn = x -> icCellVariationsTable(icCellDB(x[1]), [x[2]]; remove_constants = false)
    return variationsTableFromSimulations(query, :ICCellVarID, getVariationsTableFn)
end

function addFolderColumns!(df::DataFrame)
    col_names = ["custom_code", "config", "rulesets_collection", "ic_cell", "ic_substrate", "ic_ecm"]
    get_function = [getFolder, getFolder, getOptionalFolder, getOptionalFolder, getOptionalFolder, getOptionalFolder]
    for (col_name, get_function) in zip(col_names, get_function)
        if !("$(col_name)_id" in names(df))
            continue
        end
        unique_ids = unique(df[!,"$(col_name)_id"])
        D = Dict{Int, String}()
        for id in unique_ids
            D[id] = get_function("$(col_name)s", "$(col_name)_id", id)
        end
        df[!,"$(col_name)_folder"] .= [D[id] for id in df[!,"$(col_name)_id"]]
    end
    return df
end

function simulationsTableFromQuery(query::String; remove_constants::Bool=true, sort_by::Vector{String}=String[], sort_ignore::Vector{String}=["SimID", "ConfigVarID", "RulesVarID", "ICCellVarID"])
    df = queryToDataFrame(query)
    id_col_names_to_remove = names(df) # a bunch of ids that we don't want to show
    filter!(n -> !(n in ["simulation_id", "config_variation_id", "ic_cell_id", "rulesets_variation_id", "ic_cell_variation_id"]), id_col_names_to_remove) # keep the simulation_id and config_variation_id columns
    addFolderColumns!(df) # add the folder columns
    select!(df, Not(id_col_names_to_remove)) # remove the id columns
    unique_tuples = [(row.config_folder, row.config_variation_id) for row in eachrow(df)] |> unique
    df = appendVariations(df, unique_tuples, configDB, configVariationsTable, :config_folder => :folder_name, :config_variation_id => :ConfigVarID)
    unique_tuples = [(row.rulesets_collection_folder, row.rulesets_variation_id) for row in eachrow(df)] |> unique
    df = appendVariations(df, unique_tuples, rulesetsCollectionDB, rulesetsVariationsTable, :rulesets_collection_folder => :folder_name, :rulesets_variation_id => :RulesVarID)
    unique_tuples = [(row.ic_cell_folder, row.ic_cell_variation_id) for row in eachrow(df)] |> unique
    df = appendVariations(df, unique_tuples, icCellDB, icCellVariationsTable, :ic_cell_folder => :folder_name, :ic_cell_variation_id => :ICCellVarID)
    rename!(df, [:simulation_id => :SimID, :config_variation_id => :ConfigVarID, :rulesets_variation_id => :RulesVarID, :ic_cell_variation_id => :ICCellVarID])
    col_names = names(df)
    if remove_constants && size(df, 1) > 1
        filter!(n -> length(unique(df[!, n])) > 1, col_names)
        select!(df, col_names)
    end
    if isempty(sort_by)
        sort_by = deepcopy(col_names)
    end
    sort_by = [n for n in sort_by if !(n in sort_ignore) && (n in col_names)] # sort by columns in sort_by (overridden by sort_ignore) and in the dataframe
    sort!(df, sort_by)
    return df
end

function appendVariations(df::DataFrame, unique_tuples::Vector{Tuple{String, Int}}, getDBFn::Function, getVariationsTableFn::Function, folder_pair::Pair{Symbol, Symbol}, id_pair::Pair{Symbol, Symbol})
    var_df = DataFrame(id_pair[2] => Int[])
    for unique_tuple in unique_tuples
        temp_df = getVariationsTableFn(getDBFn(unique_tuple[1]), [unique_tuple[2]]; remove_constants = false)
        temp_df[!,:folder_name] .= unique_tuple[1]
        append!(var_df, temp_df, cols=:union)
    end
    return outerjoin(df, var_df, on = [folder_pair, id_pair])
end

function simulationsTable(T::Union{AbstractTrial,AbstractArray{<:AbstractTrial}}; remove_constants::Bool = true, sort_by::Vector{String}=String[], sort_ignore::Vector{String}=["SimID", "ConfigVarID", "RulesVarID", "ICCellVarID"])
    query = constructSelectQuery("simulations", "WHERE simulation_id IN ($(join(getSimulationIDs(T),",")));")
    return simulationsTableFromQuery(query; remove_constants = remove_constants, sort_by = sort_by, sort_ignore = sort_ignore)
end

function simulationsTable(simulation_ids::AbstractVector{<:Integer}; remove_constants::Bool = true, sort_by::Vector{String}=String[], sort_ignore::Vector{String}=["SimID", "ConfigVarID", "RulesVarID", "ICCellVarID"])
    query = constructSelectQuery("simulations", "WHERE simulation_id IN ($(join(simulation_ids,",")));")
    return simulationsTableFromQuery(query; remove_constants = remove_constants, sort_by = sort_by, sort_ignore = sort_ignore)
end

function simulationsTable(; remove_constants::Bool = true, sort_by::Vector{String}=String[], sort_ignore::Vector{String}=["SimID", "ConfigVarID", "RulesVarID", "ICCellVarID"])
    query = constructSelectQuery("simulations")
    return simulationsTableFromQuery(query; remove_constants = remove_constants, sort_by = sort_by, sort_ignore = sort_ignore)
end

function simulationsTable(class_id::VCTClassID; remove_constants::Bool = true, sort_by::Vector{String}=String[], sort_ignore::Vector{String}=["SimID", "ConfigVarID", "RulesVarID", "ICCellVarID"])
    query = constructSelectQuery("simulations", "WHERE simulation_id IN ($(join(getSimulationIDs(class_id),",")));")
    return simulationsTableFromQuery(query; remove_constants = remove_constants, sort_by = sort_by, sort_ignore = sort_ignore)
end

########### Printing Database Functions ###########

printConfigVariationsTable(args...; kwargs...) = configVariationsTable(args...; kwargs...) |> println
printRulesetsVariationsTable(args...; kwargs...) = rulesetsVariationsTable(args...; kwargs...) |> println

printSimulationsTable(args...; sink=println, kwargs...) = simulationsTable(args...; kwargs...) |> sink
