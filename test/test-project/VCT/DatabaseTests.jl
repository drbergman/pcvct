using SQLite

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

simulationsTable()
simulation_ids = 1:5
printSimulationsTable(simulation_ids)
pcvct.printConfigVariationsTable(simulation_ids)
pcvct.printRulesetsVariationsTable(simulation_ids)
pcvct.printICCellVariationsTable(simulation_ids)
pcvct.printICECMVariationsTable(simulation_ids)

# test required folders
config_src_folder =  joinpath(pcvct.data_dir, "inputs", "configs")
config_dest_folder = joinpath(pcvct.data_dir, "inputs", "configs_")
mv(config_src_folder, config_dest_folder)

custom_code_src_folder =  joinpath(pcvct.data_dir, "inputs", "custom_codes")
custom_code_dest_folder = joinpath(pcvct.data_dir, "inputs", "custom_codes_")
mv(custom_code_src_folder, custom_code_dest_folder)

@test pcvct.createSchema(false) == false

mv(config_dest_folder, config_src_folder)
mv(custom_code_dest_folder, custom_code_src_folder)

# test memory db
pcvct.initializeDatabase()
pcvct.reinitializeDatabase()
pcvct.initializeDatabase(joinpath(pcvct.data_dir, "vct.db"))

# test bad table
table_name_not_end_in_s = "test"
@test_throws ErrorException pcvct.createPCVCTTable(table_name_not_end_in_s, "")
schema_without_primary_id = ""
@test_throws ErrorException pcvct.createPCVCTTable("simulations", schema_without_primary_id)

@test_throws ArgumentError pcvct.icFilename("ecm")

# misc tests
config_db = pcvct.configDB(Simulation(1))
@test config_db isa SQLite.DB

ic_cell_db = pcvct.icCellDB(Simulation(1))
@test ic_cell_db isa Missing

ic_ecm_db = pcvct.icECMDB(Simulation(1))
@test ic_ecm_db isa Nothing

pcvct.configVariationIDs(Simulation(1))
pcvct.configVariationIDs(Sampling(1))
pcvct.rulesetsVariationIDs(Simulation(1))
pcvct.rulesetsVariationIDs(Sampling(1))
pcvct.icCellVariationIDs(Simulation(1))
pcvct.icCellVariationIDs(Sampling(1))
pcvct.icECMVariationIDs(Simulation(1))
pcvct.icECMVariationIDs(Sampling(1))

pcvct.configVariationsTable(Sampling(1); remove_constants=true)
pcvct.rulesetsVariationsTable(Sampling(1); remove_constants=true)
pcvct.icCellVariationsTable(Sampling(1); remove_constants=true)
pcvct.icECMVariationsTable(Sampling(1); remove_constants=true)