using Test, pcvct

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

pcvct.initializeDatabase()

path_to_physicell_folder = "./PhysiCell" # path to PhysiCell folder
path_to_data_folder = "./test-project/data" # path to data folder
initializeVCT(path_to_physicell_folder, path_to_data_folder)

config_folder = "default"
custom_code_folder = "default"
rulesets_collection_folder = "default"
ic_cell_folder = "default"
config_variation_id = 0
rulesets_variation_id = 0
variation_ids = pcvct.VariationIDs(config_variation_id, rulesets_variation_id, ic_cell_variation_id)
simulation = Simulation(config_folder, custom_code_folder; rulesets_collection_folder=rulesets_collection_folder, ic_cell_folder=ic_cell_folder)

simulation = Simulation(1)

monad = Monad(1)

monad_min_length = 1
config_variation_ids = [1, 2]
rulesets_variation_ids = [1, 1]
ic_cell_variation_ids = [0, 0]
sampling = Sampling(config_folder, custom_code_folder;
    monad_min_length=monad_min_length,
    ic_cell_folder=ic_cell_folder,
    config_variation_ids=config_variation_ids,
    rulesets_variation_ids=rulesets_variation_ids,
    ic_cell_variation_ids=ic_cell_variation_ids
)

trial = Trial(1)

samplings = [Sampling(1), Sampling(2)]
trial = Trial(samplings)