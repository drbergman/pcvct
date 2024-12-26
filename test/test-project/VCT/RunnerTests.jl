filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

hashBorderPrint("DATABASE SUCCESSFULLY INITIALIZED!")

config_folder = "0_template"
rulesets_collection_folder = "0_template"
custom_code_folder = "0_template"
inputs = InputFolders(config_folder, custom_code_folder; rulesets_collection=rulesets_collection_folder)

cell_type = "default"
n_replicates = 2

discrete_variations = DiscreteVariation[]
push!(discrete_variations, DiscreteVariation(["overall","max_time"], [12.0]))
push!(discrete_variations, DiscreteVariation(["save","full_data","interval"], [6.0]))
push!(discrete_variations, DiscreteVariation(["save","SVG","interval"], [6.0]))

simulation = createTrial(inputs, discrete_variations)

out = run(simulation)
@test out.trial isa Simulation
@test out.n_scheduled == 1
@test out.n_success == 1

out2 = run(inputs, discrete_variations)
@test out2.trial isa Simulation
@test out2.n_scheduled == 0
@test out2.n_success == 0

@test out.trial.id == out2.trial.id 
@test out.trial.inputs == out2.trial.inputs
@test out.trial.variation_ids == out2.trial.variation_ids

if out.n_success == 0
    hashBorderPrint("Simulation failed...")
    # print out the compilation error file if exists
    if isfile("$(path_to_data_folder)/inputs/custom_codes/$(custom_code_folder)/output.err")
        println(read("$(path_to_data_folder)/inputs/custom_codes/$(custom_code_folder)/output.err", String))
    else
        hashBorderPrint("No compilation error file found.")
    end
    # print out the output error file if exists
    if isfile("$(path_to_data_folder)/outputs/simulations/$(simulation.id)/output.err")
        println(read("$(path_to_data_folder)/outputs/simulations/$(simulation.id)/output.err", String))
    else
        hashBorderPrint("No output error file found.")
    end
    # print out the output log file if exists
    if isfile("$(path_to_data_folder)/outputs/simulations/$(simulation.id)/output.log")
        println(read("$(path_to_data_folder)/outputs/simulations/$(simulation.id)/output.log", String))
    else
        hashBorderPrint("No output log file found.")
    end
end

hashBorderPrint("SIMULATION SUCCESSFULLY RUN!")

query = pcvct.constructSelectQuery("simulations")
df = pcvct.queryToDataFrame(query; is_row=true)

hashBorderPrint("SIMULATION SUCCESSFULLY IN DB!")

discrete_variations = DiscreteVariation[]
xml_path = [pcvct.cyclePath(cell_type); "phase_durations"; "duration:index:0"]
push!(discrete_variations, DiscreteVariation(xml_path, [1.0, 2.0]))
xml_path = [pcvct.cyclePath(cell_type); "phase_durations"; "duration:index:1"]
push!(discrete_variations, DiscreteVariation(xml_path, [3.0, 4.0]))
xml_path = [pcvct.cyclePath(cell_type); "phase_durations"; "duration:index:2"]
push!(discrete_variations, DiscreteVariation(xml_path, [5.0, 6.0]))
xml_path = [pcvct.cyclePath(cell_type); "phase_durations"; "duration:index:3"]
push!(discrete_variations, DiscreteVariation(xml_path, [7.0, 8.0]))

sampling = createTrial(simulation, discrete_variations; n_replicates=n_replicates)

hashBorderPrint("SAMPLING SUCCESSFULLY CREATED!")

out = run(sampling; force_recompile=false)
@test out.n_success == length(sampling)

hashBorderPrint("SAMPLING SUCCESSFULLY RUN!")

out2 = run(simulation, discrete_variations; n_replicates=n_replicates, force_recompile=false)
@test out2.trial isa Sampling
@test out2.trial.id == sampling.id
@test out2.trial.inputs == sampling.inputs
@test Set(out2.trial.monad_ids) == Set(sampling.monad_ids)
@test Set(pcvct.getSimulationIDs(out2.trial)) == Set(pcvct.getSimulationIDs(sampling))
@test out2.n_scheduled == 0
@test out2.n_success == 0

hashBorderPrint("SUCCESSFULLY `run` WITHOUT CREATING SAMPLING!")


n_simulations = length(sampling) # number of simulations recorded (in .csvs) for this sampling
n_expected_sims = n_replicates
for discrete_variation in discrete_variations
    global n_expected_sims *= length(discrete_variation)
end
n_variations = length(sampling.variation_ids)

# make sure the number of simulations in this sampling is what we expected based on...
@test n_simulations == n_expected_sims # the discrete_variations...
@test n_simulations == n_variations * n_replicates # ...how many variation ids we recorded (number of rulesets_variations_ids must match variation_ids on construction of sampling)
@test n_simulations == out.n_success # ...how many simulations succeeded

hashBorderPrint("SAMPLING SUCCESSFULLY IN CSVS!")

out = run(sampling; force_recompile=false)

# no new simulations should have been run
@test out.n_success == 0

hashBorderPrint("SUCCESSFULLY FOUND PREVIOUS SIMS!")

trial = Trial([sampling])
@test trial isa Trial

out = run(trial; force_recompile=false)

# no new simulations should have been run
@test out.n_success == 0

hashBorderPrint("SUCCESSFULLY RAN TRIAL!")

@test_warn "`runAbstractTrial` is deprecated. Use `run` instead." runAbstractTrial(trial; force_recompile=false)