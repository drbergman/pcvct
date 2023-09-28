module VCTDatabase
using SQLite, Tables, DataFrames

home_dir = cd(pwd,homedir())
db = SQLite.DB()

function initializeDatabase(path_to_database::String)
    VCTDatabase.db = SQLite.DB(path_to_database)
    return createSchema()
end

function initializeDatabase()
    VCTDatabase.db = SQLite.DB()
    return createSchema()
end

function createSchema()
    SQLite.execute(db, "CREATE TABLE IF NOT EXISTS patients (
        patient_id INTEGER PRIMARY KEY,
        patient_name TEXT
        )
    ")

    SQLite.execute(db, "CREATE TABLE IF NOT EXISTS cohorts (
        cohort_id INTEGER PRIMARY KEY,
        intervention TEXT UNIQUE
        )
    ")

    control_cohort_id = DBInterface.execute(db, "INSERT OR IGNORE INTO cohorts (cohort_id, intervention) VALUES (0, 'none') RETURNING cohort_id;") |> DataFrame |> x->x.cohort_id
    if isempty(control_cohort_id)
        control_cohort_id = DBInterface.execute(db, "SELECT cohort_id FROM cohorts WHERE intervention='none';") |> DataFrame |> x->x.cohort_id
    end
    control_cohort_id = control_cohort_id[1]

    SQLite.execute(db, "CREATE TABLE IF NOT EXISTS folders (
        folder_id INTEGER PRIMARY KEY,
        patient_id INTEGER,
        cohort_id INTEGER,
        path TEXT UNIQUE,
        FOREIGN KEY (patient_id)
            REFERENCES patients (patient_id),
        FOREIGN KEY (cohort_id)
            REFERENCES cohorts (cohort_id),
        UNIQUE(patient_id,cohort_id)
        )
    ")

    SQLite.execute(db, "CREATE TABLE IF NOT EXISTS simulations (
        simulation_id INTEGER PRIMARY KEY,
        patient_id INTEGER,
        variation_id INTEGER,
        cohort_id INTEGER,
        folder_id INTEGER,
        FOREIGN KEY (patient_id)
            REFERENCES patients (patient_id),
        FOREIGN KEY (cohort_id)
            REFERENCES cohorts (cohort_id)
        FOREIGN KEY (folder_id)
            REFERENCES folders (folder_id)
        )    
    ")
    return db, control_cohort_id
end

function selectRow(table_name::String, condition_stmt::String)
    df = DBInterface.execute(db, "SELECT * FROM $(table_name) " * condition_stmt * ";") |> DataFrame
    @assert size(df,1)==1 "Did not find exactly one row matching the query."
    return df
end

function selectRow(column_names::Vector{String}, table_name::String, condition_stmt::String)
    df = selectRow(table_name, condition_stmt)
    return [df[1,column_name] for column_name in column_names]
end

function selectRow(column_name::String, table_name::String, condition_stmt::String)
    df = selectRow(table_name, condition_stmt)
    return df[1,column_name]
end

function getFolderID(patient_id::Int,cohort_id::Int)
    return selectRow("folder_id","folders","WHERE patient_id=$(patient_id) AND cohort_id=$(cohort_id)")
end

function retrieveFolderInfo(folder_id::Int)
    return selectRow("folders","WHERE folder_id=$(folder_id)")
end

end