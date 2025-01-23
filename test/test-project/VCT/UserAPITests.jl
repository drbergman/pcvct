filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

config_folder = "0_template"
rulesets_collection_folder = "0_template"
custom_code_folder = "0_template"
inputs = InputFolders(config_folder, custom_code_folder; rulesets_collection=rulesets_collection_folder)

method = GridVariation()

dv = DiscreteVariation(["overall","max_time"], [12.0, 13.0])

out = run(method, inputs, dv)

method = LHSVariation(3)
dv = UniformDistributedVariation(["overall","max_time"], 12.0, 20.0)
reference = getSimulationIDs(out)[1] |> Simulation
out = run(method, reference, dv)

method = SobolVariation(4)
out = run(method, reference, dv)

method = pcvct.RBDVariation(5)
out = run(method, reference, dv)