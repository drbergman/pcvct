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
sequence = PhysiCellSequence(joinpath(path_to_data_folder, "outputs", "simulations", string(out.trial.id), "output"); include_cells=true, include_substrates=true)

seq_dict = getCellDataSequence(sequence, "elapsed_time_in_phase"; include_dead=true)

simulation_population_time_series = populationTimeSeries(out.trial; include_dead=true)
simulation_population_time_series = populationTimeSeries(out.trial; include_dead=false)

for direction in [:x, :y, :z, :any]
    local mean_speed_dicts = computeMeanSpeed(out.trial.id; direction=direction)
end

monad = createTrial(out.trial; n_replicates=0)
@test monad isa Monad