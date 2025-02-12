export printSimulationsTable, printVariationsTable, simulationsTable

db::SQLite.DB = SQLite.DB()

################## Database Initialization Functions ##################

function initializeDatabase(path_to_database::String; auto_upgrade::Bool=false)
    if db.file == ":memory:" || abspath(db.file) != abspath(path_to_database)
        println(rpad("Path to database:", 20, ' ') * path_to_database)
    end
    is_new_db = !isfile(path_to_database)
    global db = SQLite.DB(path_to_database)
    SQLite.transaction(db, "EXCLUSIVE")
    success = createSchema(is_new_db; auto_upgrade=auto_upgrade)
    SQLite.commit(db)
    if success
        global initialized = true
    end
    return success
end

function initializeDatabase()
    global db = SQLite.DB()
    is_new_db = true
    success = createSchema(is_new_db)
    if success
        global initialized = true
    end
    return success
end

function reinitializeDatabase()
    if !initialized
        return
    end
    global initialized = false
    if db.file == ":memory:" # if the database is in memory, re-initialize it
        initializeDatabase()
    else
        initializeDatabase(db.file; auto_upgrade=true)
    end
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
    global current_physicell_version_id = physicellVersionID()

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
    createICTable("dcs"; data_dir_contents=data_dir_contents)

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
        description = metadataDescription(joinpath(data_dir, "inputs", "configs", config_folder))
        DBInterface.execute(db, "INSERT OR IGNORE INTO configs (folder_name, description) VALUES ('$(config_folder)', '$(description)');")
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
            description = metadataDescription(joinpath(data_dir, "inputs", "rulesets_collections", rulesets_collection_folder))
            DBInterface.execute(db, "INSERT OR IGNORE INTO rulesets_collections (folder_name, description) VALUES ('$(rulesets_collection_folder)', '$(description)');")
            db_rulesets_variations = joinpath(data_dir, "inputs", "rulesets_collections", rulesets_collection_folder, "rulesets_collection_variations.db") |> SQLite.DB
            createPCVCTTable("rulesets_collection_variations", "rulesets_collection_variation_id INTEGER PRIMARY KEY"; db=db_rulesets_variations)
            DBInterface.execute(db_rulesets_variations, "INSERT OR IGNORE INTO rulesets_collection_variations (rulesets_collection_variation_id) VALUES(0);")
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
            DBInterface.execute(db_ic_cell, "INSERT OR IGNORE INTO ic_cell_variations (ic_cell_variation_id) VALUES(0);")
        end
    end

    # initialize and populate ic_ecms variations dbs
    path_to_ic_ecms = joinpath(path_to_ics, "ecms")
    if "ics" in data_dir_contents && "ecms" in readdir(path_to_ics, sort=false)
        ic_ecms_folders = readdir(path_to_ic_ecms, sort=false) |> filter(x -> isdir(joinpath(path_to_ic_ecms, x)))
        for ic_ecm_folder in ic_ecms_folders
            DBInterface.execute(db, "INSERT OR IGNORE INTO ic_ecms (folder_name) VALUES ('$(ic_ecm_folder)');")
            path_to_folder = joinpath(path_to_ic_ecms, ic_ecm_folder)
            is_csv = isfile(joinpath(path_to_folder, "ecm.csv"))
            # ⊻ = XOR (make sure exactly one of the files is present)
            @assert is_csv ⊻ isfile(joinpath(path_to_folder, "ecm.xml")) "Must have one of ecm.csv or ecm.xml in $(joinpath(path_to_folder))"
            if is_csv
                continue # no variations allowed on csv files
            end
            db_ic_ecm = joinpath(path_to_folder, "ic_ecm_variations.db") |> SQLite.DB
            createPCVCTTable("ic_ecm_variations", "ic_ecm_variation_id INTEGER PRIMARY KEY"; db=db_ic_ecm)
            DBInterface.execute(db_ic_ecm, "INSERT OR IGNORE INTO ic_ecm_variations (ic_ecm_variation_id) VALUES(0);")
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
        ic_dc_id INTEGER,
        config_id INTEGER,
        rulesets_collection_id INTEGER,
        config_variation_id INTEGER,
        rulesets_collection_variation_id INTEGER,
        ic_cell_variation_id INTEGER,
        ic_ecm_variation_id INTEGER,
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
        FOREIGN KEY (ic_dc_id)
            REFERENCES ic_dcs (ic_dc_id),
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
    createPCVCTTable("samplings", samplingsSchema())

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
    ic_dc_id INTEGER,
    config_id INTEGER,
    rulesets_collection_id INTEGER,
    config_variation_id INTEGER,
    rulesets_collection_variation_id INTEGER,
    ic_cell_variation_id INTEGER,
    ic_ecm_variation_id INTEGER,
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
    FOREIGN KEY (ic_dc_id)
        REFERENCES ic_dcs (ic_dc_id),
    FOREIGN KEY (config_id)
        REFERENCES configs (config_id),
    FOREIGN KEY (rulesets_collection_id)
        REFERENCES rulesets_collections (rulesets_collection_id),
    UNIQUE (physicell_version_id,custom_code_id,ic_cell_id,ic_substrate_id,ic_ecm_id,ic_dc_id,config_id,rulesets_collection_id,config_variation_id,rulesets_collection_variation_id,ic_cell_variation_id,ic_ecm_variation_id)
   """
end

function samplingsSchema()
    return """
    sampling_id INTEGER PRIMARY KEY,
    physicell_version_id INTEGER,
    custom_code_id INTEGER,
    ic_cell_id INTEGER,
    ic_substrate_id INTEGER,
    ic_ecm_id INTEGER,
    ic_dc_id INTEGER,
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
    FOREIGN KEY (ic_dc_id)
        REFERENCES ic_dcs (ic_dc_id),
    FOREIGN KEY (config_id)
        REFERENCES configs (config_id),
    FOREIGN KEY (rulesets_collection_id)
        REFERENCES rulesets_collections (rulesets_collection_id)
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
                description = metadataDescription(joinpath(data_dir, "inputs", "ics", ic_name, ic_folder))
                DBInterface.execute(db, "INSERT OR IGNORE INTO $(table_name) (folder_name, description) VALUES ('$(ic_folder)', '$(description)');")
            end
        end
    end
    return
end

function metadataDescription(path_to_folder::AbstractString)
    path_to_metadata = joinpath(path_to_folder, "metadata.xml")
    description = ""
    if isfile(path_to_metadata)
        xml_doc = openXML(path_to_metadata)
        metadata = root(xml_doc)
        description_element = find_element(metadata, "description")
        if !isnothing(description_element)
            description = content(find_element(metadata, "description"))
        end
        closeXML(xml_doc)
    end
    return description
end

function icFilename(table_name::String)
    if table_name == "cells"
        return "cells.csv"
    elseif table_name == "substrates"
        return "substrates.csv"
    elseif table_name == "ecms"
        return "ecm.csv"
    elseif table_name == "dcs"
        return "dcs.csv"
    else
        throw(ArgumentError("table_name must be 'cells', 'substrates', 'ecms', or `dcs`."))
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

"""
    isStarted(simulation_id::Int[; new_status_code::Union{Missing,String}=missing])

Check if a simulation has been started.

If `new_status_code` is provided, update the status of the simulation to this value.
The check and status update are done in a transaction to ensure that the status is not changed by another process.
"""
function isStarted(simulation_id::Int; new_status_code::Union{Missing,String}=missing)
    query = constructSelectQuery("simulations", "WHERE simulation_id=$(simulation_id)"; selection="status_code_id")
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
configDB(S::AbstractSampling) = configDB(S.inputs.config.folder)

function rulesetsCollectionDB(rulesets_collection_folder::String)
    if rulesets_collection_folder == ""
        return nothing
    end
    path_to_folder = joinpath(data_dir, "inputs", "rulesets_collections", rulesets_collection_folder)
    return joinpath(path_to_folder, "rulesets_collection_variations.db") |> SQLite.DB
end
rulesetsCollectionDB(S::AbstractSampling) = rulesetsCollectionDB(S.inputs.rulesets_collection.folder)
rulesetsCollectionDB(rulesets_collection_id::Int) = rulesetsCollectionFolder(rulesets_collection_id) |> rulesetsCollectionDB

function icCellDB(ic_cell_folder::String)
    if ic_cell_folder == ""
        return nothing
    end
    path_to_folder = joinpath(data_dir, "inputs", "ics", "cells", ic_cell_folder)
    if isfile(joinpath(path_to_folder, "cells.csv"))
        return missing
    end
    return joinpath(path_to_folder, "ic_cell_variations.db") |> SQLite.DB
end
icCellDB(ic_cell_id::Int) = icCellFolder(ic_cell_id) |> icCellDB
icCellDB(S::AbstractSampling) = icCellDB(S.inputs.ic_cell.folder)

function icECMDB(ic_ecm_folder::String)
    if ic_ecm_folder == ""
        return nothing
    end
    path_to_folder = joinpath(data_dir, "inputs", "ics", "ecms", ic_ecm_folder)
    if isfile(joinpath(path_to_folder, "ecm.csv"))
        return missing
    end
    return joinpath(path_to_folder, "ic_ecm_variations.db") |> SQLite.DB
end
icECMDB(ic_ecm_id::Int) = icECMFolder(ic_ecm_id) |> icECMDB
icECMDB(S::AbstractSampling) = icECMDB(S.inputs.ic_ecm.folder)

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
icSubstrateFolder(ic_substrate_id::Int) = getOptionalFolder("ic_substrates", "ic_substrate_id", ic_substrate_id)
icECMFolder(ic_ecm_id::Int) = getOptionalFolder("ic_ecms", "ic_ecm_id", ic_ecm_id)
icDCFolder(ic_dc_id::Int) = getOptionalFolder("ic_dcs", "ic_dc_id", ic_dc_id)
rulesetsCollectionFolder(rulesets_collection_id::Int) = getOptionalFolder("rulesets_collections", "rulesets_collection_id", rulesets_collection_id)
customCodesFolder(custom_code_id::Int) = getFolder("custom_codes", "custom_code_id", custom_code_id)

function retrieveID(table_name::String, folder_name::String; db::SQLite.DB=db)
    if folder_name == ""
        return -1
    end
    primary_key_string = "$(rstrip(table_name,'s'))_id"
    query = constructSelectQuery(table_name, "WHERE folder_name='$(folder_name)'"; selection=primary_key_string)
    df = queryToDataFrame(query; is_row=true)
    return df[1, primary_key_string]
end

########### Summarizing Database Functions ###########

configVariationIDs(M::AbstractMonad) = [M.variation_ids.config]
configVariationIDs(sampling::Sampling) = [vid.config for vid in sampling.variation_ids]

rulesetsVariationIDs(M::AbstractMonad) = [M.variation_ids.rulesets_collection]
rulesetsVariationIDs(sampling::Sampling) = [vid.rulesets_collection for vid in sampling.variation_ids]

icCellVariationIDs(M::AbstractMonad) = [M.variation_ids.ic_cell]
icCellVariationIDs(sampling::Sampling) = [vid.ic_cell for vid in sampling.variation_ids]

icECMVariationIDs(M::AbstractMonad) = [M.variation_ids.ic_ecm]
icECMVariationIDs(sampling::Sampling) = [vid.ic_ecm for vid in sampling.variation_ids]

function variationsTable(query::String, db::SQLite.DB; remove_constants::Bool=false)
    df = queryToDataFrame(query, db=db)
    if remove_constants && size(df, 1) > 1
        col_names = names(df)
        filter!(n -> length(unique(df[!,n])) > 1, col_names)
        select!(df, col_names)
    end
    return df
end

function configVariationsTable(config_variations_db::SQLite.DB, config_variation_ids::AbstractVector{<:Integer}; remove_constants::Bool=false)
    query = constructSelectQuery("config_variations", "WHERE config_variation_id IN ($(join(config_variation_ids,",")));")
    df = variationsTable(query, config_variations_db; remove_constants=remove_constants)
    rename!(simpleConfigVariationNames, df)
    return df
end

configVariationsTable(S::AbstractSampling; remove_constants::Bool=false) = configVariationsTable(configDB(S), configVariationIDs(S); remove_constants=remove_constants)

function rulesetsVariationsTable(rulesets_variations_db::SQLite.DB, rulesets_collection_variation_ids::AbstractVector{<:Integer}; remove_constants::Bool=false)
    rulesets_collection_variation_ids = filter(x -> x != -1, rulesets_collection_variation_ids) # rulesets_collection_variation_id = -1 means no ruleset being used
    query = constructSelectQuery("rulesets_collection_variations", "WHERE rulesets_collection_variation_id IN ($(join(rulesets_collection_variation_ids,",")));")
    df = variationsTable(query, rulesets_variations_db; remove_constants=remove_constants)
    rename!(simpleRulesetsVariationNames, df)
    return df
end

function rulesetsVariationsTable(::Nothing, rulesets_collection_variation_ids::AbstractVector{<:Integer}; kwargs...)
    @assert all(x -> x == -1, rulesets_collection_variation_ids) "If the rulesets_collection_variation_id is missing, then all rulesets_collection_variation_ids must be -1."
    return DataFrame(RulesVarID=rulesets_collection_variation_ids)
end

rulesetsVariationsTable(S::AbstractSampling; remove_constants::Bool=false) = rulesetsVariationsTable(rulesetsCollectionDB(S), rulesetsVariationIDs(S); remove_constants=remove_constants)

function icCellVariationsTable(ic_cell_variations_db::SQLite.DB, ic_cell_variation_ids::AbstractVector{<:Integer}; remove_constants::Bool=false)
    query = constructSelectQuery("ic_cell_variations", "WHERE ic_cell_variation_id IN ($(join(ic_cell_variation_ids,",")));")
    df = variationsTable(query, ic_cell_variations_db; remove_constants=remove_constants)
    rename!(simpleICCellVariationNames, df)
    return df
end

function icCellVariationsTable(::Nothing, ic_cell_variation_ids::AbstractVector{<:Integer}; kwargs...)
    @assert all(x -> x == -1, ic_cell_variation_ids) "If no ic_cell_folder is given, then all ic_cell_variation_ids must be -1."
    return DataFrame(ICCellVarID=ic_cell_variation_ids)
end

function icCellVariationsTable(::Missing, ic_cell_variation_ids::AbstractVector{<:Integer}; kwargs...)
    @assert all(x -> x == 0, ic_cell_variation_ids) "If the ic_cell_folder contains a cells.csv, then all ic_cell_variation_ids must be 0."
    return DataFrame(ICCellVarID=ic_cell_variation_ids)
end

icCellVariationsTable(S::AbstractSampling; remove_constants::Bool=false) = icCellVariationsTable(icCellDB(S), icCellVariationIDs(S); remove_constants=remove_constants)

function icECMVariationsTable(ic_ecm_variations_db::SQLite.DB, ic_ecm_variation_ids::AbstractVector{<:Integer}; remove_constants::Bool=false)
    query = constructSelectQuery("ic_ecm_variations", "WHERE ic_ecm_variation_id IN ($(join(ic_ecm_variation_ids,",")));")
    df = variationsTable(query, ic_ecm_variations_db; remove_constants=remove_constants)
    rename!(simpleICECMVariationNames, df)
    return df
end

function icECMVariationsTable(::Nothing, ic_ecm_variation_ids::AbstractVector{<:Integer}; kwargs...)
    @assert all(x -> x == -1, ic_ecm_variation_ids) "If no ic_ecm_folder is given, then all ic_ecm_variation_ids must be -1."
    return DataFrame(ICECMVarID=ic_ecm_variation_ids)
end

function icECMVariationsTable(::Missing, ic_ecm_variation_ids::AbstractVector{<:Integer}; kwargs...)
    @assert all(x -> x == 0, ic_ecm_variation_ids) "If the ic_ecm_folder contains a ecm.csv, then all ic_ecm_variation_ids must be 0."
    return DataFrame(ICECMVarID=ic_ecm_variation_ids)
end

icECMVariationsTable(S::AbstractSampling; remove_constants::Bool=false) = icECMVariationsTable(icECMDB(S), icECMVariationIDs(S); remove_constants=remove_constants)

function variationsTableFromSimulations(query::String, id_name::Symbol, getVariationsTableFn::Function; remove_constants::Bool=false)
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

function configVariationsTable(simulation_ids::AbstractVector{<:Integer}; remove_constants::Bool=false)
    query = constructSelectQuery("simulations", "WHERE simulation_id IN ($(join(simulation_ids,",")));", selection="config_id, config_variation_id")
    getVariationsTableFn = x -> configVariationsTable(configDB(x[1]), [x[2]]; remove_constants=remove_constants)
    return variationsTableFromSimulations(query, :ConfigVarID, getVariationsTableFn)
end


function rulesetsVariationsTable(simulation_ids::AbstractVector{<:Integer}; remove_constants::Bool=false)
    query = constructSelectQuery("simulations", "WHERE simulation_id IN ($(join(simulation_ids,",")));", selection="rulesets_collection_id, rulesets_collection_variation_id")
    getVariationsTableFn = x -> rulesetsVariationsTable(rulesetsCollectionDB(x[1]), [x[2]]; remove_constants=remove_constants)
    return variationsTableFromSimulations(query, :RulesVarID, getVariationsTableFn)
end

function icCellVariationsTable(simulation_ids::AbstractVector{<:Integer}; remove_constants::Bool=false)
    query = constructSelectQuery("simulations", "WHERE simulation_id IN ($(join(simulation_ids,",")));", selection="ic_cell_id, ic_cell_variation_id")
    getVariationsTableFn = x -> icCellVariationsTable(icCellDB(x[1]), [x[2]]; remove_constants=remove_constants)
    return variationsTableFromSimulations(query, :ICCellVarID, getVariationsTableFn)
end

function icECMVariationsTable(simulation_ids::AbstractVector{<:Integer}; remove_constants::Bool=false)
    query = constructSelectQuery("simulations", "WHERE simulation_id IN ($(join(simulation_ids,",")));", selection="ic_ecm_id, ic_ecm_variation_id")
    getVariationsTableFn = x -> icECMVariationsTable(icECMDB(x[1]), [x[2]]; remove_constants=remove_constants)
    return variationsTableFromSimulations(query, :ICECMVarID, getVariationsTableFn)
end

function addFolderColumns!(df::DataFrame)
    col_names = ["custom_code", "config", "rulesets_collection", "ic_cell", "ic_substrate", "ic_ecm", "ic_dc"]
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
    filter!(n -> !(n in ["simulation_id", "config_variation_id", "ic_cell_id", "rulesets_collection_variation_id", "ic_cell_variation_id", "ic_ecm_variation_id"]), id_col_names_to_remove) # keep the simulation_id and config_variation_id columns
    addFolderColumns!(df) # add the folder columns
    select!(df, Not(id_col_names_to_remove)) # remove the id columns

    # handle each of the varying inputs
    unique_tuples_config = [(row.config_folder, row.config_variation_id) for row in eachrow(df)] |> unique
    df = appendVariations(df, unique_tuples_config, configDB, configVariationsTable, :config_folder => :folder_name, :config_variation_id => :ConfigVarID)
    unique_tuples_rulesets_collection = [(row.rulesets_collection_folder, row.rulesets_collection_variation_id) for row in eachrow(df)] |> unique
    df = appendVariations(df, unique_tuples_rulesets_collection, rulesetsCollectionDB, rulesetsVariationsTable, :rulesets_collection_folder => :folder_name, :rulesets_collection_variation_id => :RulesVarID)
    unique_tuples_ic_cell = [(row.ic_cell_folder, row.ic_cell_variation_id) for row in eachrow(df)] |> unique
    df = appendVariations(df, unique_tuples_ic_cell, icCellDB, icCellVariationsTable, :ic_cell_folder => :folder_name, :ic_cell_variation_id => :ICCellVarID)
    unique_tuples_ic_ecm = [(row.ic_ecm_folder, row.ic_ecm_variation_id) for row in eachrow(df)] |> unique
    df = appendVariations(df, unique_tuples_ic_ecm, icECMDB, icECMVariationsTable, :ic_ecm_folder => :folder_name, :ic_ecm_variation_id => :ICECMVarID)

    rename!(df, [:simulation_id => :SimID, :config_variation_id => :ConfigVarID, :rulesets_collection_variation_id => :RulesVarID, :ic_cell_variation_id => :ICCellVarID, :ic_ecm_variation_id => :ICECMVarID])
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
        temp_df = getVariationsTableFn(getDBFn(unique_tuple[1]), [unique_tuple[2]]; remove_constants=false)
        temp_df[!,:folder_name] .= unique_tuple[1]
        append!(var_df, temp_df, cols=:union)
    end
    return outerjoin(df, var_df, on = [folder_pair, id_pair])
end

function simulationsTable(T::Union{AbstractTrial,AbstractArray{<:AbstractTrial}}; kwargs...)
    query = constructSelectQuery("simulations", "WHERE simulation_id IN ($(join(getSimulationIDs(T),",")));")
    return simulationsTableFromQuery(query; kwargs...)
end

function simulationsTable(simulation_ids::AbstractVector{<:Integer}; kwargs...)
    query = constructSelectQuery("simulations", "WHERE simulation_id IN ($(join(simulation_ids,",")));")
    return simulationsTableFromQuery(query; kwargs...)
end

function simulationsTable(; kwargs...)
    query = constructSelectQuery("simulations")
    return simulationsTableFromQuery(query; kwargs...)
end

########### Printing Database Functions ###########

printConfigVariationsTable(args...; kwargs...) = configVariationsTable(args...; kwargs...) |> println
printRulesetsVariationsTable(args...; kwargs...) = rulesetsVariationsTable(args...; kwargs...) |> println
printICCellVariationsTable(args...; kwargs...) = icCellVariationsTable(args...; kwargs...) |> println
printICECMVariationsTable(args...; kwargs...) = icECMVariationsTable(args...; kwargs...) |> println

"""
    printSimulationsTable()

Print a table of simulations and their varied values. See keyword arguments below for more control of the output.

There are many methods for this function. The simplest is `printSimulationsTable()`, which prints all simulations in the database.
You can also pass in any number of simulations, monads, samplings, and trials to print a table of those simulations:
```
printSimulationsTable([simulation_1, monad_3, sampling_2, trial_1])
```
Finally, a vector of simulation IDs can be passed in:
```
printSimulationsTable([1, 2, 3])
```
Keyword arguments can be used with any of these methods to control the output:
# Keyword Arguments
- `sink`: A function to print the table. Defaults to `println`. Note, the table is a DataFrame, so you can also use `CSV.write` to write the table to a CSV file.
- `remove_constants::Bool`: If true, removes columns that have the same value for all simulations. Defaults to true.
- `sort_by::Vector{String}`: A vector of column names to sort the table by. Defaults to all columns. To populate this argument, first print the table to see the column names.
- `sort_ignore::Vector{String}`: A vector of column names to ignore when sorting. Defaults to the database IDs associated with the simulations.
"""
printSimulationsTable(args...; sink=println, kwargs...) = simulationsTable(args...; kwargs...) |> sink
