using Test, pcvct

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

pcvct.initializeDatabase()

path_to_physicell_folder = "./PhysiCell" # path to PhysiCell folder
path_to_data_folder = "./test-project/data" # path to data folder
initializeVCT(path_to_physicell_folder, path_to_data_folder)

config_id = 1
rulesets_collection_id = 1
ic_cell_id = 1
ic_substrate_id = -1
ic_ecm_id = -1
custom_code_id = 1
config_variation_id = 1
rulesets_variation_id = 1
ic_cell_variation_id = 0
variation_ids = pcvct.VariationIDs(config_variation_id, rulesets_variation_id, ic_cell_variation_id)
folder_ids = pcvct.AbstractSamplingIDs(config_id, rulesets_collection_id, ic_cell_id, ic_substrate_id, ic_ecm_id, custom_code_id)
simulation = Simulation(folder_ids, variation_ids)

simulation = Simulation(config_id, rulesets_collection_id, ic_cell_id, ic_substrate_id, ic_ecm_id, custom_code_id, config_variation_id, rulesets_variation_id, ic_cell_variation_id)
simulation = Simulation(1)

monad = Monad(1)

monad_min_length = 1
config_variation_ids = [1, 2]
rulesets_variation_ids = [1, 1]
ic_cell_variation_ids = [0, 0]
sampling = Sampling(monad_min_length, config_id, rulesets_collection_id, ic_cell_id, ic_substrate_id, ic_ecm_id, custom_code_id, config_variation_ids, rulesets_variation_ids, ic_cell_variation_ids)
sampling = Sampling(monad_min_length, folder_ids, config_variation_ids, rulesets_variation_ids, ic_cell_variation_ids)

trial = Trial(1)

samplings = [Sampling(1), Sampling(2)]
trial = Trial(samplings)