using Test, pcvct

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
str = lpad(str, length(str) + Int(ceil((40 - length(str))/2)))
str = rpad(str, 40)

println("""
############################################
##$(str)##
############################################
""")

path_to_physicell_folder = "./PhysiCell" # path to PhysiCell folder
path_to_data_folder = "./test-project/data" # path to data folder
initializeVCT(path_to_physicell_folder, path_to_data_folder)

println("""
############################################
##   DATABASE SUCCESSFULLY INITIALIZED!   ##
############################################
""")

config_folder = "default"
rulesets_collection_folder = "default"
EV = ElementaryVariation[]
push!(EV, ElementaryVariation(["overall","max_time"], [60.0]))
push!(EV, ElementaryVariation(["save","full_data","interval"], [30.0]))
push!(EV, ElementaryVariation(["save","SVG","interval"], [30.0]))

config_variation_ids, rulesets_variation_ids = addVariations(GridVariation(), config_folder, rulesets_collection_folder, EV)

println("""
############################################
##     DATABASE SUCCESSFULLY UPDATED!     ##
############################################
""")

ic_cell_folder = ""
ic_substrate_folder = ""
ic_ecm_folder = ""
custom_code_folder = "default"
config_variation_id = config_variation_ids[1]
rulesets_variation_id = rulesets_variation_ids[1]
simulation = Simulation(config_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder, custom_code_folder, config_variation_id, rulesets_variation_id)

n_ran, n_success = runAbstractTrial(simulation)
if n_success == 0
    println("Simulation failed...")
    # print out the compilation error file if exists
    if isfile("$(path_to_data_folder)/inputs/custom_codes/$(custom_code_folder)/output.err")
        println(read("$(path_to_data_folder)/inputs/custom_codes/$(custom_code_folder)/output.err", String))
    else
        println("No compilation error file found.")
    end
    # print out the output error file if exists
    if isfile("$(path_to_data_folder)/outputs/simulations/$(simulation.id)/output.err")
        println(read("$(path_to_data_folder)/outputs/simulations/$(simulation.id)/output.err", String))
    else
        println("No output error file found.")
    end
    # print out the output log file if exists
    if isfile("$(path_to_data_folder)/outputs/simulations/$(simulation.id)/output.log")
        println(read("$(path_to_data_folder)/outputs/simulations/$(simulation.id)/output.log", String))
    else
        println("No output log file found.")
    end
end

println("""
############################################
##      SIMULATION SUCCESSFULLY RUN!      ##
############################################
""")

query = pcvct.constructSelectQuery("simulations", "")
df = pcvct.queryToDataFrame(query; is_row=true)

println("""
############################################
##     SIMULATION SUCCESSFULLY IN DB!     ##
############################################
""")

monad_min_length = 2

EV = ElementaryVariation[]
xml_path = [pcvct.cyclePath("default"); "phase_durations"; "duration:index:0"]
push!(EV, ElementaryVariation(xml_path, [1.0, 2.0]))
xml_path = [pcvct.cyclePath("default"); "phase_durations"; "duration:index:1"]
push!(EV, ElementaryVariation(xml_path, [3.0, 4.0]))
xml_path = [pcvct.cyclePath("default"); "phase_durations"; "duration:index:2"]
push!(EV, ElementaryVariation(xml_path, [5.0, 6.0]))
xml_path = [pcvct.cyclePath("default"); "phase_durations"; "duration:index:3"]
push!(EV, ElementaryVariation(xml_path, [7.0, 8.0]))

config_variation_ids, rulesets_variation_ids = addVariations(GridVariation(), config_folder, rulesets_collection_folder, EV; reference_variation_id=config_variation_id, reference_rulesets_variation_id=rulesets_variation_id)
sampling = Sampling(monad_min_length, config_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder, custom_code_folder, config_variation_ids, rulesets_variation_ids)

println("""
############################################
##      SAMPLING SUCCESSFULLY CREATED!    ##
############################################
""")

n_ran, n_success = runAbstractTrial(sampling)

println("""
############################################
##      SAMPLING SUCCESSFULLY RUN!        ##
############################################
""")

n_simulations = length(sampling) # number of simulations recorded (in .csvs) for this sampling
n_expected_sims = monad_min_length
for ev in EV
    global n_expected_sims *= length(ev.values)
end
n_variations = length(sampling.variation_ids)

# make sure the number of simulations in this sampling is what we expected based on...
@test n_simulations == n_expected_sims # the EVs...
@test n_simulations == n_variations * monad_min_length # ...how many variation ids we recorded (number of rulesets_variations_ids must match variation_ids on construction of sampling)
@test n_simulations == n_ran # ...how many simulations we started
@test n_simulations == n_success # ...how many simulations succeeded

println("""
############################################
##    SAMPLING SUCCESSFULLY IN CSVS!      ##
############################################
""")

n_ran, n_success = runAbstractTrial(sampling; use_previous_sims=true, force_recompile=false)

# no new simulations should have been run
@test n_ran == 0 
@test n_success == 0

println("""
############################################
##   SUCCESSFULLY FOUND PREVIOUS SIMS!    ##
############################################
""")

trial = Trial([sampling])

n_ran, n_success = runAbstractTrial(trial; use_previous_sims=true, force_recompile=false)

# no new simulations should have been run
@test n_ran == 0 
@test n_success == 0

println("""
############################################
##        SUCCESSFULLY RAN TRIAL!         ##
############################################
""")