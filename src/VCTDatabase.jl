export printSimulationsTable, printVariationsTable, getSimulationsTable

db::SQLite.DB = SQLite.DB()

################## Database Initialization Functions ##################

function initializeDatabase(path_to_database::String)
    println(rpad("Path to database:", 20, ' ') * path_to_database)
    global db = SQLite.DB(path_to_database)
    return createSchema()
end

function initializeDatabase()
    global db = SQLite.DB()
    return createSchema()
end

function patchBaseRulesetsVariationNotInDB(rulesets_collection_folder::String, db_rulesets_variations::SQLite.DB)
    # then we are adding in this row after the db was made (so that means the db was made before this got patched)
    column_names = queryToDataFrame("PRAGMA table_info(rulesets_variations);"; db=db_rulesets_variations) |> x->x[!,:name]
    filter!(x -> x != "rulesets_variation_id", column_names) 
    path_to_rulesets_collections_folder = joinpath(data_dir, "inputs", "rulesets_collections", rulesets_collection_folder)
    path_to_xml = joinpath(path_to_rulesets_collections_folder, "base_rulesets.xml")
    if !isfile(path_to_xml)
        writeRules(path_to_xml, joinpath(path_to_rulesets_collections_folder, "base_rulesets.csv"))
    end
    xml_doc = openXML(path_to_xml)
    for column_name in column_names
        xml_path = columnNameToXMLPath(column_name)
        base_value = getField(xml_doc, xml_path)
        query = "UPDATE rulesets_variations SET '$(column_name)'=$(base_value) WHERE rulesets_variation_id=0;"
        DBInterface.execute(db_rulesets_variations, query)
    end
end

function createSchema()
    # make sure necessary directories are present
    data_dir_contents = readdir(joinpath(data_dir, "inputs"); sort=false)
    if !("custom_codes" in data_dir_contents)
        error("No $(joinpath(data_dir, "inputs", "custom_codes")) found. This is where to put the folders for custom_modules, main.cpp, and Makefile.")
    end
    if !("configs" in data_dir_contents)
        error("No $(joinpath(data_dir, "inputs", "configs")) found. This is where to put the folders for config files and rules files.")
    end

    # initialize and populate custom_codes table
    custom_codes_schema = """
        custom_code_id INTEGER PRIMARY KEY,
        folder_name UNIQUE,
        description TEXT
    """
    createPCVCTTable("custom_codes", custom_codes_schema)
        
    custom_codes_folders = readdir(joinpath(data_dir, "inputs", "custom_codes"); sort=false) |> filter(x->isdir(joinpath(data_dir, "inputs", "custom_codes", x)))
    if isempty(custom_codes_folders)
        error("No folders in $(joinpath(data_dir, "inputs", "custom_codes")) found. Add custom_modules, main.cpp, and Makefile to a folder here to move forward.")
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
        error("No folders in $(joinpath(data_dir, "inputs", "configs")) found. Add PhysiCell_settings.xml and rules files here.")
    end
    patched_variation_id_to_config_variation_id = false
    for config_folder in config_folders
        patch_to_003 = false
        DBInterface.execute(db, "INSERT OR IGNORE INTO configs (folder_name) VALUES ('$(config_folder)');")
        if isfile(joinpath(data_dir, "inputs", "configs", config_folder, "variations.db"))
            # patch for 0.0.2 to 0.0.3
            mv(joinpath(data_dir, "inputs", "configs", config_folder, "variations.db"), joinpath(data_dir, "inputs", "configs", config_folder, "config_variations.db"))
            patch_to_003 = true
            if !patched_variation_id_to_config_variation_id
                # rename column from variation_id to config_variation_id
                DBInterface.execute(db, "ALTER TABLE simulations RENAME COLUMN variation_id TO config_variation_id;")
                DBInterface.execute(db, "ALTER TABLE monads RENAME COLUMN variation_id TO config_variation_id;")
                DBInterface.execute(db, "ALTER TABLE simulations ADD COLUMN ic_cell_variation_id INTEGER;")
                # set all these new columns to -1 if ic_cell_id is -1 and to 0 if ic_cell_id is not -1
                DBInterface.execute(db, "UPDATE simulations SET ic_cell_variation_id=CASE WHEN ic_cell_id=-1 THEN -1 ELSE 0 END;")
                DBInterface.execute(db, "ALTER TABLE monads ADD COLUMN ic_cell_variation_id INTEGER;")
                # drop the previous unique constraint on monads
                DBInterface.execute(db, "CREATE TABLE monads_temp AS SELECT * FROM monads;")
                DBInterface.execute(db, "DROP TABLE monads;")
                patched_variation_id_to_config_variation_id = true
            end
        end
        db_config_variations = joinpath(data_dir, "inputs", "configs", config_folder, "config_variations.db") |> SQLite.DB
        if patch_to_003
            # rename table from variations to config_variations
            DBInterface.execute(db_config_variations, "ALTER TABLE variations RENAME TO config_variations;")
            # rename column from variation_id to config_variation_id
            DBInterface.execute(db_config_variations, "ALTER TABLE config_variations RENAME COLUMN variation_id TO config_variation_id;")
            index_df = DBInterface.execute(db_config_variations, "SELECT type,name,tbl_name,sql FROM sqlite_master WHERE type = 'index';") |> DataFrame
            variations_index = index_df[!, :name] .== "variations_index"
            variations_sql = index_df[variations_index, :sql][1]
            cols = split(variations_sql, "(")[2]
            cols = split(cols, ")")[1]
            cols = split(cols, ",") .|> string
            SQLite.createindex!(db_config_variations, "config_variations", "config_variations_index", cols; unique=true, ifnotexists=false)
            if isdir(joinpath(data_dir, "inputs", "configs", config_folder, "variations"))
                mv(joinpath(data_dir, "inputs", "configs", config_folder, "variations"), joinpath(data_dir, "inputs", "configs", config_folder, "config_variations"))
                for file in readdir(joinpath(data_dir, "inputs", "configs", config_folder, "config_variations"))
                    mv(joinpath(data_dir, "inputs", "configs", config_folder, "config_variations", file), joinpath(data_dir, "inputs", "configs", config_folder, "config_variations", "config_$(file)"))
                end
            end
        end
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
            df = DBInterface.execute(db_rulesets_variations, "INSERT OR IGNORE INTO rulesets_variations (rulesets_variation_id) VALUES(0) RETURNING rulesets_variation_id;") |> DataFrame
            if !isempty(df)
                patchBaseRulesetsVariationNotInDB(rulesets_collection_folder, db_rulesets_variations)
            end
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
    monads_schema = """
        monad_id INTEGER PRIMARY KEY,
        custom_code_id INTEGER,
        ic_cell_id INTEGER,
        ic_substrate_id INTEGER,
        ic_ecm_id INTEGER,
        config_id INTEGER,
        rulesets_collection_id INTEGER,
        config_variation_id INTEGER,
        rulesets_variation_id INTEGER,
        ic_cell_variation_id INTEGER,
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
        UNIQUE (custom_code_id,ic_cell_id,ic_substrate_id,ic_ecm_id,config_id,rulesets_collection_id,config_variation_id,rulesets_variation_id,ic_cell_variation_id)
    """
    createPCVCTTable("monads", monads_schema)

    if patched_variation_id_to_config_variation_id
        # drop the previous unique constraint on monads
        # insert from monads_temp all values except ic_cell_variation_id (set that to -1 if ic_cell_id is -1 and to 0 if ic_cell_id is not -1)
        DBInterface.execute(db, "INSERT INTO monads SELECT monad_id, custom_code_id, ic_cell_id, ic_substrate_id, ic_ecm_id, config_id, rulesets_collection_id, config_variation_id, rulesets_variation_id, CASE WHEN ic_cell_id=-1 THEN -1 ELSE 0 END FROM monads_temp;")
        DBInterface.execute(db, "DROP TABLE monads_temp;")
    end

    # initialize samplings table
    samplings_schema = """
        sampling_id INTEGER PRIMARY KEY,
        custom_code_id INTEGER,
        ic_cell_id INTEGER,
        ic_substrate_id INTEGER,
        ic_ecm_id INTEGER,
        config_id INTEGER,
        rulesets_collection_id INTEGER,
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

    return
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

getConfigDB(config_folder::String) = joinpath(data_dir, "inputs", "configs", config_folder, "config_variations.db") |> SQLite.DB
getConfigDB(config_id::Int) = getConfigFolder(config_id) |> getConfigDB
getConfigDB(S::AbstractSampling) = getConfigDB(S.folder_names.config_folder)

function getRulesetsCollectionDB(rulesets_collection_folder::String)
    if rulesets_collection_folder == ""
        return missing
    end
    path_to_folder = joinpath(data_dir, "inputs", "rulesets_collections", rulesets_collection_folder)
    return joinpath(path_to_folder, "rulesets_variations.db") |> SQLite.DB
end
getRulesetsCollectionDB(M::AbstractMonad) = getRulesetsCollectionDB(M.folder_names.rulesets_collection_folder)
getRulesetsCollectionDB(rulesets_collection_id::Int) = getRulesetsCollectionFolder(rulesets_collection_id) |> getRulesetsCollectionDB

function getICCellDB(ic_cell_folder::String)
    if ic_cell_folder == ""
        return missing
    end
    path_to_folder = joinpath(data_dir, "inputs", "ics", "cells", ic_cell_folder)
    if isfile(joinpath(path_to_folder, "cells.csv"))
        return missing
    end
    return joinpath(path_to_folder, "ic_cell_variations.db") |> SQLite.DB
end
getICCellDB(ic_cell_id::Int) = getICCellFolder(ic_cell_id) |> getICCellDB
getICCellDB(S::AbstractSampling) = getICCellDB(S.folder_names.ic_cell_folder)

########### Retrieving Database Information Functions ###########

vctDBQuery(query::String; db::SQLite.DB=db) = DBInterface.execute(db, query)

function queryToDataFrame(query::String; db::SQLite.DB=db, is_row::Bool=false) 
    df = vctDBQuery(query; db=db) |> DataFrame
    if is_row
        @assert size(df,1)==1 "Did not find exactly one row matching the query:\n\tDatabase file: $(db)\n\tQuery: $(query)\nResult: $(df)"
    end
    return df
end

constructSelectQuery(table_name::String, condition_stmt::String; selection::String = "*") = "SELECT $(selection) FROM $(table_name) $(condition_stmt);"

function getFolder(table_name::String, id_name::String, id::Int; db::SQLite.DB=db)
    query = constructSelectQuery(table_name, "WHERE $(id_name)=$(id);"; selection="folder_name")
    return queryToDataFrame(query; is_row=true) |> x -> x.folder_name[1]
end

getOptionalFolder(table_name::String, id_name::String, id::Int; db::SQLite.DB=db) = id == -1 ? "" : getFolder(table_name, id_name, id; db=db)

getConfigFolder(config_id::Int) = getFolder("configs", "config_id", config_id)
getICCellFolder(ic_cell_id::Int) = getOptionalFolder("ic_cells", "ic_cell_id", ic_cell_id)
getICSubstrateFolder(ic_substrate_id::Int) = getOptionalFolder("ic_substrates", "ic_substrate_id", ic_substrate_id)
getICECMFolder(ic_ecm_id::Int) = getOptionalFolder("ic_ecms", "ic_ecm_id", ic_ecm_id)
getRulesetsCollectionFolder(rulesets_collection_id::Int) = getOptionalFolder("rulesets_collections", "rulesets_collection_id", rulesets_collection_id)
getCustomCodesFolder(custom_code_id::Int) = getFolder("custom_codes", "custom_code_id", custom_code_id)

function retrievePathInfo(config_id::Int, rulesets_collection_id::Int, ic_cell_id::Int, ic_substrate_id::Int, ic_ecm_id::Int, custom_code_id::Int)
    config_folder = getConfigFolder(config_id)
    rulesets_collection_folder = getRulesetsCollectionFolder(rulesets_collection_id)
    ic_cell_folder = getICCellFolder(ic_cell_id)
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

getConfigVariationIDs(M::AbstractMonad) = [M.variation_ids.config_variation_id]
getConfigVariationIDs(sampling::Sampling) = [vid.config_variation_ids for vid in sampling.variation_ids]

getRulesetsVariationIDs(M::AbstractMonad) = [M.variation_ids.rulesets_variation_id]
getRulesetsVariationIDs(sampling::Sampling) = [vid.rulesets_variation_ids for vid in sampling.variation_ids]

getICCellVariationIDs(M::AbstractMonad) = [M.variation_ids.ic_cell_variation_id]
getICCellVariationIDs(sampling::Sampling) = [vid.ic_cell_variation_ids for vid in sampling.variation_ids]

getAbstractTrial(class_id::VCTClassID) = class_id.id |> getVCTClassIDType(class_id)

function getVariationsTable(query::String, db::SQLite.DB; remove_constants::Bool = false)
    df = queryToDataFrame(query, db=db)
    if remove_constants && size(df, 1) > 1
        col_names = names(df)
        filter!(n -> length(unique(df[!,n])) > 1, col_names)
        select!(df, col_names)
    end
    return df
end

function getConfigVariationsTable(config_variations_db::SQLite.DB, config_variation_ids::AbstractVector{<:Integer}; remove_constants::Bool = false)
    query = constructSelectQuery("config_variations", "WHERE config_variation_id IN ($(join(config_variation_ids,",")));")
    df = getVariationsTable(query, config_variations_db; remove_constants = remove_constants)
    rename!(simpleConfigVariationNames, df)
    return df
end

getConfigVariationsTable(S::AbstractSampling; remove_constants::Bool=false) = getConfigVariationsTable(getConfigDB(S), getConfigVariationIDs(S); remove_constants = remove_constants)
getConfigVariationsTable(class_id::VCTClassID{<:AbstractSampling}; remove_constants::Bool = false) = getAbstractTrial(class_id) |> x -> getConfigVariationsTable(x; remove_constants = remove_constants)

function getRulesetsVariationsTable(rulesets_variations_db::SQLite.DB, rulesets_variation_ids::AbstractVector{<:Integer}; remove_constants::Bool = false)
    rulesets_variation_ids = filter(x -> x != -1, rulesets_variation_ids) # rulesets_variation_id = -1 means no ruleset being used
    query = constructSelectQuery("rulesets_variations", "WHERE rulesets_variation_id IN ($(join(rulesets_variation_ids,",")));")
    df = getVariationsTable(query, rulesets_variations_db; remove_constants = remove_constants)
    rename!(simpleRulesetsVariationNames, df)
    return df
end

function getRulesetsVariationsTable(::Missing, rulesets_variation_ids::AbstractVector{<:Integer}; remove_constants::Bool = false)
    @assert all(x -> x == -1, rulesets_variation_ids) "If the rulesets_variation_id is missing, then all rulesets_variation_ids must be -1."
    return DataFrame(RulesVarID=rulesets_variation_ids)
end

getRulesetsVariationsTable(S::AbstractSampling; remove_constants::Bool=false) = getRulesetsVariationsTable(getRulesetsCollectionDB(S), getRulesetsVariationIDs(S); remove_constants = remove_constants)
getRulesetsVariationsTable(class_id::VCTClassID{<:AbstractSampling}; remove_constants::Bool = false) = getAbstractTrial(class_id) |> x -> getRulesetsVariationsTable(x; remove_constants = remove_constants)

function getICCellVariationsTable(ic_cell_variations_db::SQLite.DB, ic_cell_variation_ids::AbstractVector{<:Integer}; remove_constants::Bool = false)
    query = constructSelectQuery("ic_cell_variations", "WHERE ic_cell_variation_id IN ($(join(ic_cell_variation_ids,",")));")
    df = getVariationsTable(query, ic_cell_variations_db; remove_constants = remove_constants)
    rename!(simpleICCellVariationNames, df)
    return df
end

function getICCellVariationsTable(::Missing, ic_cell_variation_ids::AbstractVector{<:Integer}; remove_constants::Bool = false)
    @assert all(x -> x == -1, ic_cell_variation_ids) "If the ic_cell_variation_id is missing, then all ic_cell_variation_ids must be -1."
    return DataFrame(ICCellVarID=ic_cell_variation_ids)
end

getICCellVariationsTable(S::AbstractSampling; remove_constants::Bool=false) = getICCellVariationsTable(getICCellDB(S), getICCellVariationIDs(S); remove_constants = remove_constants)
getICCellVariationsTable(class_id::VCTClassID{<:AbstractSampling}; remove_constants::Bool = false) = getAbstractTrial(class_id) |> x -> getICCellVariationsTable(x; remove_constants = remove_constants)

function getVariationsTableFromSimulations(query::String, id_name::Symbol, getVariationsTableFn::Function; remove_constants::Bool = false)
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

function getConfigVariationsTable(simulation_ids::AbstractVector{<:Integer}; remove_constants::Bool = false)
    query = constructSelectQuery("simulations", "WHERE simulation_id IN ($(join(simulation_ids,",")));", selection="config_id, config_variation_id")
    getVariationsTableFn = x -> getConfigVariationsTable(getConfigDB(x[1]), [x[2]]; remove_constants = false)
    return getVariationsTableFromSimulations(query, :ConfigVarID, getVariationsTableFn)
end


function getRulesetsVariationsTable(simulation_ids::AbstractVector{<:Integer}; remove_constants::Bool = false)
    query = constructSelectQuery("simulations", "WHERE simulation_id IN ($(join(simulation_ids,",")));", selection="rulesets_collection_id, rulesets_variation_id")
    getVariationsTableFn = x -> getRulesetsVariationsTable(getRulesetsCollectionDB(x[1]), [x[2]]; remove_constants = false)
    return getVariationsTableFromSimulations(query, :RulesVarID, getVariationsTableFn)
end

function getICCellVariationsTable(simulation_ids::AbstractVector{<:Integer}; remove_constants::Bool = false)
    query = constructSelectQuery("simulations", "WHERE simulation_id IN ($(join(simulation_ids,",")));", selection="ic_cell_id, ic_cell_variation_id")
    getVariationsTableFn = x -> getICCellVariationsTable(getICCellDB(x[1]), [x[2]]; remove_constants = false)
    return getVariationsTableFromSimulations(query, :ICCellVarID, getVariationsTableFn)
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

function getSimulationsTableFromQuery(query::String; remove_constants::Bool=true, sort_by::Vector{String}=String[], sort_ignore::Vector{String}=["SimID", "ConfigVarID", "RulesVarID", "ICCellVarID"])
    df = queryToDataFrame(query)
    id_col_names_to_remove = names(df) # a bunch of ids that we don't want to show
    filter!(n -> !(n in ["simulation_id", "config_variation_id", "ic_cell_id", "rulesets_variation_id", "ic_cell_variation_id"]), id_col_names_to_remove) # keep the simulation_id and config_variation_id columns
    addFolderColumns!(df) # add the folder columns
    select!(df, Not(id_col_names_to_remove)) # remove the id columns
    unique_tuples = [(row.config_folder, row.config_variation_id) for row in eachrow(df)] |> unique
    df = appendVariations(df, unique_tuples, getConfigDB, getConfigVariationsTable, :config_folder => :folder_name, :config_variation_id => :ConfigVarID)
    unique_tuples = [(row.rulesets_collection_folder, row.rulesets_variation_id) for row in eachrow(df)] |> unique
    df = appendVariations(df, unique_tuples, getRulesetsCollectionDB, getRulesetsVariationsTable, :rulesets_collection_folder => :folder_name, :rulesets_variation_id => :RulesVarID)
    unique_tuples = [(row.ic_cell_folder, row.ic_cell_variation_id) for row in eachrow(df)] |> unique
    df = appendVariations(df, unique_tuples, getICCellDB, getICCellVariationsTable, :ic_cell_folder => :folder_name, :ic_cell_variation_id => :ICCellVarID)
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

function getSimulationsTable(T::Union{AbstractTrial,AbstractArray{<:AbstractTrial}}; remove_constants::Bool = true, sort_by::Vector{String}=String[], sort_ignore::Vector{String}=["SimID", "ConfigVarID", "RulesVarID", "ICCellVarID"])
    query = constructSelectQuery("simulations", "WHERE simulation_id IN ($(join(getSimulationIDs(T),",")));")
    return getSimulationsTableFromQuery(query; remove_constants = remove_constants, sort_by = sort_by, sort_ignore = sort_ignore)
end

function getSimulationsTable(simulation_ids::AbstractVector{<:Integer}; remove_constants::Bool = true, sort_by::Vector{String}=String[], sort_ignore::Vector{String}=["SimID", "ConfigVarID", "RulesVarID", "ICCellVarID"])
    query = constructSelectQuery("simulations", "WHERE simulation_id IN ($(join(simulation_ids,",")));")
    return getSimulationsTableFromQuery(query; remove_constants = remove_constants, sort_by = sort_by, sort_ignore = sort_ignore)
end

function getSimulationsTable(; remove_constants::Bool = true, sort_by::Vector{String}=String[], sort_ignore::Vector{String}=["SimID", "ConfigVarID", "RulesVarID", "ICCellVarID"])
    query = constructSelectQuery("simulations", "")
    return getSimulationsTableFromQuery(query; remove_constants = remove_constants, sort_by = sort_by, sort_ignore = sort_ignore)
end

function getSimulationsTable(class_id::VCTClassID; remove_constants::Bool = true, sort_by::Vector{String}=String[], sort_ignore::Vector{String}=["SimID", "ConfigVarID", "RulesVarID", "ICCellVarID"])
    query = constructSelectQuery("simulations", "WHERE simulation_id IN ($(join(getSimulationIDs(class_id),",")));")
    return getSimulationsTableFromQuery(query; remove_constants = remove_constants, sort_by = sort_by, sort_ignore = sort_ignore)
end

########### Printing Database Functions ###########

printConfigVariationsTable(args...; kwargs...) = getConfigVariationsTable(args...; kwargs...) |> println
printRulesetsVariationsTable(args...; kwargs...) = getRulesetsVariationsTable(args...; kwargs...) |> println

printSimulationsTable(args...; sink=println, kwargs...) = getSimulationsTable(args...; kwargs...) |> sink
