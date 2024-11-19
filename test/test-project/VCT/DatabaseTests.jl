using Test, pcvct

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

path_to_physicell_folder = "./test-project/PhysiCell" # path to PhysiCell folder
path_to_data_folder = "./test-project/data" # path to data folder
initializeVCT(path_to_physicell_folder, path_to_data_folder)

simulationsTable()
simulation_ids = 1:5
printSimulationsTable(simulation_ids)
pcvct.printConfigVariationsTable(simulation_ids)
pcvct.printRulesetsVariationsTable(simulation_ids)