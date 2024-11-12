using Pkg

function pcvctVersion()
    proj = Pkg.project()
    version = if proj.name == "pcvct"
        proj.version
    else
        deps = Pkg.dependencies()
        deps[proj.dependencies["pcvct"]].version
    end
    return version
end

function pcvctDBVersion(is_new_db::Bool)
    # check if versions table exists
    table_name = "pcvct_version"
    versions_exists = DBInterface.execute(db, "SELECT name FROM sqlite_master WHERE type='table' AND name='$(table_name)';") |> DataFrame |> x -> (length(x.name)==1)
    if !versions_exists
        createPCVCTVersionTable(is_new_db)
    end
    return queryToDataFrame("SELECT * FROM $(table_name);") |> x -> x.version[1] |> VersionNumber
end

function createPCVCTVersionTable(is_new_db::Bool)
    table_name = "pcvct_version"
    DBInterface.execute(db, "CREATE TABLE IF NOT EXISTS $(table_name) (version TEXT PRIMARY KEY);")
    version = is_new_db ? pcvctVersion() : v"0.0.0"
    DBInterface.execute(db, "INSERT INTO $(table_name) (version) VALUES ('$version');")
end

function resolvePCVCTVersion(is_new_db::Bool, auto_upgrade::Bool)
    pcvct_version = pcvctVersion()
    pcvct_db_version = pcvctDBVersion(is_new_db)

    if pcvct_version < pcvct_db_version
        msg = """
        The pcvct version is $(pcvct_version) but the database version is $(pcvct_db_version).\
        Upgrade your pcvct version to $(pcvct_db_version) or higher:
            pkg> registry add https://github.com/drbergman/PCVCTRegistry
            pkg> registry up PCVCTRegistry
        """
        println(msg)
        success = false
        return success
    end

    if pcvct_version == pcvct_db_version
        success = true
        return success
    end

    success = upgradePCVCT(pcvct_db_version, pcvct_version, auto_upgrade)
    return success
end

function upgradePCVCT(from_version::VersionNumber, to_version::VersionNumber, auto_upgrade::Bool)
    println("Upgrading pcvct from version $(from_version) to $(to_version)...")
    milestone_versions = [v"0.0.1", v"0.0.3"]
    next_milestones = findall(x -> from_version < x, milestone_versions) # this could be simplified to take advantage of this list being sorted, but who cares? It's already so fast
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
            df = DBInterface.execute(db_rulesets_variations, "INSERT OR IGNORE INTO rulesets_variations (rulesets_variation_id) VALUES(0) RETURNING rulesets_variation_id;") |> DataFrame
            if isempty(df)
                continue
            end
            column_names = queryToDataFrame("PRAGMA table_info(rulesets_variations);"; db=db_rulesets_variations) |> x -> x[!, :name]
            filter!(x -> x != "rulesets_variation_id", column_names)
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
    DBInterface.execute(db, "DROP TABLE monads;")
    createPCVCTTable("monads", monadsSchema())
    # drop the previous unique constraint on monads
    # insert from monads_temp all values except ic_cell_variation_id (set that to -1 if ic_cell_id is -1 and to 0 if ic_cell_id is not -1)
    DBInterface.execute(db, "INSERT INTO monads SELECT monad_id, custom_code_id, ic_cell_id, ic_substrate_id, ic_ecm_id, config_id, rulesets_collection_id, config_variation_id, rulesets_variation_id, CASE WHEN ic_cell_id=-1 THEN -1 ELSE 0 END FROM monads_temp;")
    DBInterface.execute(db, "DROP TABLE monads_temp;")

    # now get the config_variations.db's right
    config_folders = queryToDataFrame(constructSelectQuery("configs", "", selection="folder_name")) |> x -> x.folder_name
    for config_folder in config_folders
        if !isfile(joinpath(data_dir, "inputs", "configs", config_folder, "variations.db"))
            continue
        end
        # rename all "variation" to "config_variation" in filenames and in databases
        mv(joinpath(data_dir, "inputs", "configs", config_folder, "variations.db"), joinpath(data_dir, "inputs", "configs", config_folder, "config_variations.db"))
        db_config_variations = joinpath(data_dir, "inputs", "configs", config_folder, "config_variations.db") |> SQLite.DB
        DBInterface.execute(db_config_variations, "ALTER TABLE variations RENAME TO config_variations;")
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
    return true
end

