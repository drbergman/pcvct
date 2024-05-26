export printSimulationsTable, printVariationsTable

db::SQLite.DB = SQLite.DB()

################## Database Initialization Functions ##################

function initializeDatabase(path_to_database::String)
    println(path_to_database)
    println("loading up the global db variable")
    global db = SQLite.DB(path_to_database)
    println("VCT database located at $(path_to_database) loaded.")
    return createSchema()
end

function initializeDatabase()
    global db = SQLite.DB()
    return createSchema()
end

function createSchema()
    # make sure necessary directories are present
    data_dir_contents = readdir("$(data_dir)/inputs/", sort=false)
    if !("custom_codes" in data_dir_contents)
        error("No $(data_dir)/inputs/custom_codes found. This is where to put the folders for custom_modules, main.cpp, and Makefile.")
    end
    if !("configs" in data_dir_contents)
        error("No $(data_dir)/inputs/configs found. This is where to put the folders for config files and rules files.")
    end

    # initialize and populate custom_codes table
    custom_codes_schema = """
        custom_code_id INTEGER PRIMARY KEY,
        folder_name UNIQUE,
        description TEXT
    """
    createPCVCTTable("custom_codes", custom_codes_schema)
        
    custom_codes_folders = readdir("$(data_dir)/inputs/custom_codes", sort=false) |> filter(x->isdir("$(data_dir)/inputs/custom_codes/$(x)"))
    if isempty(custom_codes_folders)
        error("No folders in $(data_dir)/inputs/custom_codes found. Add custom_modules, main.cpp, and Makefile to a folder here to move forward.")
    end
    for custom_codes_folder in custom_codes_folders
        DBInterface.execute(db, "INSERT OR IGNORE INTO custom_codes (folder_name) VALUES ('$(custom_codes_folder)');")
    end
    
    # initialize and populate ics tables
    createICTable("cells", data_dir_contents=data_dir_contents)
    createICTable("substrates", data_dir_contents=data_dir_contents)
    createICTable("ecms", data_dir_contents=data_dir_contents)

    # initialize and populate configs table
    configs_schema = """
        config_id INTEGER PRIMARY KEY,
        folder_name UNIQUE,
        description TEXT
    """
    createPCVCTTable("configs", configs_schema)
        
    config_folders = readdir("$(data_dir)/inputs/configs", sort=false) |> filter(x->isdir("$(data_dir)/inputs/configs/$(x)"))
    if isempty(config_folders)
        error("No folders in $(data_dir)/inputs/configs found. Add PhysiCell_settings.xml and rules files here.")
    end
    for config_folder in config_folders
        DBInterface.execute(db, "INSERT OR IGNORE INTO configs (folder_name) VALUES ('$(config_folder)');")
        db_variations = "$(data_dir)/inputs/configs/$(config_folder)/variations.db" |> SQLite.DB
        createPCVCTTable("variations", "variation_id INTEGER PRIMARY KEY"; db=db_variations)
        DBInterface.execute(db_variations, "INSERT OR IGNORE INTO variations (variation_id) VALUES(0);")
    end

    # initialize and populate rulesets_collections table
    rulesets_collections_schema = """
        rulesets_collection_id INTEGER PRIMARY KEY,
        folder_name UNIQUE,
        description TEXT
    """
    createPCVCTTable("rulesets_collections", rulesets_collections_schema)

    if "rulesets_collections" in data_dir_contents
        rulesets_collections_folders = readdir("$(data_dir)/inputs/rulesets_collections", sort=false) |> filter(x -> isdir("$(data_dir)/inputs/rulesets_collections/$(x)"))
        for rulesets_collection_folder in rulesets_collections_folders
            DBInterface.execute(db, "INSERT OR IGNORE INTO rulesets_collections (folder_name) VALUES ('$(rulesets_collection_folder)');")
            db_rulesets_variations = "$(data_dir)/inputs/rulesets_collections/$(rulesets_collection_folder)/rulesets_variations.db" |> SQLite.DB
            createPCVCTTable("rulesets_variations", "rulesets_variation_id INTEGER PRIMARY KEY"; db=db_rulesets_variations)
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
        variation_id INTEGER,
        rulesets_variation_id INTEGER,
        FOREIGN KEY (custom_code_id)
            REFERENCES custom_codes (custom_code_id),
        FOREIGN KEY (ic_cell_id)
            REFERENCES ic_cells (ic_cell_id),
        FOREIGN KEY (ic_substrate_id)
            REFERENCES ic_substrates (ic_substrate_id),
        FOREIGN KEY (ic_ecm_id)
            REFERENCES ic_ecms (ic_ecm_id),
        FOREIGN KEY (config_id)
            REFERENCES configs (config_id)
        FOREIGN KEY (rulesets_collection_id)
            REFERENCES rulesets_collections (rulesets_collection_id)
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
        variation_id INTEGER,
        rulesets_variation_id INTEGER,
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
        UNIQUE (custom_code_id,ic_cell_id,ic_substrate_id,ic_ecm_id,config_id,rulesets_collection_id,variation_id,rulesets_variation_id)
    """
    createPCVCTTable("monads", monads_schema)

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
    if "ics" in data_dir_contents && ic_name in readdir("$(data_dir)/inputs/ics", sort=false)
        ic_folders = readdir("$(data_dir)/inputs/ics/$(ic_name)", sort=false) |> filter(x->isdir("$(data_dir)/inputs/ics/$(ic_name)/$(x)"))
        if !isempty(ic_folders)
            for ic_folder in ic_folders
                if !isfile("$(data_dir)/inputs/ics/$(ic_name)/$(ic_folder)/$(icFilename(ic_name))")
                    continue
                end
                if isfile("$(data_dir)/inputs/ics/$(ic_name)/$(ic_folder)/metadata.xml")
                    metadata = parse_file("$(data_dir)/inputs/ics/$(ic_name)/$(ic_folder)/metadata.xml")
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

################## DB Interface Functions ##################

function getVariationDB(folder::String; type::Symbol = :config)
    if type == :config
        getConfigDB(folder)
    elseif type == :rulesets_collection
        getRulesetsCollectionDB(folder)
    else
        error("type must be :config or :rulesets_collection.")
    end
end

getConfigDB(config_folder::String) = "$(data_dir)/inputs/configs/$(config_folder)/variations.db" |> SQLite.DB
getConfigDB(config_id::Int) = getConfigFolder(config_id) |> getConfigDB
getConfigDB(S::AbstractSampling) = getConfigDB(S.folder_names.config_folder)

getRulesetsCollectionDB(rulesets_collection_folder::String) = "$(data_dir)/inputs/rulesets_collections/$(rulesets_collection_folder)/rulesets_variations.db" |> SQLite.DB
getRulesetsCollectionDB(M::AbstractMonad) = getRulesetsCollectionDB(M.folder_names.rulesets_collection_folder)
getRulesetsCollectionDB(rulesets_collection_id::Int) = getRulesetsCollectionFolder(rulesets_collection_id) |> getRulesetsCollectionDB

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
    ic_cell_folder = getICCellFolder(ic_cell_id)
    ic_substrate_folder = getICSubstrateFolder(ic_substrate_id)
    ic_ecm_folder = getICECMFolder(ic_ecm_id)
    rulesets_collection_folder = getRulesetsCollectionFolder(rulesets_collection_id)
    custom_code_folder = getCustomCodesFolder(custom_code_id)
    return config_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder, custom_code_folder
end

function retrieveID(table_name::String, folder_name::String; db::SQLite.DB=db)
    if folder_name == ""
        return -1
    end
    primary_key_string = "$(rstrip(table_name,'s'))_id"
    return constructSelectQuery(table_name, "WHERE folder_name='$(folder_name)'"; selection=primary_key_string) |> queryToDataFrame |> x -> x[1,primary_key_string]
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

getConfigVariationIDs(M::AbstractMonad) = [M.variation_id]
getConfigVariationIDs(sampling::Sampling) = sampling.variation_ids

getRulesetsVariationIDs(M::AbstractMonad) = [M.rulesets_variation_id]
getRulesetsVariationIDs(sampling::Sampling) = sampling.rulesets_variation_ids

getAbstractTrial(class_id::VCTClassID) = class_id.id |> getVCTClassIDType(class_id)

function getVariationsTable(query::String, db::SQLite.DB; remove_constants::Bool = false, simpleVariationNames=simpleVariationNames)
    df = queryToDataFrame(query, db=db)
    if remove_constants && size(df, 1) > 1
        col_names = names(df)
        filter!(n -> length(unique(df[!,n])) > 1, col_names)
        select!(df, col_names)
    end
    return df
end

function getConfigVariationsTable(variations_db::SQLite.DB, variation_ids::Vector{Int}; remove_constants::Bool = false)
    query = constructSelectQuery("variations", "WHERE variation_id IN ($(join(variation_ids,",")));")
    df = getVariationsTable(query, variations_db; remove_constants = remove_constants)
    rename!(simpleVariationNames, df)
    return df
end

getConfigVariationsTable(S::AbstractSampling; remove_constants::Bool=false) = getConfigVariationsTable(getConfigDB(S), getConfigVariationIDs(S); remove_constants = remove_constants)
getConfigVariationsTable(class_id::VCTClassID{<:AbstractSampling}; remove_constants::Bool = false) = getAbstractTrial(class_id) |> x -> getConfigVariationsTable(x; remove_constants = remove_constants)

function getRulesetsVariationsTable(rulesets_variations_db::SQLite.DB, rulesets_variation_ids::Vector{Int}; remove_constants::Bool = false)
    query = constructSelectQuery("rulesets_variations", "WHERE rulesets_variation_id IN ($(join(rulesets_variation_ids,",")));")
    df = getVariationsTable(query, rulesets_variations_db; remove_constants = remove_constants)
    rename!(simpleRulesetsVariationNames, df)
    return df
end

getRulesetsVariationsTable(S::AbstractSampling; remove_constants::Bool=false) = getRulesetsVariationsTable(getRulesetsCollectionDB(S), getRulesetsVariationIDs(S); remove_constants = remove_constants)
getRulesetsVariationsTable(class_id::VCTClassID{<:AbstractSampling}; remove_constants::Bool = false) = getAbstractTrial(class_id) |> x -> getRulesetsVariationsTable(x; remove_constants = remove_constants)

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

function getConfigVariationsTable(simulation_ids::Vector{Int}; remove_constants::Bool = false)
    query = constructSelectQuery("simulations", "WHERE simulation_id IN ($(join(simulation_ids,",")));", selection="config_id, variation_id")
    getVariationsTableFn = x -> getConfigVariationsTable(getConfigDB(x[1]), [x[2]]; remove_constants = false)
    return getVariationsTableFromSimulations(query, :VarID, getVariationsTableFn)
end


function getRulesetsVariationsTable(simulation_ids::Vector{Int}; remove_constants::Bool = false)
    query = constructSelectQuery("simulations", "WHERE simulation_id IN ($(join(simulation_ids,",")));", selection="rulesets_collection_id, rulesets_variation_id")
    getVariationsTableFn = x -> getRulesetsVariationsTable(getRulesetsCollectionDB(x[1]), [x[2]]; remove_constants = false)
    return getVariationsTableFromSimulations(query, :RulesVarID, getVariationsTableFn)
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

function getSimulationsTableFromQuery(query::String; remove_constants::Bool=true)
    df = queryToDataFrame(query)
    id_col_names_to_remove = names(df) # a bunch of ids that we don't want to show
    filter!(n -> !(n in ["simulation_id", "variation_id", "rulesets_variation_id"]), id_col_names_to_remove) # keep the simulation_id and variation_id columns
    addFolderColumns!(df) # add the folder columns
    select!(df, Not(id_col_names_to_remove)) # remove the id columns
    unique_tuples = [(row.config_folder, row.variation_id) for row in eachrow(df)] |> unique
    df = appendVariations(df, unique_tuples, getConfigDB, getConfigVariationsTable, :variation_id, :VarID)
    unique_tuples = [(row.rulesets_collection_folder, row.rulesets_variation_id) for row in eachrow(df)] |> unique
    df = appendVariations(df, unique_tuples, getRulesetsCollectionDB, getRulesetsVariationsTable, :rulesets_variation_id, :RulesVarID)
    rename!(df, [:simulation_id => :SimID, :variation_id => :VarID, :rulesets_variation_id => :RulesVarID])
    if remove_constants && size(df, 1) > 1
        col_names = names(df)
        filter!(n -> length(unique(df[!, n])) > 1, col_names)
        select!(df, col_names)
    end
    return df
end

function appendVariations(df::DataFrame, unique_tuples::Vector{Tuple{String, Int}}, getDB::Function, getVariationsTableFn::Function, id_name::Symbol, new_id_name::Symbol)
    var_df = DataFrame(new_id_name => Int[])
    for unique_tuple in unique_tuples
        append!(var_df, getVariationsTableFn(getDB(unique_tuple[1]), [unique_tuple[2]]; remove_constants = false), cols=:union)
    end
    return outerjoin(df, var_df, on = id_name => new_id_name)
end

function getSimulationsTable(T::AbstractTrial; remove_constants::Bool = true)
    query = constructSelectQuery("simulations", "WHERE simulation_id IN ($(join(getSimulations(T),",")));")
    return getSimulationsTableFromQuery(query; remove_constants = remove_constants)
end

function getSimulationsTable(simulation_ids::Vector{Int}; remove_constants::Bool = true)
    query = constructSelectQuery("simulations", "WHERE simulation_id IN ($(join(simulation_ids,",")));")
    return getSimulationsTableFromQuery(query; remove_constants = remove_constants)
end

function getSimulationsTable(; remove_constants::Bool = true)
    query = constructSelectQuery("simulations", "")
    return getSimulationsTableFromQuery(query; remove_constants = remove_constants)
end

function getSimulationsTable(class_id::VCTClassID; remove_constants::Bool = true)
    query = constructSelectQuery("simulations", "WHERE simulation_id IN ($(join(getSimulations(class_id),",")));")
    return getSimulationsTableFromQuery(query; remove_constants = remove_constants)
end

########### Printing Database Functions ###########

printConfigVariationsTable(args...; kwargs...) = getConfigVariationsTable(args...; kwargs...) |> println
printRulesetsVariationsTable(args...; kwargs...) = getRulesetsVariationsTable(args...; kwargs...) |> println

printSimulationsTable(args...; kwargs...) = getSimulationsTable(args...; kwargs...) |> println
