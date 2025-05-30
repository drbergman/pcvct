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

cell_type = "default"

xml_path = configPath(cell_type, "apoptosis", "death_rate")
dv = UniformDistributedVariation(xml_path, 0.0, 1.0)
@test_throws ErrorException pcvct.variationValues(dv)

discrete_variation = DiscreteVariation(xml_path, [0.0, 1.0])
@test_throws ErrorException cdf(discrete_variation, 0.5)

sobol_variation = pcvct.SobolVariation(; pow2=8)
rbd_variation = pcvct.RBDVariation(16; pow2_diff=0, num_cycles=1//2)
rbd_variation = pcvct.RBDVariation(16; num_cycles=1, use_sobol=false)

discrete_variations = DiscreteVariation[]
xml_path = rulePath("default", "cycle entry", "decreasing_signals", "max_response")
vals = [1.0, 2.0]
push!(discrete_variations, DiscreteVariation(xml_path, vals))

# Test edge cases of addGrid
add_variations_result = pcvct.addVariations(GridVariation(), inputs, discrete_variations)

# Test edge cases of addLHS
add_variations_result = pcvct.addVariations(LHSVariation(4), inputs, discrete_variations)

discrete_variations = DiscreteVariation[]
xml_path = pcvct.cyclePath(cell_type, "phase_durations", "duration:index:0")
push!(discrete_variations, DiscreteVariation(xml_path, [1.0, 2.0]))
add_variations_result = pcvct.addVariations(LHSVariation(; n=4), inputs, discrete_variations)

discrete_variations = DiscreteVariation[]
xml_path = icCellsPath("default", "disc", 1, "x0")
vals = [0.0, -100.0]
push!(discrete_variations, DiscreteVariation(xml_path, vals))
add_variations_result = pcvct.addVariations(LHSVariation(4), inputs, discrete_variations)

# Test edge cases of addSobol
add_variations_result = pcvct.addVariations(pcvct.SobolVariation(5), inputs, discrete_variations)

discrete_variations = DiscreteVariation[]
xml_path = pcvct.cyclePath(cell_type, "phase_durations", "duration:index:0")
push!(discrete_variations, DiscreteVariation(xml_path, [1.0, 2.0]))
add_variations_result = pcvct.addVariations(pcvct.SobolVariation(5; skip_start=false), inputs, discrete_variations)

discrete_variations = DiscreteVariation[]
xml_path = rulePath("default", "cycle entry", "decreasing_signals", "max_response")
vals = [1.0, 2.0]
push!(discrete_variations, DiscreteVariation(xml_path, vals))
add_variations_result = pcvct.addVariations(pcvct.SobolVariation(5; skip_start=4, include_one=true), inputs, discrete_variations)

# Test edge cases of addRBD
add_variations_result = pcvct.addVariations(pcvct.RBDVariation(1), inputs, discrete_variations)

discrete_variations = DiscreteVariation[]
xml_path = icCellsPath("default", "disc", 1, "x0")
vals = [0.0, -100.0]
push!(discrete_variations, DiscreteVariation(xml_path, vals))
add_variations_result = pcvct.addVariations(pcvct.RBDVariation(2), inputs, discrete_variations)

discrete_variations = DiscreteVariation[]
xml_path = pcvct.cyclePath(cell_type, "phase_durations", "duration:index:0")
push!(discrete_variations, DiscreteVariation(xml_path, [1.0, 2.0]))
add_variations_result = pcvct.addVariations(pcvct.RBDVariation(3), inputs, discrete_variations)

add_variations_result = pcvct.addVariations(pcvct.RBDVariation(3; use_sobol=false), inputs, discrete_variations)

# test deprecation of ElementaryVariation
@test_warn "`ElementaryVariation` is deprecated in favor of the more descriptive `DiscreteVariation`." ElementaryVariation(xml_path, [0.0, 1.0])

# CoVariation tests
config_folder = "0_template"
custom_code_folder = "0_template"
rulesets_collection_folder = "0_template"
ic_cell_folder = "1_xml"
inputs = InputFolders(config_folder, custom_code_folder; rulesets_collection=rulesets_collection_folder, ic_cell=ic_cell_folder)

dv_max_time = DiscreteVariation(["overall", "max_time"], 12.0)
apoptosis_rate_path = configPath(cell_type, "apoptosis", "death_rate")
cycle_rate_path = pcvct.cyclePath(cell_type, "phase_durations", "duration:index:0")
val_1 = [0.0, 1.0]
val_2 = [1000.0, 2000.0]
cv = CoVariation((apoptosis_rate_path, val_1), (cycle_rate_path, val_2))
show(stdout, MIME"text/plain"(), cv)

sampling = createTrial(inputs, [dv_max_time, cv]; n_replicates=2)
@test length(pcvct.readConstituentIDs(sampling)) == 2
@test length(sampling) == 4

df = pcvct.simulationsTable(sampling)
drs = df[!, Symbol("default: apop death rate")]
pdurs = df[!, Symbol("default: duration:index:0")]
for (dr, pdur) in zip(drs, pdurs)
    @test (val_1.==dr) == (val_2.==pdur) #! make sure they are using the same index in both
end

max_response_path = rulePath("default", "cycle entry", "decreasing_signals", "max_response")
mrs = [1.0, 2.0]

x0_path = icCellsPath("default", "disc", 1, "x0")
x0s = [0.0, -100.0]

cv_new = CoVariation([cv.variations; DiscreteVariation(max_response_path, mrs); DiscreteVariation(x0_path, x0s)])
cv_test = CoVariation(cv_new.variations...)
sampling = createTrial(inputs, [dv_max_time, cv_new]; n_replicates=3)
@test length(pcvct.readConstituentIDs(sampling)) == 2
@test length(sampling) == 6

d_1 = Uniform(0, 1)
d_2 = Normal(3, 0.01)
cv = CoVariation((apoptosis_rate_path, d_1), (cycle_rate_path, d_2))
sampling = createTrial(LHSVariation(5), inputs, cv; n_replicates=3)
@test length(pcvct.readConstituentIDs(sampling)) == 5
@test length(sampling) == 15
@test pcvct.variationLocation(cv) == [:config, :config]
@test pcvct.variationTarget(cv) == pcvct.XMLPath.([apoptosis_rate_path, cycle_rate_path])

cv = CoVariation(cv.variations[1], cv.variations[2]) #! CoVariation(ev1, ev2, ...)
sampling = createTrial(SobolVariation(7), inputs, cv; n_replicates=2)
@test length(pcvct.readConstituentIDs(sampling)) == 7

# more tests for coverage
ev = DiscreteVariation(rulePath("default", "cycle entry", "decreasing_signals", "signal:name:pressure", "applies_to_dead"), [true, false])
@test pcvct.sqliteDataType(ev) == "TEXT"

ev = DiscreteVariation(["options", "random_seed"], ["system_clock", 0])
@test pcvct.sqliteDataType(ev) == "TEXT"

Base.show(stdout, MIME"text/plain"(), pcvct.XMLPath(xml_path))
Base.show(stdout, MIME"text/plain"(), ev)
Base.show(stdout, MIME"text/plain"(), UniformDistributedVariation(xml_path, 0.0, 1.0))
Base.show(stdout, MIME"text/plain"(), cv)