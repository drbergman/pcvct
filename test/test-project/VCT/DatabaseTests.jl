using Test, pcvct

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

pcvct.initializeDatabase()

path_to_physicell_folder = "./PhysiCell" # path to PhysiCell folder
path_to_data_folder = "./test-project/data" # path to data folder
initializeVCT(path_to_physicell_folder, path_to_data_folder)

getSimulationsTable()
simulation_ids = 1:50 |> collect
printSimulationsTable(simulation_ids)
pcvct.printConfigVariationsTable(simulation_ids)
pcvct.printRulesetsVariationsTable(simulation_ids)