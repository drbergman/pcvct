using Test, pcvct

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

path_to_physicell_folder = "./test-project/PhysiCell" # path to PhysiCell folder
path_to_data_folder = "./test-project/data" # path to data folder
initializeVCT(path_to_physicell_folder, path_to_data_folder)

simulation = Simulation(Monad(1))

prune_options = PruneOptions(true, true, true, true, true)
n_success = runAbstractTrial(simulation; prune_options=prune_options)

@test n_success == 1

pcvct.deleteSimulation(simulation.id)