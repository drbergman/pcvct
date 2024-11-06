using Test, pcvct

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

path_to_physicell_folder = "./test-project/PhysiCell" # path to PhysiCell folder
path_to_data_folder = "./test-project/data" # path to data folder
initializeVCT(path_to_physicell_folder, path_to_data_folder)

force_recompile = false

config_folder = "0_template"
rulesets_collection_folder = "0_template"
custom_code_folder = "0_template"
ic_substrate_folder = ""
ic_ecm_folder = ""

EV_max_time = ElementaryVariation(["overall", "max_time"], 12.0)
EV_save_full_data_interval = ElementaryVariation(["save", "full_data", "interval"], 6.0)
EV_save_svg_data_interval = ElementaryVariation(["save","SVG","interval"], 6.0)
EV = [EV_max_time, EV_save_full_data_interval, EV_save_svg_data_interval]

reference_config_variation_id, reference_rulesets_variation_id, reference_ic_cell_variation_id = addVariations(GridVariation(), config_folder, rulesets_collection_folder, ic_cell_folder, EV)
reference_config_variation_id = reference_config_variation_id[1]
reference_rulesets_variation_id = reference_rulesets_variation_id[1]
reference_ic_cell_variation_id = reference_ic_cell_variation_id[1]

cell_type = "default"

AV = DistributedVariation[]
for index in 0:1
    local xml_path = [pcvct.cyclePath(cell_type); "phase_durations"; "duration:index:$(index)"]
    lower_bound = 250.0 - index * 50.0
    upper_bound = 350.0 + index * 50.0
    push!(AV, UniformDistributedVariation(xml_path, lower_bound, upper_bound))
end
xml_path = [pcvct.cyclePath(cell_type); "phase_durations"; "duration:index:2"]
vals = [100.0, 200.0, 300.0]
push!(AV, ElementaryVariation(xml_path, vals))

xml_path = [pcvct.cyclePath(cell_type); "phase_durations"; "duration:index:3"]
mu = 300.0
sigma = 50.0
lb = 10.0
ub = 1000.0
push!(AV, NormalDistributedVariation(xml_path, mu, sigma; lb=lb, ub=ub))

n_points = 2^4-1
monad_min_length = 1
folder_names = pcvct.AbstractSamplingFolders(config_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder, custom_code_folder)
folder_ids = pcvct.AbstractSamplingIDs(folder_names)

@test folder_names == pcvct.AbstractSamplingFolders(folder_ids)

gs_fn(simulation_id::Int) = finalPopulationCount(simulation_id)[cell_type]

moat_sampling = sensitivitySampling(MOAT(n_points), monad_min_length, folder_names, AV; force_recompile=force_recompile, reference_config_variation_id=reference_config_variation_id, reference_rulesets_variation_id=reference_rulesets_variation_id, reference_ic_cell_variation_id=reference_ic_cell_variation_id, functions=[gs_fn])
sobol_sampling = sensitivitySampling(Sobolʼ(n_points), monad_min_length, folder_names, AV; force_recompile=force_recompile, reference_config_variation_id=reference_config_variation_id, reference_rulesets_variation_id=reference_rulesets_variation_id, reference_ic_cell_variation_id=reference_ic_cell_variation_id, functions=[gs_fn])
rbd_sampling = sensitivitySampling(RBD(n_points), monad_min_length, folder_names, AV; force_recompile=force_recompile, reference_config_variation_id=reference_config_variation_id, reference_rulesets_variation_id=reference_rulesets_variation_id, reference_ic_cell_variation_id=reference_ic_cell_variation_id, functions=[gs_fn])
