using Test, pcvct

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

path_to_physicell_folder = "./test-project/PhysiCell" # path to PhysiCell folder
path_to_data_folder = "./test-project/data" # path to data folder
initializeVCT(path_to_physicell_folder, path_to_data_folder)

hashBorderPrint("DATABASE SUCCESSFULLY INITIALIZED!")

config_folder = "0_template"
rulesets_collection_folder = "0_template"
ic_cell_folder = ""
EV = ElementaryVariation[]
push!(EV, ElementaryVariation(["overall","max_time"], [12.0]))
push!(EV, ElementaryVariation(["save","full_data","interval"], [6.0]))
push!(EV, ElementaryVariation(["save","SVG","interval"], [6.0]))

config_variation_ids, rulesets_variation_ids, ic_cell_variation_ids = addVariations(GridVariation(), config_folder, rulesets_collection_folder, ic_cell_folder, EV)
hashBorderPrint("DATABASE SUCCESSFULLY UPDATED!")

custom_code_folder = "0_template"
config_variation_id = config_variation_ids[1]
rulesets_variation_id = rulesets_variation_ids[1]
ic_cell_variation_id = ic_cell_variation_ids[1]
simulation = Simulation(config_folder, custom_code_folder;
    rulesets_collection_folder=rulesets_collection_folder,
    config_variation_id=config_variation_id,
    rulesets_variation_id=rulesets_variation_id,
    ic_cell_variation_id=ic_cell_variation_id
)

n_success = runAbstractTrial(simulation)
if n_success == 0
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
@test n_success == 1

hashBorderPrint("SIMULATION SUCCESSFULLY RUN!")

query = pcvct.constructSelectQuery("simulations")
df = pcvct.queryToDataFrame(query; is_row=true)

hashBorderPrint("SIMULATION SUCCESSFULLY IN DB!")

monad_min_length = 2

cell_type = "default"

EV = ElementaryVariation[]
xml_path = [pcvct.cyclePath(cell_type); "phase_durations"; "duration:index:0"]
push!(EV, ElementaryVariation(xml_path, [1.0, 2.0]))
xml_path = [pcvct.cyclePath(cell_type); "phase_durations"; "duration:index:1"]
push!(EV, ElementaryVariation(xml_path, [3.0, 4.0]))
xml_path = [pcvct.cyclePath(cell_type); "phase_durations"; "duration:index:2"]
push!(EV, ElementaryVariation(xml_path, [5.0, 6.0]))
xml_path = [pcvct.cyclePath(cell_type); "phase_durations"; "duration:index:3"]
push!(EV, ElementaryVariation(xml_path, [7.0, 8.0]))

config_variation_ids, rulesets_variation_ids, ic_cell_variation_ids = addVariations(GridVariation(), config_folder, rulesets_collection_folder, ic_cell_folder, EV; reference_config_variation_id=config_variation_id, reference_rulesets_variation_id=rulesets_variation_id, reference_ic_cell_variation_id=ic_cell_variation_id)
sampling = Sampling(config_folder, custom_code_folder;
    monad_min_length=monad_min_length,
    rulesets_collection_folder=rulesets_collection_folder,
    config_variation_ids=config_variation_ids,
    rulesets_variation_ids=rulesets_variation_ids,
    ic_cell_variation_ids=ic_cell_variation_ids
)

hashBorderPrint("SAMPLING SUCCESSFULLY CREATED!")

n_success = runAbstractTrial(sampling; force_recompile=false)
@test n_success == length(sampling)

hashBorderPrint("SAMPLING SUCCESSFULLY RUN!")

n_simulations = length(sampling) # number of simulations recorded (in .csvs) for this sampling
n_expected_sims = monad_min_length
for ev in EV
    global n_expected_sims *= length(ev.values)
end
n_variations = length(sampling.variation_ids)

# make sure the number of simulations in this sampling is what we expected based on...
@test n_simulations == n_expected_sims # the EVs...
@test n_simulations == n_variations * monad_min_length # ...how many variation ids we recorded (number of rulesets_variations_ids must match variation_ids on construction of sampling)
@test n_simulations == n_success # ...how many simulations succeeded

hashBorderPrint("SAMPLING SUCCESSFULLY IN CSVS!")

n_success = runAbstractTrial(sampling; force_recompile=false)

# no new simulations should have been run
@test n_success == 0

hashBorderPrint("SUCCESSFULLY FOUND PREVIOUS SIMS!")

trial = Trial([sampling])

n_success = runAbstractTrial(trial; force_recompile=false)

# no new simulations should have been run
@test n_success == 0

hashBorderPrint("SUCCESSFULLY RAN TRIAL!")
