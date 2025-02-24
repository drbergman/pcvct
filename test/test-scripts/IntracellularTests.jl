filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

config = "template-combined"
custom_code = "template-combined"
cell_to_components_dict = Dict("default" => pcvct.PhysiCellComponent("roadrunner", "Toy_Metabolic_Model.xml"))
intracellular = assembleIntracellular!(cell_to_components_dict; name="template-combined")
inputs = InputFolders(config, custom_code; intracellular=intracellular)

dv1 = DiscreteVariation(["overall", "max_time"], 12.0)
xml_path = ["intracellulars", "intracellular:ID:1", "sbml", "model", "listOfReactions", "reaction:id:Aerobic", "kineticLaw", "math", "apply", "apply", "cn"]
dv2 = DiscreteVariation(xml_path, [5, 6])
out = run(inputs, [dv1, dv2])
@test out.n_success == 2

macros_lines = pcvct.readMacrosFile(out.trial)
@test "ADDON_ROADRUNNER" in macros_lines

#! more test coverage
intracellular = assembleIntracellular!(cell_to_components_dict; name="template-combined")
@test intracellular == "template-combined" #! should not need to make a new folder, the assembly.toml file should show they match