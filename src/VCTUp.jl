function upgradePCVCT(from_version::VersionNumber, to_version::VersionNumber, auto_upgrade::Bool)
    println("Upgrading pcvct from version $(from_version) to $(to_version)...")
    milestone_versions = [v"0.0.1", v"0.0.3", v"0.0.10", v"0.0.11", v"0.0.13", v"0.0.15"]
    next_milestone_inds = findall(x -> from_version < x, milestone_versions) # this could be simplified to take advantage of this list being sorted, but who cares? It's already so fast
    next_milestones = milestone_versions[next_milestone_inds]
    success = true
    for next_milestone in next_milestones
        up_fn_symbol = Meta.parse("upgradeToV$(replace(string(next_milestone), "." => "_"))")
        if !isdefined(pcvct, up_fn_symbol)
            throw(ArgumentError("Upgrade from version $(from_version) to $(next_milestone) not supported."))
        end
        from_version = eval(up_fn_symbol)(auto_upgrade)
        if from_version == false
            success = false
            break
        else
            DBInterface.execute(db, "UPDATE pcvct_version SET version='$(next_milestone)';")
        end
    end
    if success && to_version > milestone_versions[end]
        println("\t- Upgrading to version $(to_version)...")
        DBInterface.execute(db, "UPDATE pcvct_version SET version='$(to_version)';")
    end
    return success
end

function populateTableOnFeatureSubset(db::SQLite.DB, source_table::String, target_table::String; column_mapping::Dict{String, String}=Dict{String,String}())
    source_columns = queryToDataFrame("PRAGMA table_info($(source_table));") |> x -> x[!, :name]
    target_columns = [c in keys(column_mapping) ? column_mapping[c] : c for c in source_columns]
    insert_into_cols = "(" * join(target_columns, ",") * ")"
    select_cols = join(source_columns, ",")
    query = "INSERT INTO $(target_table) $(insert_into_cols) SELECT $(select_cols) FROM $(source_table);"
    DBInterface.execute(db, query)
end

function upgradeToV0_0_1(::Bool)
    println("\t- Upgrading to version 0.0.1...")
    data_dir_contents = readdir(joinpath(data_dir, "inputs"); sort=false)
    if "rulesets_collections" in data_dir_contents
        rulesets_collections_folders = readdir(joinpath(data_dir, "inputs", "rulesets_collections"); sort=false) |> filter(x -> isdir(joinpath(data_dir, "inputs", "rulesets_collections", x)))
        for rulesets_collection_folder in rulesets_collections_folders
            path_to_rulesets_collections_folder = joinpath(data_dir, "inputs", "rulesets_collections", rulesets_collection_folder)
            path_to_rulesets_variations_db = joinpath(path_to_rulesets_collections_folder, "rulesets_variations.db")
            if !isfile(joinpath(path_to_rulesets_variations_db))
                continue
            end
            db_rulesets_variations = SQLite.DB(path_to_rulesets_variations_db)
            df = DBInterface.execute(db_rulesets_variations, "INSERT OR IGNORE INTO rulesets_variations (rulesets_collection_variation_id) VALUES(0) RETURNING rulesets_collection_variation_id;") |> DataFrame
            if isempty(df)
                continue
            end
            column_names = queryToDataFrame("PRAGMA table_info(rulesets_variations);"; db=db_rulesets_variations) |> x -> x[!, :name]
            filter!(x -> x != "rulesets_collection_variation_id", column_names)
            path_to_xml = joinpath(path_to_rulesets_collections_folder, "base_rulesets.xml")
            if !isfile(path_to_xml)
                writeRules(path_to_xml, joinpath(path_to_rulesets_collections_folder, "base_rulesets.csv"))
            end
            xml_doc = openXML(path_to_xml)
            for column_name in column_names
                xml_path = columnNameToXMLPath(column_name)
                base_value = getField(xml_doc, xml_path)
                query = "UPDATE rulesets_variations SET '$(column_name)'=$(base_value) WHERE rulesets_collection_variation_id=0;"
                DBInterface.execute(db_rulesets_variations, query)
            end
            closeXML(xml_doc)
        end
    end
    return true
end

function upgradeToV0_0_3(auto_upgrade::Bool)
    warning_msg = """
    \t- Upgrading to version 0.0.3...
    \nWARNING: Upgrading to version 0.0.3 will change the database schema.
    See info at https://github.com/drbergman/pcvct?tab=readme-ov-file#to-v003

    ------IF ANOTHER INSTANCE OF PCVCT IS USING THIS DATABASE, PLEASE CLOSE IT BEFORE PROCEEDING.------

    Continue upgrading to version 0.0.3? (y/n):
    """
    println(warning_msg)
    response = auto_upgrade ? "y" : readline()
    if response != "y"
        println("Upgrade to version 0.0.3 aborted.")
        return false
    end
    println("\t- Upgrading to version 0.0.3...")
    # first get vct.db right changing simulations and monads tables
    if DBInterface.execute(db, "SELECT 1 FROM pragma_table_info('simulations') WHERE name='config_variation_id';") |> DataFrame |> isempty
        DBInterface.execute(db, "ALTER TABLE simulations RENAME COLUMN variation_id TO config_variation_id;")
    end
    if DBInterface.execute(db, "SELECT 1 FROM pragma_table_info('monads') WHERE name='config_variation_id';") |> DataFrame |> isempty
        DBInterface.execute(db, "ALTER TABLE monads RENAME COLUMN variation_id TO config_variation_id;")
    end
    if DBInterface.execute(db, "SELECT 1 FROM pragma_table_info('simulations') WHERE name='ic_cell_variation_id';") |> DataFrame |> isempty
        DBInterface.execute(db, "ALTER TABLE simulations ADD COLUMN ic_cell_variation_id INTEGER;")
        DBInterface.execute(db, "UPDATE simulations SET ic_cell_variation_id=CASE WHEN ic_cell_id=-1 THEN -1 ELSE 0 END;")
    end
    if DBInterface.execute(db, "SELECT 1 FROM pragma_table_info('monads') WHERE name='ic_cell_variation_id';") |> DataFrame |> isempty
        DBInterface.execute(db, "ALTER TABLE monads ADD COLUMN ic_cell_variation_id INTEGER;")
    end
    DBInterface.execute(db, "CREATE TABLE monads_temp AS SELECT * FROM monads;")
    DBInterface.execute(db, "UPDATE monads_temp SET ic_cell_variation_id=CASE WHEN ic_cell_id=-1 THEN -1 ELSE 0 END;")
    DBInterface.execute(db, "DROP TABLE monads;")
    createPCVCTTable("monads", monadsSchema())
    # drop the previous unique constraint on monads
    # insert from monads_temp all values except ic_cell_variation_id (set that to -1 if ic_cell_id is -1 and to 0 if ic_cell_id is not -1)
    populateTableOnFeatureSubset(db, "monads_temp", "monads")
    DBInterface.execute(db, "DROP TABLE monads_temp;")

    # now get the config_variations.db's right
    config_folders = queryToDataFrame(constructSelectQuery("configs"; selection="folder_name")) |> x -> x.folder_name
    for config_folder in config_folders
        path_to_config_folder = joinpath(data_dir, "inputs", "configs", config_folder)
        if !isfile(joinpath(path_to_config_folder, "variations.db"))
            continue
        end
        # rename all "variation" to "config_variation" in filenames and in databases
        old_db_file = joinpath(path_to_config_folder, "variations.db")
        db_file = joinpath(path_to_config_folder, "config_variations.db")
        if isfile(old_db_file)
            mv(old_db_file, db_file)
        end
        db_config_variations = db_file |> SQLite.DB
        # check if variations is a table name in the database
        if DBInterface.execute(db_config_variations, "SELECT name FROM sqlite_master WHERE type='table' AND name='variations';") |> DataFrame |> x -> (length(x.name)==1)
            DBInterface.execute(db_config_variations, "ALTER TABLE variations RENAME TO config_variations;")
        end
        if DBInterface.execute(db_config_variations, "SELECT 1 FROM pragma_table_info('config_variations') WHERE name='config_variation_id';") |> DataFrame |> isempty
            DBInterface.execute(db_config_variations, "ALTER TABLE config_variations RENAME COLUMN variation_id TO config_variation_id;")
        end
        index_df = DBInterface.execute(db_config_variations, "SELECT type,name,tbl_name,sql FROM sqlite_master WHERE type = 'index';") |> DataFrame
        variations_index = index_df[!, :name] .== "variations_index"
        if any(variations_index)
            variations_sql = index_df[variations_index, :sql][1]
            cols = split(variations_sql, "(")[2]
            cols = split(cols, ")")[1]
            cols = split(cols, ",") .|> string .|> x -> strip(x, '"')
            SQLite.createindex!(db_config_variations, "config_variations", "config_variations_index", cols; unique=true, ifnotexists=false)
            SQLite.dropindex!(db_config_variations, "variations_index")
        end
        old_folder = joinpath(path_to_config_folder, "variations")
        new_folder = joinpath(path_to_config_folder, "config_variations")
        if isdir(old_folder)
            mv(old_folder, new_folder)
            for file in readdir(new_folder)
                mv(joinpath(new_folder, file), joinpath(new_folder, "config_$(file)"))
            end
        end
    end
    return true
end

function upgradeToV0_0_10(auto_upgrade::Bool)
    warning_msg = """
    \t- Upgrading to version 0.0.10...
    \nWARNING: Upgrading to version 0.0.10 will change the database schema.
    See info at https://github.com/drbergman/pcvct?tab=readme-ov-file#to-v0010

    ------IF ANOTHER INSTANCE OF PCVCT IS USING THIS DATABASE, PLEASE CLOSE IT BEFORE PROCEEDING.------

    Continue upgrading to version 0.0.10? (y/n):
    """
    println(warning_msg)
    response = auto_upgrade ? "y" : readline()
    if response != "y"
        println("Upgrade to version 0.0.10 aborted.")
        return false
    end
    println("\t- Upgrading to version 0.0.10...")

    createPCVCTTable("physicell_versions", physicellVersionsSchema())
    global current_physicell_version_id = physicellVersionID()

    println("\t\tPhysiCell version: $(physicellInfo())")
    println("\n\t\tAssuming all output has been generated with this version...")

    if DBInterface.execute(db, "SELECT 1 FROM pragma_table_info('simulations') WHERE name='physicell_version_id';") |> DataFrame |> isempty
        DBInterface.execute(db, "ALTER TABLE simulations ADD COLUMN physicell_version_id INTEGER;")
        DBInterface.execute(db, "UPDATE simulations SET physicell_version_id=$(physicellVersionDBEntry());")
    end

    if DBInterface.execute(db, "SELECT 1 FROM pragma_table_info('monads') WHERE name='physicell_version_id';") |> DataFrame |> isempty
        DBInterface.execute(db, "ALTER TABLE monads ADD COLUMN physicell_version_id INTEGER;")
        DBInterface.execute(db, "CREATE TABLE monads_temp AS SELECT * FROM monads;")
        DBInterface.execute(db, "UPDATE monads_temp SET physicell_version_id=$(physicellVersionDBEntry());")
        DBInterface.execute(db, "DROP TABLE monads;")
        createPCVCTTable("monads", monadsSchema())
        populateTableOnFeatureSubset(db, "monads_temp", "monads")
        DBInterface.execute(db, "DROP TABLE monads_temp;")
    end

    if DBInterface.execute(db, "SELECT 1 FROM pragma_table_info('samplings') WHERE name='physicell_version_id';") |> DataFrame |> isempty
        DBInterface.execute(db, "ALTER TABLE samplings ADD COLUMN physicell_version_id INTEGER;")
        DBInterface.execute(db, "UPDATE samplings SET physicell_version_id=$(physicellVersionDBEntry());")
    end
    return true
end

function upgradeToV0_0_11(::Bool)
    println("\t- Upgrading to version 0.0.11...")
    query = constructSelectQuery("samplings")
    samplings_df = queryToDataFrame(query)
    for row in eachrow(samplings_df)
        if !ismissing(row.physicell_version_id)
            continue
        end
        monads = getMonadIDs(Sampling(row.sampling_id))
        query = constructSelectQuery("monads", "WHERE monad_id IN ($(join(monads, ",")))"; selection="physicell_version_id")
        monads_df = queryToDataFrame(query)
        monad_physicell_versions = monads_df.physicell_version_id |> unique
        if length(monad_physicell_versions) == 1
            DBInterface.execute(db, "UPDATE samplings SET physicell_version_id=$(monad_physicell_versions[1]) WHERE sampling_id=$(row.sampling_id);")
        else
            println("WARNING: Multiple PhysiCell versions found for monads in sampling $(row.sampling_id). Not setting the sampling PhysiCell version.")
        end
    end
end

function upgradeToV0_0_13(::Bool)
    println("\t- Upgrading to version 0.0.13...")
    if DBInterface.execute(db, "SELECT 1 FROM pragma_table_info('simulations') WHERE name='rulesets_variation_id';") |> DataFrame |> isempty
        DBInterface.execute(db, "ALTER TABLE simulations RENAME COLUMN rulesets_variation_id TO rulesets_collection_variation_id;")
    end
    if DBInterface.execute(db, "SELECT 1 FROM pragma_table_info('monads') WHERE name='rulesets_variation_id';") |> DataFrame |> isempty
        DBInterface.execute(db, "ALTER TABLE monads RENAME COLUMN rulesets_variation_id TO rulesets_collection_variation_id;")
    end
    rulesets_collection_folders = queryToDataFrame(constructSelectQuery("rulesets_collections"; selection="folder_name")) |> x -> x.folder_name
    for rulesets_collection_folder in rulesets_collection_folders
        path_to_rulesets_collection_folder = joinpath(data_dir, "inputs", "rulesets_collections", rulesets_collection_folder)
        path_to_new_db = joinpath(path_to_rulesets_collection_folder, "rulesets_collection_variations.db")
        if isfile(path_to_new_db)
            continue
        end
        path_to_old_db = joinpath(path_to_rulesets_collection_folder, "rulesets_variations.db")
        if !isfile(path_to_old_db)
            error("Could not find a rulesets collection variation database file in $(path_to_rulesets_collection_folder).")
        end
        mv(path_to_old_db, path_to_new_db)
        db_rulesets_collection_variations = SQLite.DB(path_to_new_db)
        if DBInterface.execute(db_rulesets_collection_variations, "SELECT name FROM sqlite_master WHERE type='table' AND name='rulesets_variations';") |> DataFrame |> x -> (length(x.name)==1)
            DBInterface.execute(db_rulesets_collection_variations, "ALTER TABLE rulesets_variations RENAME TO rulesets_collection_variations;")
        end
        if !(DBInterface.execute(db_rulesets_collection_variations, "SELECT 1 FROM pragma_table_info('rulesets_collection_variations') WHERE name='rulesets_variation_id';") |> DataFrame |> isempty)
            DBInterface.execute(db_rulesets_collection_variations, "ALTER TABLE rulesets_collection_variations RENAME COLUMN rulesets_variation_id TO rulesets_collection_variation_id;")
        end
    end
end

function upgradeToV0_0_15(::Bool)
    println("\t- Upgrading to version 0.0.15...")
    if DBInterface.execute(db, "SELECT 1 FROM pragma_table_info('simulations') WHERE name='ic_dc_id';") |> DataFrame |> isempty
        DBInterface.execute(db, "ALTER TABLE simulations ADD COLUMN ic_dc_id INTEGER;")
        DBInterface.execute(db, "UPDATE simulations SET ic_dc_id=-1;")
    end
    if DBInterface.execute(db, "SELECT 1 FROM pragma_table_info('monads') WHERE name='ic_dc_id';") |> DataFrame |> isempty
        DBInterface.execute(db, "ALTER TABLE monads ADD COLUMN ic_dc_id INTEGER;")
        DBInterface.execute(db, "CREATE TABLE monads_temp AS SELECT * FROM monads;")
        DBInterface.execute(db, "UPDATE monads_temp SET ic_dc_id=-1;")
        DBInterface.execute(db, "DROP TABLE monads;")
        createPCVCTTable("monads", monadsSchema())
        populateTableOnFeatureSubset(db, "monads_temp", "monads")
        DBInterface.execute(db, "DROP TABLE monads_temp;")
    end
    return true
end