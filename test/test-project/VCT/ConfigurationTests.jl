filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

config_folder = "0_template"
custom_code_folder = "0_template"
rulesets_collection_folder = "0_template"
inputs = InputFolders(config_folder, custom_code_folder; rulesets_collection=rulesets_collection_folder)

n_replicates = 2

path_to_xml = "$(path_to_data_folder)/inputs/configs/$(config_folder)/PhysiCell_settings.xml"

cell_type = "default"

element_paths = [
"default_celltype_path" => pcvct.cellDefinitionPath(cell_type)
"phenotype_path" => pcvct.phenotypePath(cell_type)

"cycle_path" => pcvct.cyclePath(cell_type)
"death_path" => pcvct.deathPath(cell_type)
"apoptosis_path" => pcvct.apoptosisPath(cell_type)
"necrosis_path" => pcvct.necrosisPath(cell_type)

"motility_path" => pcvct.motilityPath(cell_type)

"cell_interactions_path" => pcvct.cellInteractionsPath(cell_type)
"attack_rates_path" => pcvct.attackRatesPath(cell_type)
]

xml_doc = pcvct.openXML(path_to_xml)
for ep in element_paths
    ce = pcvct.retrieveElement(xml_doc, ep[2]; required=false)
    @test !isnothing(ce) # make sure the element was found
end
pcvct.closeXML(xml_doc)

node_paths = [
"speed_path" => pcvct.motilityPath(cell_type, "speed")
"persistence_time_path" => pcvct.motilityPath(cell_type, "persistence_time")
"migration_bias_path" => pcvct.motilityPath(cell_type, "migration_bias")

"live_phagocytosis_rates_path" => pcvct.cellInteractionsPath(cell_type, "live_phagocytosis_rates")

"attack_rate_default_path" => pcvct.attackRatesPath(cell_type, cell_type)

"custom_data_path" => pcvct.customDataPath(cell_type, "sample")
"custom_data_paths" => pcvct.customDataPath(cell_type, ["sample"])

"number_of_cells_path" => pcvct.userParameterPath("number_of_cells")
"number_of_cells_paths" => pcvct.userParameterPath(["number_of_cells"])
] |> Dict

discrete_variations = DiscreteVariation[]
for (i, xml_path) in enumerate(values(node_paths))
    if typeof(xml_path[1])==String # do not add the custom_datas_path since they also vary "sample"
        if xml_path[end] == "number_of_cells"
            push!(discrete_variations, DiscreteVariation(xml_path, [1, 2]))
        else
            push!(discrete_variations, DiscreteVariation(xml_path, float(i)))
        end
    end
end

push!(discrete_variations, DiscreteVariation(["overall", "max_time"], [12.0]))

out = run(inputs, discrete_variations; n_replicates=n_replicates)

@test out.trial isa Sampling
@test length(out.trial) == prod(length.(discrete_variations)) * n_replicates
@test out.n_success == length(out.trial)

## test the in place functions
reference_monad = Monad(out.trial.monad_ids[1])

monads = Monad[]
discrete_variations = DiscreteVariation[]
addDomainVariationDimension!(discrete_variations, (-78.0, 78.0, -30.0, 30.0, -10.0, 10.0))
monad = createTrial(reference_monad, discrete_variations; n_replicates=n_replicates)
push!(monads, monad)

discrete_variations = DiscreteVariation[]
addDomainVariationDimension!(discrete_variations, (x_min=-78.1, x_max=78.1, y_min=-30.1, y_max=30.1, z_min=-10.1, z_max=10.1))
monad = createTrial(reference_monad, discrete_variations; n_replicates=n_replicates)
push!(monads, monad)

discrete_variations = DiscreteVariation[]
addDomainVariationDimension!(discrete_variations, (min_x=-78.2, maxy=30.2))
monad = createTrial(reference_monad, discrete_variations; n_replicates=n_replicates)
push!(monads, monad)

sampling_1 = Sampling(monads)

discrete_variations = DiscreteVariation[]
addMotilityVariationDimension!(discrete_variations, cell_type, "speed", [0.1, 1.0])
addCustomDataVariationDimension!(discrete_variations, cell_type, "sample", [0.1, 1.0])
sampling_2 = createTrial(reference_monad, discrete_variations; n_replicates=n_replicates)

trial = Trial([sampling_1, sampling_2])

out = run(trial; force_recompile=false)
@test out.n_success == length(trial)

hashBorderPrint("SUCCESSFULLY VARIED CONFIG PARAMETERS!")

discrete_variations = DiscreteVariation[]

xml_path = ["hypothesis_ruleset:name:default","behavior:name:cycle entry","decreasing_signals","max_response"]
push!(discrete_variations, DiscreteVariation(xml_path, [0.0, 1e-8]))
xml_path = ["hypothesis_ruleset:name:default","behavior:name:cycle entry","decreasing_signals","signal:name:pressure","half_max"]
push!(discrete_variations, DiscreteVariation(xml_path, [0.25, 0.75]))

out = run(reference_monad, discrete_variations; n_replicates=n_replicates)

@test out.n_success == length(out.trial)

hashBorderPrint("SUCCESSFULLY VARIED RULESETS PARAMETERS!")

discrete_variations = DiscreteVariation[]
addMotilityVariationDimension!(discrete_variations, cell_type, "speed", [0.1, 1.0])
xml_path = ["hypothesis_ruleset:name:default","behavior:name:cycle entry","decreasing_signals","signal:name:pressure","half_max"]
push!(discrete_variations, DiscreteVariation(xml_path, [0.3, 0.6]))

out = run(reference_monad, discrete_variations; n_replicates=n_replicates)
@test out.n_success == length(out.trial)

hashBorderPrint("SUCCESSFULLY VARIED CONFIG AND RULESETS PARAMETERS!")

# one last set of tests for coverage 
discrete_variations = DiscreteVariation[]

addAttackRateVariationDimension!(discrete_variations, cell_type, cell_type, [0.1])

out = run(reference_monad, discrete_variations; n_replicates=n_replicates)
@test out.n_success == length(out.trial)