db::SQLite.DB = SQLite.DB()

function initializeDatabase(path_to_database::String)
    println(path_to_database)
    println("loading up the global db variable")
    global db = SQLite.DB(path_to_database)
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
    if !("base_configs" in data_dir_contents)
        error("No $(data_dir)/inputs/base_configs found. This is where to put the folders for config files and rules files.")
    end
    
    # initialize and populate custom_codes table
    SQLite.execute(db, "CREATE TABLE IF NOT EXISTS custom_codes (
        custom_code_id INTEGER PRIMARY KEY,
        folder_name UNIQUE,
        description TEXT
        )
    ")
        
    custom_codes_folders = readdir("$(data_dir)/inputs/custom_codes", sort=false) |> filter(x->isdir("$(data_dir)/inputs/custom_codes/$(x)"))
    if isempty(custom_codes_folders)
        error("No folders in $(data_dir)/inputs/custom_codes found. Add custom_modules, main.cpp, and Makefile to a folder here to move forward.")
    end
    for custom_codes_folder in custom_codes_folders
        DBInterface.execute(db, "INSERT OR IGNORE INTO custom_codes (folder_name) VALUES ('$(custom_codes_folder)');")
    end
    
    # initialize and populate ics table
    SQLite.execute(db, "CREATE TABLE IF NOT EXISTS ics (
        ic_id INTEGER PRIMARY KEY,
        folder_name UNIQUE,
        description TEXT
        )
    ")
        
    if "ics" in data_dir_contents
        ics_folders = readdir("$(data_dir)/inputs/ics", sort=false) |> filter(x->isdir("$(data_dir)/inputs/ics/$(x)"))
        if !isempty(ics_folders)
            for ics_folder in ics_folders
                DBInterface.execute(db, "INSERT OR IGNORE INTO ics (folder_name) VALUES ('$(ics_folder)');")
            end
        end
    end
        
    # initialize and populate base_configs table
    SQLite.execute(db, "CREATE TABLE IF NOT EXISTS base_configs (
        base_config_id INTEGER PRIMARY KEY,
        folder_name UNIQUE,
        description TEXT
        )
    ")
        
    base_config_folders = readdir("$(data_dir)/inputs/base_configs", sort=false) |> filter(x->isdir("$(data_dir)/inputs/base_configs/$(x)"))
    if isempty(base_config_folders)
        error("No folders in $(data_dir)/inputs/base_configs found. Add PhysiCell_settings.xml and rules files here.")
    end
    for base_config_folders in base_config_folders
        DBInterface.execute(db, "INSERT OR IGNORE INTO base_configs (folder_name) VALUES ('$(base_config_folders)');")
        db_variations = "$(data_dir)/inputs/base_configs/$(base_config_folders)/variations.db" |> SQLite.DB
        DBInterface.execute(db_variations, "CREATE TABLE IF NOT EXISTS variations (
            variation_id INTEGER PRIMARY KEY
        );")
        DBInterface.execute(db_variations, "INSERT OR IGNORE INTO variations (variation_id) VALUES(0);")

        db_rulesets_collections = "$(data_dir)/inputs/base_configs/$(base_config_folders)/rulesets_collections.db" |> SQLite.DB
        DBInterface.execute(db_rulesets_collections, "CREATE TABLE IF NOT EXISTS rulesets_collections (
            rulesets_collection_id INTEGER PRIMARY KEY,
            folder_name UNIQUE,
            description TEXT
        );")
        for rulesets_collection in readdir("$(data_dir)/inputs/base_configs/$(base_config_folders)/rulesets_collections", sort=false) |> filter(x->isdir("$(data_dir)/inputs/base_configs/$(base_config_folders)/rulesets_collections/$(x)"))
            DBInterface.execute(db_rulesets_collections, "INSERT OR IGNORE INTO rulesets_collections (folder_name) VALUES('$rulesets_collection');")

            # make the db with rulesets variations for the collection
            db_rulesets_variations = "$(data_dir)/inputs/base_configs/$(base_config_folders)/rulesets_collections/$(rulesets_collection)/rulesets_variations.db" |> SQLite.DB
            SQLite.execute(db_rulesets_variations, "CREATE TABLE IF NOT EXISTS rulesets_variations (
                rulesets_variation_id INTEGER PRIMARY KEY
            );")
            # createRulesetsVariationsDB(rulesets_scheme, base_config_folders)
        end
    end
            
    # initialize simulations table
    SQLite.execute(db, "CREATE TABLE IF NOT EXISTS simulations (
        simulation_id INTEGER PRIMARY KEY,
        custom_code_id INTEGER,
        ic_id INTEGER,
        base_config_id INTEGER,
        rulesets_collection_id INTEGER,
        variation_id INTEGER,
        rulesets_variation_id INTEGER,
        FOREIGN KEY (custom_code_id)
            REFERENCES custom_codes (custom_code_id),
        FOREIGN KEY (ic_id)
            REFERENCES ics (ic_id),
        FOREIGN KEY (base_config_id)
            REFERENCES base_configs (base_config_id)
        )    
    ")

    # initialize monads table
    SQLite.execute(db, "CREATE TABLE IF NOT EXISTS monads (
        monad_id INTEGER PRIMARY KEY,
        custom_code_id INTEGER,
        ic_id INTEGER,
        base_config_id INTEGER,
        rulesets_collection_id INTEGER,
        variation_id INTEGER,
        rulesets_variation_id INTEGER,
        FOREIGN KEY (custom_code_id)
            REFERENCES custom_codes (custom_code_id),
        FOREIGN KEY (ic_id)
            REFERENCES ics (ic_id),
        FOREIGN KEY (base_config_id)
            REFERENCES base_configs (base_config_id),
        UNIQUE (custom_code_id,ic_id,base_config_id,rulesets_collection_id,variation_id,rulesets_variation_id)
        )    
    ")

    # initialize samplings table
    SQLite.execute(db, "CREATE TABLE IF NOT EXISTS samplings (
        sampling_id INTEGER PRIMARY KEY,
        custom_code_id INTEGER,
        ic_id INTEGER,
        base_config_id INTEGER,
        rulesets_collection_id INTEGER,
        FOREIGN KEY (custom_code_id)
            REFERENCES custom_codes (custom_code_id),
        FOREIGN KEY (ic_id)
            REFERENCES ics (ic_id),
        FOREIGN KEY (base_config_id)
            REFERENCES base_configs (base_config_id)
        )    
    ")

    SQLite.execute(db, "CREATE TABLE IF NOT EXISTS trials (
        trial_id INTEGER PRIMARY KEY,
        datetime TEXT,
        description TEXT
        )
    ")
    return
end

# function createRulesetsVariationsDB(rulesets_scheme::String, base_config_folder::String)
#     db_rulesets_variations = "$(data_dir)/inputs/base_configs/$(base_config_folder)/rulesets_schema/$(rulesets_scheme)/rulesets_variations.db" |> SQLite.DB
#     SQLite.execute(db_rulesets_variations, "CREATE TABLE IF NOT EXISTS rulesets_variations (
#         rulesets_variations INTEGER PRIMARY KEY
#     );")

#     scheme_xml_path = "$(data_dir)/inputs/base_configs/$(base_config_folder)/rulesets_schema/$(rulesets_scheme)/scheme.xml"
#     if !isfile(scheme_xml_path)
#         scheme_xml = XMLDocument()
#         return
#     end
#     scheme_xml = parse_file(scheme_xml_path)
#     hypothesis_rulesets = root(scheme_xml)
#     for hypothesis_ruleset in child_elements(hypothesis_rulesets)
#         prepareHypothesisRuleset(hypothesis_ruleset, db_rulesets_variations)
#     end
#     return
# end

# function prepareHypothesisRuleset(hypothesis_ruleset::XMLElement, db_rulesets_variations::SQLite.DB)
#     cell_definition = find_element(hypothesis_ruleset, "cell_definition")
#     for behavior in child_elements(hypothesis_ruleset)
#         prepareBehavior(behavior, cell_definition, db_rulesets_variations)
#     end
#     return
# end

# function prepareBehavior(behavior::XMLElement, cell_definition::XMLElement, db_rulesets_variations::SQLite.DB)
#     behavior_name = content(behavior["name"])
#     decreasing_signals = find_element(behavior, "decreasing_signals")
#     if !isnothing(decreasing_signals)
#         prepareSignals(behavior_name, decreasing_signals, cell_definition, db_rulesets_variations, "decreasing_signals")
#     end
#     increasing_signals = find_element(behavior, "increasing_signals")
#     if !isnothing(increasing_signals)
#         prepareSignals(behavior_name, increasing_signals, cell_definition, db_rulesets_variations, "increasing_signals")
#     end
#     return
# end

# function prepareSignals(behavior_name::String, signals::XMLElement, cell_definition::XMLElement, db_rulesets_variations::SQLite.DB, signals_table::String)
#     behavior_base_column_name = "hypothesis_ruleset:name:$(cell_definition)/behavior:name:$(behavior_name)/$(signals_table)"
#     data_types = ["REAL", "REAL", "INTEGER"]
#     for signal in child_elements(signals)
#         signal_name = content(signal["name"])
#         column_names = "$(behavior_base_column_name)/signal:name:$(signal_name)" .* ["half_max", "hill_power", "applies_to_dead"]
#         for (column_name, data_type) in zip(column_names, data_types)
#             SQLite.execute(db_rulesets_variations, "ALTER TABLE $(signals_table) ADD COLUMN IF NOT EXISTS '$(column_name)' $(data_type);")
#         end
#     end
#     max_response_column_name = "$(behavior_base_column_name)/max_response"
#     SQLite.execute(db_rulesets_variations, "ALTER TABLE $(signals_table) ADD COLUMN IF NOT EXISTS '$(max_response_column_name)' REAL;")
#     return
# end

function selectRow(table_name::String, condition_stmt::String; db::SQLite.DB=db)
    s = "SELECT * FROM $(table_name) " * condition_stmt * ";"
    df = DBInterface.execute(db, s) |> DataFrame
    @assert size(df,1)==1 "Did not find exactly one row matching the query:\n\tDatabase file: $(db)\n\tQuery: $(s)\nResult: $(df)"
    return df
end

function selectRow(column_names::Vector{String}, table_name::String, condition_stmt::String; db::SQLite.DB=db)
    df = selectRow(table_name, condition_stmt; db=db)
    return [df[1,column_name] for column_name in column_names]
end

function selectRow(column_name::String, table_name::String, condition_stmt::String; db::SQLite.DB=db)
    df = selectRow(table_name, condition_stmt; db=db)
    return df[1,column_name]
end

function getFolder(table_name::String, id_name::String, id::Int; db::SQLite.DB=db)
    return DBInterface.execute(db, "SELECT folder_name FROM $(table_name) WHERE $(id_name)=$(id)") |> DataFrame |> x -> x.folder_name[1]
end

getOptionalFolder(table_name::String, id_name::String, id::Int; db::SQLite.DB=db) = id == -1 ? "" : getFolder(table_name, id_name, id; db=db)

getBaseConfigFolder(base_config_id::Int) = getFolder("base_configs", "base_config_id", base_config_id)
getICFolder(ic_id::Int) = getOptionalFolder("ics", "ic_id", ic_id)
getRulesetsCollectionFolder(base_config_folder::String, rulesets_collection_id::Int) = getOptionalFolder("rulesets_collections", "rulesets_collection_id", rulesets_collection_id; db=getRulesetsCollectionsDB(base_config_folder))
getRulesetsCollectionFolder(base_config_id::Int, rulesets_collection_id::Int) = getRulesetsCollectionFolder(getBaseConfigFolder(base_config_id), rulesets_collection_id)
getCustomCodesFolder(custom_code_id::Int) = getFolder("custom_codes", "custom_code_id", custom_code_id)

function retrievePathInfo(base_config_id::Int, rulesets_collection_id::Int, ic_id::Int, custom_code_id::Int)
    base_config_folder = getBaseConfigFolder(base_config_id)
    ic_folder = getICFolder(ic_id)
    rulesets_collection_folder = getRulesetsCollectionFolder(base_config_folder, rulesets_collection_id)
    custom_code_folder = getCustomCodesFolder(custom_code_id)
    return base_config_folder, rulesets_collection_folder, ic_folder, custom_code_folder
end

function retrieveID(table_name::String, folder_name::String; db::SQLite.DB=db)
    primary_key_string = "$(rstrip(table_name,'s'))_id"
    return DBInterface.execute(db, "SELECT $(primary_key_string) FROM $(table_name) WHERE folder_name='$(folder_name)'") |> DataFrame |> x -> x[1,primary_key_string]
end