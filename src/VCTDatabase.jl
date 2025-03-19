export printSimulationsTable, simulationsTable

db::SQLite.DB = SQLite.DB()

################## Database Initialization Functions ##################

function initializeDatabase(path_to_database::String; auto_upgrade::Bool=false)
    if db.file == ":memory:" || abspath(db.file) != abspath(path_to_database)
        println(rpad("Path to database:", 25, ' ') * path_to_database)
    end
    is_new_db = !isfile(path_to_database)
    global db = SQLite.DB(path_to_database)
    SQLite.transaction(db, "EXCLUSIVE")
    try
        createSchema(is_new_db; auto_upgrade=auto_upgrade)
    catch e
        SQLite.rollback(db)
        println("Error initializing database: $e")
        return false
    else
        SQLite.commit(db)
        global initialized = true
        return true
    end
end

function reinitializeDatabase()
    if !initialized
        return
    end
    global initialized = false
    return initializeDatabase(db.file; auto_upgrade=true)
end

function createSchema(is_new_db::Bool; auto_upgrade::Bool=false)
    #! make sure necessary directories are present
    if !necessaryInputsPresent()
        return false
    end

    #! start with pcvct version info
    if !resolvePCVCTVersion(is_new_db, auto_upgrade)
        println("Could not successfully upgrade database. Please check the logs for more information.")
        return false
    end

    #! initialize and populate physicell_versions table
    createPCVCTTable("physicell_versions", physicellVersionsSchema())
    global current_physicell_version_id = physicellVersionID()

    #! initialize tables for all inputs
    for (location, location_dict) in pairs(inputs_dict)
        table_name = tableName(location)
        table_schema = """
            $(locationIDName(location)) INTEGER PRIMARY KEY,
            folder_name UNIQUE,
            description TEXT
        """
        createPCVCTTable(table_name, table_schema)

        folders = readdir(locationPath(location); sort=false) |> filter(x -> isdir(joinpath(locationPath(location), x)))
        if location_dict["required"] && isempty(folders)
            println("No folders in $(locationPath(location)) found. This is where to put the folders for $(tableName(location)).")
            return false
        end
        for folder in folders
            insertFolder(location, folder)
        end
    end

    simulations_schema = """
        simulation_id INTEGER PRIMARY KEY,
        physicell_version_id INTEGER,
        $(inputIDsSubSchema()),
        $(inputVariationIDsSubSchema()),
        status_code_id INTEGER,
        $(abstractSamplingForeignReferenceSubSchema()),
        FOREIGN KEY (status_code_id)
            REFERENCES status_codes (status_code_id)
    """
    createPCVCTTable("simulations", simulations_schema)

    #! initialize monads table
    createPCVCTTable("monads", monadsSchema())

    #! initialize samplings table
    createPCVCTTable("samplings", samplingsSchema())

    #! initialize trials table
    trials_schema = """
        trial_id INTEGER PRIMARY KEY,
        datetime TEXT,
        description TEXT
    """
    createPCVCTTable("trials", trials_schema)

    createDefaultStatusCodesTable()

    return true
end

function necessaryInputsPresent()
    success = true
    for (location, location_dict) in pairs(inputs_dict)
        if !location_dict["required"]
            continue
        end

        if !(locationPath(location) |> isdir)
            println("No $(locationPath(location)) found. This is where to put the folders for $(tableName(location)).")
            success = false
        end
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
    $(inputIDsSubSchema()),
    $(inputVariationIDsSubSchema()),
    $(abstractSamplingForeignReferenceSubSchema()),
    UNIQUE (physicell_version_id,
            $(join([locationIDName(k) for k in keys(inputs_dict)], ",\n")),
            $(join([locationVarIDName(k) for (k, d) in pairs(inputs_dict) if any(d["varied"])], ",\n"))
            )
   """
end

function inputIDsSubSchema()
    return join(["$(locationIDName(k)) INTEGER" for k in keys(inputs_dict)], ",\n")
end

function inputVariationIDsSubSchema()
    return join(["$(locationVarIDName(k)) INTEGER" for (k, d) in pairs(inputs_dict) if any(d["varied"])], ",\n")
end

function abstractSamplingForeignReferenceSubSchema()
    return """
    FOREIGN KEY (physicell_version_id)
        REFERENCES physicell_versions (physicell_version_id),
    $(join(["""
    FOREIGN KEY ($(locationIDName(k)))
        REFERENCES $(tableName(k)) ($(locationIDName(k)))\
    """ for k in keys(inputs_dict)], ",\n"))
    """
end

function samplingsSchema()
    return """
    sampling_id INTEGER PRIMARY KEY,
    physicell_version_id INTEGER,
    $(inputIDsSubSchema()),
    $(abstractSamplingForeignReferenceSubSchema())
    """
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

function createPCVCTTable(table_name::String, schema::String; db::SQLite.DB=db)
    #! check that table_name ends in "s"
    if last(table_name) != 's'
        s = "Table name must end in 's'."
        s *= "\n\tThis helps to normalize what the id names are for these entries."
        s *= "\n\tYour table $(table_name) does not end in 's'."
        s *= "\n\tSee retrieveID(location::Symbol, folder_name::String; db::SQLite.DB=db)."
        throw(ErrorException(s))
    end
    #! check that schema has PRIMARY KEY named as table_name without the s followed by _id
    id_name = locationIDName(Symbol(table_name[1:end-1]))
    if !occursin("$(id_name) INTEGER PRIMARY KEY", schema)
        s = "Schema must have PRIMARY KEY named as $(id_name)."
        s *= "\n\tThis helps to normalize what the id names are for these entries."
        s *= "\n\tYour schema $(schema) does not have \"$(id_name) INTEGER PRIMARY KEY\"."
        s *= "\n\tSee retrieveID(location::Symbol, folder_name::String; db::SQLite.DB=db)."
        throw(ErrorException(s))
    end
    SQLite.execute(db, "CREATE TABLE IF NOT EXISTS $(table_name) (
        $(schema)
        )
    ")
    return
end

function insertFolder(location::Symbol, folder::String, description::String="")
    path_to_folder = locationPath(location, folder)
    old_description = metadataDescription(path_to_folder)
    description = isempty(old_description) ? description : old_description
    query = "INSERT OR IGNORE INTO $(tableName(location)) (folder_name, description) VALUES ('$folder', '$description') RETURNING $(locationIDName(location));"
    df = queryToDataFrame(query)
    if !folderIsVaried(location, folder)
        return
    end
    db_variations = joinpath(locationPath(location, folder), "$(location)_variations.db") |> SQLite.DB
    createPCVCTTable(variationsTableName(location), "$(locationVarIDName(location)) INTEGER PRIMARY KEY"; db=db_variations)
    DBInterface.execute(db_variations, "INSERT OR IGNORE INTO $(location)_variations ($(locationVarIDName(location))) VALUES(0);")
    input_folder = InputFolder(location, folder)
    prepareBaseFile(input_folder)
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
    mode = ismissing(new_status_code) ? "DEFERRED" : "EXCLUSIVE" #! if we are possibly going to update, then set to exclusive mode
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

function variationsDatabase(location::Symbol, folder::String)
    if folder == ""
        return nothing
    end
    path_to_db = joinpath(locationPath(location, folder), "$(location)_variations.db")
    if !isfile(path_to_db)
        return missing
    end
    return path_to_db |> SQLite.DB
end

function variationsDatabase(location::Symbol, id::Int)
    folder = inputFolderName(location, id)
    return variationsDatabase(location, folder)
end

function variationsDatabase(location::Symbol, S::AbstractSampling)
    folder = S.inputs[location].folder
    return variationsDatabase(location, folder)
end

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

function inputFolderName(location::Symbol, id::Int)
    if id == -1
        return ""
    end

    query = constructSelectQuery(tableName(location), "WHERE $(locationIDName(location))=$(id)"; selection="folder_name")
    return queryToDataFrame(query; is_row=true) |> x -> x.folder_name[1]
end

function retrieveID(location::Symbol, folder_name::String; db::SQLite.DB=db)
    if folder_name == ""
        return -1
    end
    primary_key_string = locationIDName(location)
    query = constructSelectQuery(tableName(location), "WHERE folder_name='$(folder_name)'"; selection=primary_key_string)
    df = queryToDataFrame(query; is_row=true)
    return df[1, primary_key_string]
end

########### Summarizing Database Functions ###########

variationIDs(location::Symbol, M::AbstractMonad) = [M.variation_id[location]]
variationIDs(location::Symbol, sampling::Sampling) = [monad.variation_id[location] for monad in sampling.monads]

function variationsTable(query::String, db::SQLite.DB; remove_constants::Bool=false)
    df = queryToDataFrame(query, db=db)
    if remove_constants && size(df, 1) > 1
        col_names = names(df)
        filter!(n -> length(unique(df[!,n])) > 1, col_names)
        select!(df, col_names)
    end
    return df
end

function variationsTable(location::Symbol, variations_database::SQLite.DB, variation_ids::AbstractVector{<:Integer}; remove_constants::Bool=false)
    used_variation_ids = filter(x -> x != -1, variation_ids) #! variation_id = -1 means this input is not even being used
    query = constructSelectQuery(variationsTableName(location), "WHERE $(locationVarIDName(location)) IN ($(join(used_variation_ids,",")))")
    df = variationsTable(query, variations_database; remove_constants=remove_constants)
    rename!(name -> shortVariationName(location, name), df)
    return df
end

function variationsTable(location::Symbol, S::AbstractSampling; remove_constants::Bool=false)
    return variationsTable(location, variationsDatabase(location, S), variationIDs(location, S); remove_constants=remove_constants)
end

function variationsTable(location::Symbol, ::Nothing, variation_ids::AbstractVector{<:Integer}; kwargs...)
    @assert all(x -> x == -1, variation_ids) "If the $(location)_variation database is missing, then all $(locationVarIDName(location))s must be -1."
    return DataFrame(shortLocationVariationID(location)=>variation_ids)
end

function variationsTable(location::Symbol, ::Missing, variation_ids::AbstractVector{<:Integer}; kwargs...)
    @assert all(x -> x == 0, variation_ids) "If the $(location)_folder does not contain a $(location)_variations.db, then all $(locationVarIDName(location))s must be 0."
    return DataFrame(shortLocationVariationID(location)=>variation_ids)
end

function addFolderColumns!(df::DataFrame)
    for (location, location_dict) in pairs(inputs_dict)
        if !(locationIDName(location) in names(df))
            continue
        end
        unique_ids = unique(df[!,locationIDName(location)])
        folder_names_dict = [id => inputFolderName(location, id) for id in unique_ids] |> Dict{Int,String}
        if location_dict["required"]
            @assert !any(folder_names_dict |> values .|> isempty) "Some $(location) folders are empty/missing, but they are required."
        end
        df[!,"$(location)_folder"] .= [folder_names_dict[id] for id in df[!,locationIDName(location)]]
    end
    return df
end

function simulationsTableFromQuery(query::String; remove_constants::Bool=true,
                                   sort_by=String[],
                                   sort_ignore=[:SimID; shortLocationVariationID.(project_locations.varied)])
    #! preprocess sort kwargs
    sort_by = (sort_by isa Vector ? sort_by : [sort_by]) .|> Symbol
    sort_ignore = (sort_ignore isa Vector ? sort_ignore : [sort_ignore]) .|> Symbol

    df = queryToDataFrame(query)
    id_col_names_to_remove = names(df) #! a bunch of ids that we don't want to show
    locations = project_locations.varied

    filter!(n -> !(n in ["simulation_id"; [locationVarIDName(loc) for loc in locations]]), id_col_names_to_remove) #! but do not throw away the variation ids or the sim id, we want to show these
    addFolderColumns!(df) #! add the folder columns
    select!(df, Not(id_col_names_to_remove)) #! remove the id columns

    #! handle each of the varying inputs
    for loc in locations
        df = appendVariations(loc, df)
    end

    rename!(df, [:simulation_id => :SimID; [(locationVarIDName(loc) |> Symbol) => shortLocationVariationID(loc) for loc in locations]])
    col_names = names(df)
    if remove_constants && size(df, 1) > 1
        filter!(n -> length(unique(df[!, n])) > 1, col_names)
        select!(df, col_names)
    end
    if isempty(sort_by)
        sort_by = deepcopy(col_names)
    end
    sort_by = [n for n in sort_by if !(n in sort_ignore) && (n in col_names)] #! sort by columns in sort_by (overridden by sort_ignore) and in the dataframe
    sort!(df, sort_by)
    return df
end

function appendVariations(location::Symbol, df::DataFrame)
    short_var_name = shortLocationVariationID(location)
    var_df = DataFrame(short_var_name => Int[], :folder_name => String[])
    unique_tuples = [(row["$(location)_folder"], row[locationVarIDName(location)]) for row in eachrow(df)] |> unique
    for unique_tuple in unique_tuples
        temp_df = variationsTable(location, variationsDatabase(location, unique_tuple[1]), [unique_tuple[2]]; remove_constants=false)
        temp_df[!,:folder_name] .= unique_tuple[1]
        append!(var_df, temp_df, cols=:union)
    end
    folder_pair = ("$(location)_folder" |> Symbol) => :folder_name
    id_pair = (locationVarIDName(location) |> Symbol) => short_var_name
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
