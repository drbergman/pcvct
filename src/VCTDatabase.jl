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
    
    # initialize and populate ic_cells table
    ic_cells_schema = """
        ic_cell_id INTEGER PRIMARY KEY,
        folder_name UNIQUE,
        description TEXT
    """
    createPCVCTTable("ic_cells", ic_cells_schema)
        
    if "ics" in data_dir_contents && "cells" in readdir("$(data_dir)/inputs/ics", sort=false)
        ic_cell_folders = readdir("$(data_dir)/inputs/ics/cells", sort=false) |> filter(x->isdir("$(data_dir)/inputs/ics/cells/$(x)"))
        if !isempty(ic_cell_folders)
            for ic_cell_folder in ic_cell_folders
                if !isfile("$(data_dir)/inputs/ics/cells/$(ic_cell_folder)/cells.csv")
                    continue
                end
                if isfile("$(data_dir)/inputs/ics/cells/$(ic_cell_folder)/metadata.xml")
                    metadata = parse_file("$(data_dir)/inputs/ics/cells/$(ic_cell_folder)/metadata.xml")
                    description = content(find_element(metadata, "description"))
                else
                    description = ""
                end
                DBInterface.execute(db, "INSERT OR IGNORE INTO ic_cells (folder_name, description) VALUES ('$(ic_cell_folder)', '$description');")
            end
        end
    end
        
    # initialize and populate base_configs table
    base_configs_schema = """
        base_config_id INTEGER PRIMARY KEY,
        folder_name UNIQUE,
        description TEXT
    """
    createPCVCTTable("base_configs", base_configs_schema)
        
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
            rulesets_variations_schema = """
                rulesets_variation_id INTEGER PRIMARY KEY
            """
            createPCVCTTable("rulesets_variations", rulesets_variations_schema; db=db_rulesets_variations)
        end
    end
            
    # initialize simulations table
    simulations_schema = """
        simulation_id INTEGER PRIMARY KEY,
        custom_code_id INTEGER,
        ic_cell_id INTEGER,
        base_config_id INTEGER,
        rulesets_collection_id INTEGER,
        variation_id INTEGER,
        rulesets_variation_id INTEGER,
        FOREIGN KEY (custom_code_id)
            REFERENCES custom_codes (custom_code_id),
        FOREIGN KEY (ic_cell_id)
            REFERENCES ic_cells (ic_cell_id),
        FOREIGN KEY (base_config_id)
            REFERENCES base_configs (base_config_id)
    """
    createPCVCTTable("simulations", simulations_schema)

    # initialize monads table
    monads_schema = """
        monad_id INTEGER PRIMARY KEY,
        custom_code_id INTEGER,
        ic_cell_id INTEGER,
        base_config_id INTEGER,
        rulesets_collection_id INTEGER,
        variation_id INTEGER,
        rulesets_variation_id INTEGER,
        FOREIGN KEY (custom_code_id)
            REFERENCES custom_codes (custom_code_id),
        FOREIGN KEY (ic_cell_id)
            REFERENCES ic_cells (ic_cell_id),
        FOREIGN KEY (base_config_id)
            REFERENCES base_configs (base_config_id),
        UNIQUE (custom_code_id,ic_cell_id,base_config_id,rulesets_collection_id,variation_id,rulesets_variation_id)
    """
    createPCVCTTable("monads", monads_schema)

    # initialize samplings table
    samplings_schema = """
        sampling_id INTEGER PRIMARY KEY,
        custom_code_id INTEGER,
        ic_cell_id INTEGER,
        base_config_id INTEGER,
        rulesets_collection_id INTEGER,
        FOREIGN KEY (custom_code_id)
            REFERENCES custom_codes (custom_code_id),
        FOREIGN KEY (ic_cell_id)
            REFERENCES ic_cells (ic_cell_id),
        FOREIGN KEY (base_config_id)
            REFERENCES base_configs (base_config_id)
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
getICCellFolder(ic_cell_id::Int) = getOptionalFolder("ic_cells", "ic_cell_id", ic_cell_id)
getICSubstrateFolder(ic_substrate_id::Int) = getOptionalFolder("ic_substrates", "ic_substrate_id", ic_substrate_id)
getICECMFolder(ic_ecm_id::Int) = getOptionalFolder("ic_ecms", "ic_ecm_id", ic_ecm_id)
getRulesetsCollectionFolder(base_config_folder::String, rulesets_collection_id::Int) = getOptionalFolder("rulesets_collections", "rulesets_collection_id", rulesets_collection_id; db=getRulesetsCollectionsDB(base_config_folder))
getRulesetsCollectionFolder(base_config_id::Int, rulesets_collection_id::Int) = getRulesetsCollectionFolder(getBaseConfigFolder(base_config_id), rulesets_collection_id)
getCustomCodesFolder(custom_code_id::Int) = getFolder("custom_codes", "custom_code_id", custom_code_id)

function retrievePathInfo(base_config_id::Int, rulesets_collection_id::Int, ic_cell_id::Int, ic_substrate_id::Int, ic_ecm_id::Int, custom_code_id::Int)
    base_config_folder = getBaseConfigFolder(base_config_id)
    ic_cell_folder = getICCellFolder(ic_cell_id)
    ic_substrate_folder = getICSubstrateFolder(ic_substrate_id)
    ic_ecm_folder = getICECMFolder(ic_ecm_id)
    rulesets_collection_folder = getRulesetsCollectionFolder(base_config_folder, rulesets_collection_id)
    custom_code_folder = getCustomCodesFolder(custom_code_id)
    return base_config_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder, custom_code_folder
end

function retrieveID(table_name::String, folder_name::String; db::SQLite.DB=db)
    primary_key_string = "$(rstrip(table_name,'s'))_id"
    return DBInterface.execute(db, "SELECT $(primary_key_string) FROM $(table_name) WHERE folder_name='$(folder_name)'") |> DataFrame |> x -> x[1,primary_key_string]
end

function retrieveID(folder_names::AbstractSamplingFolders)
    base_config_id = retrieveID("base_configs", folder_names.base_config_folder)
    rulesets_collection_id = retrieveID("rulesets_collections", folder_names.rulesets_collection_folder, db=getRulesetsCollectionsDB(folder_names.base_config_folder))
    ic_cell_id = retrieveID("ic_cells", folder_names.ic_cell_folder)
    ic_substrate_id = retrieveID("ic_substrates", folder_names.ic_substrate_folder)
    ic_ecm_id = retrieveID("ic_ecms", folder_names.ic_ecm_folder)
    custom_code_id = retrieveID("custom_codes", folder_names.custom_code_folder)
    return base_config_id, rulesets_collection_id, ic_cell_id, ic_substrate_id, ic_ecm_id, custom_code_id
end