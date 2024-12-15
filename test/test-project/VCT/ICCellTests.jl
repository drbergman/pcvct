using LightXML
filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

config_folder = "0_template"
custom_code_folder = "0_template"
rulesets_collection_folder = "0_template"
ic_cell_folder = "1_xml"
monad_min_length = 1

EV = ElementaryVariation[]
push!(EV, ElementaryVariation(["overall","max_time"], 12.0))
push!(EV, ElementaryVariation(["save","full_data","interval"], 6.0))
push!(EV, ElementaryVariation(["save","SVG","interval"], 6.0))

xml_path = ["cell_patches:name:default", "patch_collection:type:disc", "patch:ID:1", "x0"]
vals = [0.0, -100.0]
push!(EV, ElementaryVariation(xml_path, vals))

config_variation_ids, rulesets_variation_ids, ic_cell_variation_ids = addVariations(GridVariation(), config_folder, rulesets_collection_folder, ic_cell_folder, EV)

hashBorderPrint("SUCCESSFULLY ADDED IC CELL VARIATION!")

sampling = Sampling(config_folder, custom_code_folder;
    monad_min_length=monad_min_length,
    rulesets_collection_folder=rulesets_collection_folder,
    ic_cell_folder=ic_cell_folder,
    config_variation_ids=config_variation_ids,
    rulesets_variation_ids=rulesets_variation_ids,
    ic_cell_variation_ids=ic_cell_variation_ids
)

hashBorderPrint("SUCCESSFULLY CREATED SAMPLING WITH IC CELL VARIATION!")

n_success = run(sampling; force_recompile=false)
@test n_success == length(sampling)

hashBorderPrint("SUCCESSFULLY RAN SAMPLING WITH IC CELL VARIATION!")

EV = ElementaryVariation[]
xml_path = ["cell_patches:name:default", "patch_collection:type:annulus", "patch:ID:1", "inner_radius"]
push!(EV, ElementaryVariation(xml_path, 300.0))

config_variation_ids, rulesets_variation_ids, ic_cell_variation_ids = 
    addVariations(GridVariation(), config_folder, rulesets_collection_folder, ic_cell_folder, EV;
    reference_config_variation_id=config_variation_ids[1], reference_rulesets_variation_id=rulesets_variation_ids[1], reference_ic_cell_variation_id=ic_cell_variation_ids[1])

sampling = Sampling(config_folder, custom_code_folder;
    monad_min_length=monad_min_length,
    rulesets_collection_folder=rulesets_collection_folder,
    ic_cell_folder=ic_cell_folder,
    config_variation_ids=config_variation_ids,
    rulesets_variation_ids=rulesets_variation_ids,
    ic_cell_variation_ids=ic_cell_variation_ids
)
    
n_success = run(sampling; force_recompile=false)
@test n_success == 0
