using Test, pcvct

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

path_to_physicell_folder = "./PhysiCell" # path to PhysiCell folder
path_to_data_folder = "./test-project/data" # path to data folder
initializeVCT(path_to_physicell_folder, path_to_data_folder)

deleteSimulation(1)
pcvct.deleteMonad(1:10)
pcvct.deleteSampling(1)
pcvct.deleteTrial(1)

pcvct.deleteSimulationsByStatus(; user_check=false)
resetDatabase(; force_reset=true)