using LightXML, PhysiCellCellCreator

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

config_folder = "0_template"
custom_code_folder = "0_template"
rulesets_collection_folder = "0_template"
ic_cell_folder = "1_xml"
inputs = InputFolders(config_folder, custom_code_folder; rulesets_collection=rulesets_collection_folder, ic_cell=ic_cell_folder)

n_replicates = 1

discrete_variations = DiscreteVariation[]
push!(discrete_variations, DiscreteVariation(["overall","max_time"], 12.0))
push!(discrete_variations, DiscreteVariation(["save","full_data","interval"], 6.0))
push!(discrete_variations, DiscreteVariation(["save","SVG","interval"], 6.0))

xml_path = ["cell_patches:name:default", "patch_collection:type:disc", "patch:ID:1", "x0"]
vals = [0.0, -100.0]
push!(discrete_variations, DiscreteVariation(xml_path, vals))

out = run(inputs, discrete_variations; n_replicates=n_replicates)

@test out.trial isa Sampling

hashBorderPrint("SUCCESSFULLY ADDED IC CELL VARIATION!")

hashBorderPrint("SUCCESSFULLY CREATED SAMPLING WITH IC CELL VARIATION!")

@test out.n_success == length(out.trial)

simulation_with_ic_cell_xml_id = getSimulationIDs(out.trial)[1] #! used in ExportTests.jl

hashBorderPrint("SUCCESSFULLY RAN SAMPLING WITH IC CELL VARIATION!")

discrete_variations = DiscreteVariation[]
xml_path = ["cell_patches:name:default", "patch_collection:type:annulus", "patch:ID:1", "inner_radius"]
push!(discrete_variations, DiscreteVariation(xml_path, 300.0))

out_fail = run(out.trial.monads[1], discrete_variations; n_replicates=n_replicates)
@test out_fail.n_success == 0

ic_cell_folder = pcvct.createICCellXMLTemplate("2_xml")
@test ic_cell_folder == "2_xml"
@test isdir(pcvct.locationPath(:ic_cell, ic_cell_folder))
@test_nowarn pcvct.createICECMXMLTemplate(ic_cell_folder)

xml_path = ["cell_patches:name:default", "patch_collection:type:disc", "patch:ID:1", "x0"]
dv1 = DiscreteVariation(xml_path, -1e6) #! outside the domain so none can be placed
out = run(inputs, dv1)
@test out.n_success == 0