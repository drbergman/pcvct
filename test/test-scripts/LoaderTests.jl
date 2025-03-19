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
sequence = pcvct.PhysiCellSequence(out.trial.id; include_cells=true, include_substrates=true)

seq_dict = getCellDataSequence(sequence, "elapsed_time_in_phase"; include_dead=true)

simulation_population_time_series = pcvct.populationTimeSeries(out.trial; include_dead=true)
simulation_population_time_series["time"]
cell_types = keys(simulation_population_time_series.cell_count)
simulation_population_time_series[first(cell_types)]
@test_throws ArgumentError simulation_population_time_series["not_a_cell_type"]
simulation_population_time_series = pcvct.populationTimeSeries(out.trial; include_dead=false)


# brief pause for motility testing
for direction in [:x, :y, :z, :any]
    local mean_speed_dicts = motilityStatistics(Simulation(out.trial.id); direction=direction)
end
@test ismissing(motilityStatistics(pruned_simulation_id))

@test ismissing(pcvct.PhysiCellSequence(pruned_simulation_id))
@test pcvct.pathToOutputXML(pruned_simulation_id, :initial) |> pcvct.getLabels |> isempty
@test pcvct.pathToOutputXML(pruned_simulation_id, :initial) |> pcvct.getSubstrateNames |> isempty

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

simulation = Simulation(monad)
out = run(simulation; prune_options=PruneOptions(prune_mat=true))
mat_pruned_simulation_id = out.trial.id
pcvct.PhysiCellSnapshot(mat_pruned_simulation_id, 0; include_cells=true)
pcvct.PhysiCellSnapshot(mat_pruned_simulation_id, 0; include_substrates=true)
snapshot = pcvct.PhysiCellSnapshot(mat_pruned_simulation_id, 0)
@test ismissing(pcvct.averageExtracellularSubstrate(snapshot))

sequence = pcvct.PhysiCellSequence(mat_pruned_simulation_id; include_attachments=true, include_spring_attachments=true, include_neighbors=true)
pcvct.loadAttachments!(sequence)
pcvct.loadSpringAttachments!(sequence)
pcvct.loadNeighbors!(sequence)

simulation = Simulation(monad)
out = run(simulation; prune_options=PruneOptions(prune_txt=true))
txt_pruned_simulation_id = out.trial.id
@test ismissing(pcvct.PhysiCellSnapshot(txt_pruned_simulation_id, 0; include_attachments=true))
@test ismissing(pcvct.PhysiCellSnapshot(txt_pruned_simulation_id, 0; include_spring_attachments=true))
@test ismissing(pcvct.PhysiCellSnapshot(txt_pruned_simulation_id, 0; include_neighbors=true))