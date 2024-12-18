filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

force_recompile = false

config_folder = "0_template"
rulesets_collection_folder = "0_template"
custom_code_folder = "0_template"
ic_cell_folder = ""
ic_substrate_folder = ""
ic_ecm_folder = ""

dv_max_time = DiscreteVariation(["overall", "max_time"], 12.0)
dv_save_full_data_interval = DiscreteVariation(["save", "full_data", "interval"], 6.0)
dv_save_svg_data_interval = DiscreteVariation(["save","SVG","interval"], 6.0)
discrete_variations = [dv_max_time, dv_save_full_data_interval, dv_save_svg_data_interval]

reference_config_variation_id, reference_rulesets_variation_id, reference_ic_cell_variation_id = addVariations(GridVariation(), config_folder, rulesets_collection_folder, ic_cell_folder, discrete_variations)
reference_config_variation_id = reference_config_variation_id[1]
reference_rulesets_variation_id = reference_rulesets_variation_id[1]
reference_ic_cell_variation_id = reference_ic_cell_variation_id[1]

cell_type = "default"

evs = ElementaryVariation[]
xml_path = [pcvct.cyclePath(cell_type); "phase_durations"; "duration:index:0"]
lower_bound = 250.0 - 50.0
upper_bound = 350.0 + 50.0
push!(evs, UniformDistributedVariation(xml_path, lower_bound, upper_bound))

xml_path = [pcvct.cyclePath(cell_type); "phase_durations"; "duration:index:1"]
vals = [100.0, 200.0, 300.0]
push!(evs, DiscreteVariation(xml_path, vals))

xml_path = [pcvct.cyclePath(cell_type); "phase_durations"; "duration:index:2"]
mu = 300.0
sigma = 50.0
lb = 10.0
ub = 1000.0
push!(evs, NormalDistributedVariation(xml_path, mu, sigma; lb=lb, ub=ub))

n_points = 2^3-1
monad_min_length = 1
folder_names = pcvct.AbstractSamplingFolders(config_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder, custom_code_folder)
folder_ids = pcvct.AbstractSamplingIDs(folder_names)

@test folder_names == pcvct.AbstractSamplingFolders(folder_ids)

gs_fn(simulation_id::Int) = finalPopulationCount(simulation_id)[cell_type]

moat_sampling = run(MOAT(n_points), monad_min_length, folder_names, evs; force_recompile=force_recompile, reference_config_variation_id=reference_config_variation_id, reference_rulesets_variation_id=reference_rulesets_variation_id, reference_ic_cell_variation_id=reference_ic_cell_variation_id, functions=[gs_fn])
moat_sampling = run(MOAT(8; orthogonalize=true), monad_min_length, folder_names, evs; force_recompile=force_recompile, reference_config_variation_id=reference_config_variation_id, reference_rulesets_variation_id=reference_rulesets_variation_id, reference_ic_cell_variation_id=reference_ic_cell_variation_id, functions=[gs_fn])
sobol_sampling = run(Sobolʼ(n_points), monad_min_length, folder_names, evs; force_recompile=force_recompile, reference_config_variation_id=reference_config_variation_id, reference_rulesets_variation_id=reference_rulesets_variation_id, reference_ic_cell_variation_id=reference_ic_cell_variation_id, functions=[gs_fn])
rbd_sampling = run(RBD(n_points), monad_min_length, folder_names, evs; force_recompile=force_recompile, reference_config_variation_id=reference_config_variation_id, reference_rulesets_variation_id=reference_rulesets_variation_id, reference_ic_cell_variation_id=reference_ic_cell_variation_id, functions=[gs_fn])

# test sensitivity with config, rules, and ic_cells at once
ic_cell_folder = "1_xml"
folder_names = pcvct.AbstractSamplingFolders(config_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder, custom_code_folder)

dv_max_time = DiscreteVariation(["overall", "max_time"], 12.0)
dv_save_full_data_interval = DiscreteVariation(["save", "full_data", "interval"], 6.0)
dv_save_svg_data_interval = DiscreteVariation(["save","SVG","interval"], 6.0)
discrete_variations = [dv_max_time, dv_save_full_data_interval, dv_save_svg_data_interval]

reference_config_variation_id, reference_rulesets_variation_id, reference_ic_cell_variation_id = addVariations(GridVariation(), config_folder, rulesets_collection_folder, ic_cell_folder, discrete_variations)
reference_config_variation_id = reference_config_variation_id[1]
reference_rulesets_variation_id = reference_rulesets_variation_id[1]
reference_ic_cell_variation_id = reference_ic_cell_variation_id[1]

evs = ElementaryVariation[]
xml_path = [pcvct.cyclePath(cell_type); "phase_durations"; "duration:index:0"]
lower_bound = 250.0 - 50.0
upper_bound = 350.0 + 50.0
push!(evs, UniformDistributedVariation(xml_path, lower_bound, upper_bound))

xml_path = ["hypothesis_ruleset:name:default","behavior:name:cycle entry","decreasing_signals","max_response"]
push!(evs, UniformDistributedVariation(xml_path, 0.0, 1.0e-8))

xml_path = ["cell_patches:name:default", "patch_collection:type:annulus", "patch:ID:1", "inner_radius"]
push!(evs, UniformDistributedVariation(xml_path, 0.0, 1.0))

moat_sampling = run(MOAT(n_points), monad_min_length, folder_names, evs; force_recompile=force_recompile, reference_config_variation_id=reference_config_variation_id, reference_rulesets_variation_id=reference_rulesets_variation_id, reference_ic_cell_variation_id=reference_ic_cell_variation_id, functions=[gs_fn])
n_simulations_expected = n_points * (length(evs) + 1) * monad_min_length
@test length(moat_sampling.sampling) == n_simulations_expected