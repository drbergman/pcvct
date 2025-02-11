using LightXML, PhysiCellECMCreator

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

ic_ecm_folder = "1_xml"
pcvct.createICECMXMLTemplate(ic_ecm_folder)

config_folder = "template-ecm"
custom_code_folder = "template-ecm"
rulesets_collection_folder = "0_template"
inputs = InputFolders(config_folder, custom_code_folder; rulesets_collection=rulesets_collection_folder, ic_ecm=ic_ecm_folder)

n_replicates = 1

dv1 = DiscreteVariation(["overall", "max_time"], 12.0)
dv2 = DiscreteVariation(["layer:ID:2", "patch_collection:type:ellipse", "patch:ID:1", "density"], [0.25, 0.75])
out = run(inputs, [dv1, dv2]; n_replicates=n_replicates)

macros_lines = pcvct.readMacrosFile(out.trial)
@test "ADDON_PHYSIECM" in macros_lines

# test failing ecm sim
xml_path1 = ["layer:ID:2", "patch_collection:type:ellipse", "patch:ID:1", "a"]
xml_path2 = ["layer:ID:2", "patch_collection:type:elliptical_disc", "patch:ID:1", "a"]
dv1 = DiscreteVariation(xml_path1, 50.0)
dv2 = DiscreteVariation(xml_path2, 80.0)
cv = CoVariation(dv1, dv2)

out_fail = run(Monad(out.trial.monad_ids[1]), cv; n_replicates=n_replicates)
@test out_fail.n_success == 0