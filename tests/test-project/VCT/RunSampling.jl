include("../../../src/VCTModule.jl") # include
using .VCTModule

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
##   DATABASE SUCCESSFULLY INITIALIZED!   ##
############################################
""")

ic_cell_folder = ""
ic_substrate_folder = ""
ic_ecm_folder = ""
custom_code_folder = "default"
config_variation_id = config_variation_ids[1]
rulesets_variation_id = rulesets_variation_ids[1]
simulation = Simulation(config_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder, custom_code_folder, config_variation_id, rulesets_variation_id)

runAbstractTrial(simulation)

println("""
############################################
##      SIMULATION SUCCESSFULLY RUN!      ##
############################################
""")

query = VCTModule.constructSelectQuery("simulations", "")
df = queryToDataFrame(query; is_row=true)

println("""
############################################
##     SIMULATION SUCCESSFULLY IN DB!     ##
############################################
""")

monad_min_length = 2

EV = ElementaryVariation[]
xml_path = [VCTModule.cyclePath("default"); "phase_durations"; "duration:index:0"]
push!(EV, ElementaryVariation(xml_path, [1.0, 2.0]))
xml_path = [VCTModule.cyclePath("default"); "phase_durations"; "duration:index:1"]
push!(EV, ElementaryVariation(xml_path, [3.0, 4.0]))
xml_path = [VCTModule.cyclePath("default"); "phase_durations"; "duration:index:2"]
push!(EV, ElementaryVariation(xml_path, [5.0, 6.0]))
xml_path = [VCTModule.cyclePath("default"); "phase_durations"; "duration:index:3"]
push!(EV, ElementaryVariation(xml_path, [7.0, 8.0]))

reference_config_variation_id = config_variation_id
reference_rulesets_variation_id = rulesets_variation_id

sampling = Sampling(monad_min_length, config_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder, custom_code_folder, reference_config_variation_id, reference_rulesets_variation_id)

println("""
############################################
##      SAMPLING SUCCESSFULLY CREATED!    ##
############################################
""")

runAbstractTrial(sampling)

println("""
############################################
##      SAMPLING SUCCESSFULLY RUN!        ##
############################################
""")

simulation_ids = getSimulations(sampling)
expected_num_sims = monad_min_length
for ev in EV
    expected_num_sims *= length(ev.values)
end

@assert length(simulation_ids) == expected_num_sims

println("""
############################################
##    SAMPLING SUCCESSFULLY IN CSVS!      ##
############################################
""")