using Test, pcvct

include("./PrintHelpers.jl")

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

path_to_physicell_folder = "./PhysiCell" # path to PhysiCell folder
path_to_data_folder = "./test-project/data" # path to data folder
initializeVCT(path_to_physicell_folder, path_to_data_folder)

config_folder = "default"
path_to_xml = "$(path_to_data_folder)/inputs/configs/$(config_folder)/PhysiCell_settings.xml"

element_paths = [
"default_celltype_path" => pcvct.cellDefinitionPath("default")
"phenotype_path" => pcvct.phenotypePath("default")

"cycle_path" => pcvct.cyclePath("default")
"death_path" => pcvct.deathPath("default")
"apoptosis_path" => pcvct.apoptosisPath("default")
"necrosis_path" => pcvct.necrosisPath("default")

"motility_path" => pcvct.motilityPath("default")

"cell_interactions_path" => pcvct.cellInteractionsPath("default")
"attack_rates_path" => pcvct.attackRatesPath("default")
]

for ep in element_paths
    ce = pcvct.retrieveElement(path_to_xml, ep[2]; required=false)
    @test !isnothing(ce) # make sure the element was found
end

node_paths = [
"speed_path" => pcvct.motilityPath("default", "speed")
"persistence_time_path" => pcvct.motilityPath("default", "persistence_time")
"migration_bias_path" => pcvct.motilityPath("default", "migration_bias")

"live_phagocytosis_rates_path" => pcvct.cellInteractionsPath("default", "live_phagocytosis_rates")

"attack_rate_default_path" => pcvct.attackRatesPath("default", "default")

"custom_data_path" => pcvct.customDataPath("default", "sample")
"custom_data_paths" => pcvct.customDataPath("default", ["sample"])

"number_of_cells_path" => pcvct.userParameterPath("number_of_cells")
"number_of_cells_paths" => pcvct.userParameterPath(["number_of_cells"])
] |> Dict

EV = ElementaryVariation[]
for (i, xml_path) in enumerate(values(node_paths))
    if typeof(xml_path[1])==String # do not add the custom_datas_path since they also vary "sample"
        if xml_path[end] == "number_of_cells"
            push!(EV, ElementaryVariation(xml_path, [1, 2]))
        else
            push!(EV, ElementaryVariation(xml_path, [float(i), float(i)+0.5]))
        end
    end
end

push!(EV, ElementaryVariation(["overall", "max_time"], [1.0]))

config_variation_ids = addGridVariation(config_folder, EV)

monad_min_length = 2
rulesets_collection_folder = "default"
ic_cell_folder = ""
ic_substrate_folder = ""
ic_ecm_folder = ""
custom_code_folder = "default"
rulesets_variation_ids = zeros(Int, size(config_variation_ids))

sampling = Sampling(monad_min_length, config_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder, custom_code_folder, config_variation_ids, rulesets_variation_ids)

n_ran, n_success = runAbstractTrial(sampling)
@test length(sampling) == length(config_variation_ids) * monad_min_length
@test n_ran == n_success

## test the in place functions
reference_config_variation_id = config_variation_ids[1] # just get one with the short max_time
config_variation_ids = Int[]
EV = ElementaryVariation[]
addDomainVariationDimension!(EV, (-78.0, 78.0, -30.0, 30.0, -10.0, 10.0))
new_config_variation_ids = addGridVariation(config_folder, EV; reference_variation_id=reference_config_variation_id)
append!(config_variation_ids, new_config_variation_ids)


EV = ElementaryVariation[]
addDomainVariationDimension!(EV, (x_min=-78.1, x_max=78.1, y_min=-30.1, y_max=30.1, z_min=-10.1, z_max=10.1))
new_config_variation_ids = addGridVariation(config_folder, EV; reference_variation_id=reference_config_variation_id)
append!(config_variation_ids, new_config_variation_ids)

EV = ElementaryVariation[]
addDomainVariationDimension!(EV, (min_x=-78.2, maxy=30.2))
new_config_variation_ids = addGridVariation(config_folder, EV; reference_variation_id=reference_config_variation_id)
append!(config_variation_ids, new_config_variation_ids)

EV = ElementaryVariation[]
addMotilityVariationDimension!(EV, "default", "speed", [0.1, 1.0])
addCustomDataVariationDimension!(EV, "default", "sample", [0.1, 1.0])
new_config_variation_ids = addGridVariation(config_folder, EV; reference_variation_id=reference_config_variation_id)
append!(config_variation_ids, new_config_variation_ids)

rulesets_variation_ids = zeros(Int, size(config_variation_ids))
sampling = Sampling(monad_min_length, config_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder, custom_code_folder, config_variation_ids, rulesets_variation_ids)

n_ran, n_success = runAbstractTrial(sampling)
@test n_ran == n_success

hashBorderPrint("SUCCESSFULLY VARIED CONFIG PARAMETERS!")

EV = ElementaryVariation[]
"default,pressure,decreases,cycle entry,0,0.5,4,0"

xml_path = ["hypothesis_ruleset:name:default","behavior:name:cycle entry","decreasing_signals","max_response"]
push!(EV, ElementaryVariation(xml_path, [0.0, 1e-8]))
xml_path = ["hypothesis_ruleset:name:default","behavior:name:cycle entry","decreasing_signals","signal:name:cycle entry","half_max"]
push!(EV, ElementaryVariation(xml_path, [0.25, 0.75]))

rulesets_variation_ids = addGridRulesetsVariation(rulesets_collection_folder, EV)

config_variation_ids = fill(reference_config_variation_id, size(rulesets_variations_ids))
sampling = Sampling(monad_min_length, config_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder, custom_code_folder, config_variation_ids, rulesets_variation_ids)

n_ran, n_success = runAbstractTrial(sampling)
@test n_ran == n_success

hashBorderPrint("SUCCESSFULLY VARIED RULESETS PARAMETERS!")

EV = ElementaryVariation[]
addMotilityVariationDimension!(EV, "default", "speed", [0.1, 1.0])
xml_path = ["hypothesis_ruleset:name:default","behavior:name:cycle entry","decreasing_signals","signal:name:cycle entry","half_max"]
push!(EV, ElementaryVariation(xml_path, [0.25, 0.75]))

config_variation_ids, rulesets_variation_ids = addVariations(GridVariation(), config_folder, rulesets_collection_folder, EV; reference_variation_id=reference_config_variation_id, reference_rulesets_variation_id=0)

sampling = Sampling(monad_min_length, config_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder, custom_code_folder, config_variation_ids, rulesets_variation_ids)

n_ran, n_success = runAbstractTrial(sampling)
@test n_ran == n_success

hashBorderPrint("SUCCESSFULLY VARIED CONFIG AND RULESETS PARAMETERS!")
