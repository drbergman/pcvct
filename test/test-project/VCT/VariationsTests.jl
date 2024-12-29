using Distributions

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

config_folder = "0_template"
custom_code_folder = "0_template"
rulesets_collection_folder = "0_template"
ic_cell_folder = "1_xml"
inputs = InputFolders(config_folder, custom_code_folder; rulesets_collection=rulesets_collection_folder, ic_cell=ic_cell_folder)

xml_path = [pcvct.apoptosisPath(cell_type); "death_rate"]
dv = UniformDistributedVariation(xml_path, 0.0, 1.0)
@test_throws ErrorException pcvct._values(dv)

discrete_variation = DiscreteVariation(xml_path, [0.0, 1.0])
@test_throws ErrorException cdf(discrete_variation, 0.5)

sobol_variation = pcvct.SobolVariation(; pow2=8)
rbd_variation = pcvct.RBDVariation(16; pow2_diff=0, num_cycles=1//2)
rbd_variation = pcvct.RBDVariation(16; num_cycles=1, use_sobol=false)

discrete_variations = DiscreteVariation[]
xml_path = ["hypothesis_ruleset:name:default","behavior:name:cycle entry","decreasing_signals","max_response"]
vals = [1.0, 2.0]
push!(discrete_variations, DiscreteVariation(xml_path, vals))

# Test edge cases of addGrid
config_variation_ids, rulesets_collection_variation_ids, ic_cell_variation_ids = addVariations(GridVariation(), inputs, discrete_variations)

# Test edge cases of addLHS
config_variation_ids, rulesets_collection_variation_ids, ic_cell_variation_ids = addVariations(LHSVariation(4), inputs, discrete_variations)

discrete_variations = DiscreteVariation[]
xml_path = [pcvct.cyclePath(cell_type); "phase_durations"; "duration:index:0"]
push!(discrete_variations, DiscreteVariation(xml_path, [1.0, 2.0]))
config_variation_ids, rulesets_collection_variation_ids, ic_cell_variation_ids = addVariations(LHSVariation(4), inputs, discrete_variations)

discrete_variations = DiscreteVariation[]
xml_path = ["cell_patches:name:default", "patch_collection:type:disc", "patch:ID:1", "x0"]
vals = [0.0, -100.0]
push!(discrete_variations, DiscreteVariation(xml_path, vals))
config_variation_ids, rulesets_collection_variation_ids, ic_cell_variation_ids = addVariations(LHSVariation(4), inputs, discrete_variations)

# Test edge cases of addSobol
config_variation_ids, rulesets_collection_variation_ids, ic_cell_variation_ids = addVariations(pcvct.SobolVariation(5), inputs, discrete_variations)

discrete_variations = DiscreteVariation[]
xml_path = [pcvct.cyclePath(cell_type); "phase_durations"; "duration:index:0"]
push!(discrete_variations, DiscreteVariation(xml_path, [1.0, 2.0]))
config_variation_ids, rulesets_collection_variation_ids, ic_cell_variation_ids = addVariations(pcvct.SobolVariation(5; skip_start=false), inputs, discrete_variations)

discrete_variations = DiscreteVariation[]
xml_path = ["hypothesis_ruleset:name:default","behavior:name:cycle entry","decreasing_signals","max_response"]
vals = [1.0, 2.0]
push!(discrete_variations, DiscreteVariation(xml_path, vals))
config_variation_ids, rulesets_collection_variation_ids, ic_cell_variation_ids = addVariations(pcvct.SobolVariation(5; skip_start=4, include_one=true), inputs, discrete_variations)

# Test edge cases of addRBD
config_variation_ids, rulesets_collection_variation_ids, ic_cell_variation_ids = addVariations(pcvct.RBDVariation(1), inputs, discrete_variations)

discrete_variations = DiscreteVariation[]
xml_path = ["cell_patches:name:default", "patch_collection:type:disc", "patch:ID:1", "x0"]
vals = [0.0, -100.0]
push!(discrete_variations, DiscreteVariation(xml_path, vals))
config_variation_ids, rulesets_collection_variation_ids, ic_cell_variation_ids = addVariations(pcvct.RBDVariation(2), inputs, discrete_variations)

discrete_variations = DiscreteVariation[]
xml_path = [pcvct.cyclePath(cell_type); "phase_durations"; "duration:index:0"]
push!(discrete_variations, DiscreteVariation(xml_path, [1.0, 2.0]))
config_variation_ids, rulesets_collection_variation_ids, ic_cell_variation_ids = addVariations(pcvct.RBDVariation(3), inputs, discrete_variations)

config_variation_ids, rulesets_collection_variation_ids, ic_cell_variation_ids = addVariations(pcvct.RBDVariation(3; use_sobol=false), inputs, discrete_variations)

# test deprecation of ElementaryVariation
@test_warn "`ElementaryVariation` is deprecated in favor of the more descriptive `DiscreteVariation`." ElementaryVariation(xml_path, [0.0, 1.0])