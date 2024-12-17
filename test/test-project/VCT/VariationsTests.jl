using Distributions

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

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

config_folder = "0_template"
rulesets_collection_folder = "0_template"
ic_cell_folder = "1_xml"

# Test edge cases of addGrid
config_variation_ids, rulesets_variation_ids, ic_cell_variation_ids = addVariations(GridVariation(), config_folder, rulesets_collection_folder, ic_cell_folder, discrete_variations)

# Test edge cases of addLHS
config_variation_ids, rulesets_variation_ids, ic_cell_variation_ids = addVariations(LHSVariation(4), config_folder, rulesets_collection_folder, ic_cell_folder, discrete_variations)

discrete_variations = DiscreteVariation[]
xml_path = [pcvct.cyclePath(cell_type); "phase_durations"; "duration:index:0"]
push!(discrete_variations, DiscreteVariation(xml_path, [1.0, 2.0]))
config_variation_ids, rulesets_variation_ids, ic_cell_variation_ids = addVariations(LHSVariation(4), config_folder, rulesets_collection_folder, ic_cell_folder, discrete_variations)

discrete_variations = DiscreteVariation[]
xml_path = ["cell_patches:name:default", "patch_collection:type:disc", "patch:ID:1", "x0"]
vals = [0.0, -100.0]
push!(discrete_variations, DiscreteVariation(xml_path, vals))
config_variation_ids, rulesets_variation_ids, ic_cell_variation_ids = addVariations(LHSVariation(4), config_folder, rulesets_collection_folder, ic_cell_folder, discrete_variations)

# Test edge cases of addSobol
config_variation_ids, rulesets_variation_ids, ic_cell_variation_ids = addVariations(pcvct.SobolVariation(5), config_folder, rulesets_collection_folder, ic_cell_folder, discrete_variations)

discrete_variations = DiscreteVariation[]
xml_path = [pcvct.cyclePath(cell_type); "phase_durations"; "duration:index:0"]
push!(discrete_variations, DiscreteVariation(xml_path, [1.0, 2.0]))
config_variation_ids, rulesets_variation_ids, ic_cell_variation_ids = addVariations(pcvct.SobolVariation(5; skip_start=false), config_folder, rulesets_collection_folder, ic_cell_folder, discrete_variations)

discrete_variations = DiscreteVariation[]
xml_path = ["hypothesis_ruleset:name:default","behavior:name:cycle entry","decreasing_signals","max_response"]
vals = [1.0, 2.0]
push!(discrete_variations, DiscreteVariation(xml_path, vals))
config_variation_ids, rulesets_variation_ids, ic_cell_variation_ids = addVariations(pcvct.SobolVariation(5; skip_start=4, include_one=true), config_folder, rulesets_collection_folder, ic_cell_folder, discrete_variations)

# Test edge cases of addRBD
config_variation_ids, rulesets_variation_ids, ic_cell_variation_ids = addVariations(pcvct.RBDVariation(1), config_folder, rulesets_collection_folder, ic_cell_folder, discrete_variations)

discrete_variations = DiscreteVariation[]
xml_path = ["cell_patches:name:default", "patch_collection:type:disc", "patch:ID:1", "x0"]
vals = [0.0, -100.0]
push!(discrete_variations, DiscreteVariation(xml_path, vals))
config_variation_ids, rulesets_variation_ids, ic_cell_variation_ids = addVariations(pcvct.RBDVariation(2), config_folder, rulesets_collection_folder, ic_cell_folder, discrete_variations)

discrete_variations = DiscreteVariation[]
xml_path = [pcvct.cyclePath(cell_type); "phase_durations"; "duration:index:0"]
push!(discrete_variations, DiscreteVariation(xml_path, [1.0, 2.0]))
config_variation_ids, rulesets_variation_ids, ic_cell_variation_ids = addVariations(pcvct.RBDVariation(3), config_folder, rulesets_collection_folder, ic_cell_folder, discrete_variations)

config_variation_ids, rulesets_variation_ids, ic_cell_variation_ids = addVariations(pcvct.RBDVariation(3; use_sobol=false), config_folder, rulesets_collection_folder, ic_cell_folder, discrete_variations)

# test deprecation of ElementaryVariation
@test_warn "`ElementaryVariation` is deprecated in favor of the more descriptive `DiscreteVariation`." ElementaryVariation(xml_path, [0.0, 1.0])