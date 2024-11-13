using Test, pcvct, Plots

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

path_to_physicell_folder = "./test-project/PhysiCell" # path to PhysiCell folder
path_to_data_folder = "./test-project/data" # path to data folder
initializeVCT(path_to_physicell_folder, path_to_data_folder)

asts = pcvct.AverageSubstrateTimeSeries(1)
ests = pcvct.ExtracellularSubstrateTimeSeries(1)