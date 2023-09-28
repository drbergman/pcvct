import SQLite, DataFrames
db = SQLite.DB()
DBInterface.execute(db, "CREATE TABLE sims (
    id INTEGER PRIMARY KEY,
    a TEXT
    )
")

DBInterface.execute(db, "SELECT * FROM sims") |> DataFrame

DBInterface.execute(db, "ALTER TABLE sims ADD COLUMN 'save/folder' TEXT;")

DBInterface.execute(db, "SELECT * FROM sims") |> DataFrame

DBInterface.execute(db, "INSERT INTO sims (a, 'save/folder') VALUES(2.35,3.4);")

DBInterface.execute(db, "SELECT * FROM sims;") |> DataFrame
s = "SELECT * FROM sims WHERE \"save/folder\"=3.4;"
DBInterface.execute(db,s) |> DataFrame
