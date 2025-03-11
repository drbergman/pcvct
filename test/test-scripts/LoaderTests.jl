filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

config_folder = "0_template"
rulesets_collection_folder = "0_template"
custom_code_folder = "0_template"
inputs = InputFolders(config_folder, custom_code_folder; rulesets_collection=rulesets_collection_folder)

discrete_variations = DiscreteVariation[]
push!(discrete_variations, DiscreteVariation(["overall","max_time"], 12.0))
push!(discrete_variations, DiscreteVariation(["save","full_data","interval"], 6.0))
push!(discrete_variations, DiscreteVariation(["save","SVG","interval"], 6.0))

out = run(inputs, discrete_variations; use_previous=false)
@test out.trial isa Simulation
sequence = pcvct.PhysiCellSequence(joinpath("data", "outputs", "simulations", string(out.trial.id), "output"); include_cells=true, include_substrates=true)

seq_dict = getCellDataSequence(sequence, "elapsed_time_in_phase"; include_dead=true)

simulation_population_time_series = pcvct.populationTimeSeries(out.trial; include_dead=true)
simulation_population_time_series["time"]
cell_types = keys(simulation_population_time_series.cell_count)
simulation_population_time_series[first(cell_types)]
@test_throws ArgumentError simulation_population_time_series["not_a_cell_type"]
simulation_population_time_series = pcvct.populationTimeSeries(out.trial; include_dead=false)


for direction in [:x, :y, :z, :any]
    local mean_speed_dicts = pcvct.motilityStatistics(out.trial.id; direction=direction)
end

monad = createTrial(out.trial; n_replicates=0)
@test monad isa Monad

monad = createTrial(monad; n_replicates=2)
out = run(monad)
monad = out.trial
monad_population_time_series = pcvct.populationTimeSeries(monad; include_dead=false)
monad_population_time_series["time"]
@test_throws ArgumentError monad_population_time_series["not_a_cell_type"]

# misc testing
snapshot = sequence.snapshots[1]
pcvct.getLabels(snapshot)
pcvct.getSubstrateNames(snapshot)
pcvct.loadSubstrates!(sequence)
pcvct.loadMesh!(sequence)
snapshot = pcvct.PhysiCellSnapshot(1, 0)
sequence = pcvct.PhysiCellSequence(Simulation(1))
getCellDataSequence(1, "position")
getCellDataSequence(Simulation(1), "position")