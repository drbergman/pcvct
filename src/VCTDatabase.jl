db = SQLite.DB()

current_ic_id = -1

function initializeDatabase(path_to_database::String)
    println(path_to_database)
    global db = SQLite.DB(path_to_database)
    return createSchema()
end

function initializeDatabase()
    global db = SQLite.DB()
    return createSchema()
end

function createSchema()

    data_dir_contents = readdir(data_dir, sort=false)
    if !("custom_codes" in data_dir_contents)
        error("No $(data_dir)/custom_codes found. This is where to put the folders for custom_modules, main.cpp, and Makefile.")
    end
    if !("base_configs" in data_dir_contents)
        error("No $(data_dir)/base_configs found. This is where to put the folders for config files and rules files.")
    end
    
    SQLite.execute(db, "CREATE TABLE IF NOT EXISTS custom_codes (
        custom_code_id INTEGER PRIMARY KEY,
        folder_name UNIQUE,
        description TEXT
        )
    ")
        
    custom_codes_folders = readdir("$(data_dir)/custom_codes", sort=false) |> filter(x->isdir("$(data_dir)/custom_codes/$(x)"))
    if isempty(custom_codes_folders)
        error("No folders in $(data_dir)/custom_codes found. Add custom_modules, main.cpp, and Makefile to a folder here to move forward.")
    end
    for custom_codes_folder in custom_codes_folders
        DBInterface.execute(db, "INSERT OR IGNORE INTO custom_codes (folder_name) VALUES ('$(custom_codes_folder)');")
    end
    
    SQLite.execute(db, "CREATE TABLE IF NOT EXISTS ics (
        ic_id INTEGER PRIMARY KEY,
        folder_name UNIQUE,
        description TEXT
        )
    ")
        
    if "ics" in data_dir_contents
        ics_folders = readdir("ics", sort=false) |> filter(x->isdir("ics/$(x)"))
        if !isempty(ics_folders)
            for ics_folder in ics_folders
                DBInterface.execute(db, "INSERT OR IGNORE INTO ics (folder_name) VALUES ('$(ics_folder)');")
            end
        end
    end
        
    SQLite.execute(db, "CREATE TABLE IF NOT EXISTS base_configs (
        base_config_id INTEGER PRIMARY KEY,
        folder_name UNIQUE,
        description TEXT
        )
    ")
        
    base_configs_folders = readdir("$(data_dir)/base_configs", sort=false) |> filter(x->isdir("$(data_dir)/base_configs/$(x)"))
    if isempty(base_configs_folders)
        error("No folders in $(data_dir)/base_configs found. Add PhysiCell_settings.xml and rules files here.")
    end
    for base_configs_folder in base_configs_folders
        DBInterface.execute(db, "INSERT OR IGNORE INTO base_configs (folder_name) VALUES ('$(base_configs_folder)');")
        db_config = "$(data_dir)/base_configs/$(base_configs_folder)/variations.db" |> SQLite.DB
        DBInterface.execute(db_config, "CREATE TABLE IF NOT EXISTS variations (
            variation_id INTEGER PRIMARY KEY
        );")
        DBInterface.execute(db_config, "INSERT OR IGNORE INTO variations (variation_id) VALUES(0);")
    end
            
    SQLite.execute(db, "CREATE TABLE IF NOT EXISTS simulations (
        simulation_id INTEGER PRIMARY KEY,
        custom_code_id INTEGER,
        ic_id INTEGER,
        base_config_id INTEGER,
        variation_id INTEGER,
        FOREIGN KEY (custom_code_id)
            REFERENCES custom_codes (custom_code_id),
        FOREIGN KEY (ic_id)
            REFERENCES ics (ic_id),
        FOREIGN KEY (base_config_id)
            REFERENCES base_configs (base_config_id)
        )    
    ")

    SQLite.execute(db, "CREATE TABLE IF NOT EXISTS monads (
        monad_id INTEGER PRIMARY KEY,
        custom_code_id INTEGER,
        ic_id INTEGER,
        base_config_id INTEGER,
        variation_id INTEGER,
        FOREIGN KEY (custom_code_id)
            REFERENCES custom_codes (custom_code_id),
        FOREIGN KEY (ic_id)
            REFERENCES ics (ic_id),
        FOREIGN KEY (base_config_id)
            REFERENCES base_configs (base_config_id),
        UNIQUE (custom_code_id,ic_id,base_config_id,variation_id)
        )    
    ")

    SQLite.execute(db, "CREATE TABLE IF NOT EXISTS samplings (
        sampling_id INTEGER PRIMARY KEY,
        custom_code_id INTEGER,
        ic_id INTEGER,
        base_config_id INTEGER,
        FOREIGN KEY (custom_code_id)
            REFERENCES custom_codes (custom_code_id),
        FOREIGN KEY (ic_id)
            REFERENCES ics (ic_id),
        FOREIGN KEY (base_config_id)
            REFERENCES base_configs (base_config_id)
        )    
    ")

    # SQLite.execute(db, "CREATE TABLE IF NOT EXISTS trials (
    #     trial_id INTEGER PRIMARY KEY,
    #     datetime TEXT,
    #     description TEXT
    #     )
    # ")
    return
end

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

function retrievePathInfo(base_config_id::Int, ic_id::Int, custom_code_id::Int)
    base_config_folder = DBInterface.execute(db, "SELECT folder_name FROM base_configs WHERE base_config_id=$(base_config_id)") |> DataFrame |> x -> x.folder_name[1]
    ic_folder = ic_id==-1 ? "" : DBInterface.execute(db, "SELECT folder_name FROM ics WHERE ic_id=$(ic_id)") |> DataFrame |> x -> x.folder_name[1]
    custom_code_folder = DBInterface.execute(db, "SELECT folder_name FROM custom_codes WHERE custom_code_id=$(custom_code_id)") |> DataFrame |> x -> x.folder_name[1]
    return base_config_folder, ic_folder, custom_code_folder
end
