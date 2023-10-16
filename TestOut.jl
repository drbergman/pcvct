using SQLite, DataFrames, Revise, JLD2
# cd("VCT")
# using .VCTModule
home_dir = cd(pwd,homedir())
path_to_data_folder = home_dir * "/pdac-ecm/user_projects/sandbox/data"
# path_to_data_folder = home_dir * "/pcvct/data"
path_to_physicell_folder = home_dir * "/pdac-ecm" # MAKE SURE THE PROJECT IS COMPILED ALREADY!
# path_to_physicell_folder = home_dir * "/pcvct/src" # MAKE SURE THE PROJECT IS COMPILED ALREADY!
run(`cp $(path_to_data_folder)/spec_folders/main/config/PhysiCell_settings_default.xml $(path_to_data_folder)/spec_folders/main/config/PhysiCell_settings.xml`)
include("./VCT/VCTModule.jl")

num_samples = 2

VCTModule.initializeVCT(path_to_physicell_folder, path_to_data_folder)

VCTModule.resetDatabase()

cd(path_to_physicell_folder)

db = VCTModule.VCTDatabase.db
# DBInterface.execute(db,"INSERT INTO patients (patient_name) VALUES('test');")
# DBInterface.execute(db,"INSERT INTO variations (variation_id) VALUES(0);")
DBInterface.execute(db,"INSERT OR IGNORE INTO cohorts (intervention) VALUES('none');")
# DBInterface.execute(db,"INSERT INTO folders (patient_id,cohort_id,path) VALUES(1,1,'/Users/bergmand/pcvct/data/spec_folders/test');")

VCTModule.addPatient("main",path_to_data_folder*"/spec_folders/main/")

D = [[["user_parameters","ecm_by_biofvm"],[false,true]]]
# xml_paths = 
# push!(xml_paths,)
# new_values = []
# push!(new_values, )
# [false,true]
# print([typeof])

# D = [[xml_paths[i],new_values[i]]]

variation_ids1, is_new_variation_id = VCTModule.addGridVariationToTable(1,D)

reference_variation_ids = DBInterface.execute(db, "SELECT variation_id FROM patient_variations_1 WHERE \"user_parameters/ecm_by_biofvm\"=\"false\";") |> DataFrame |> x->x.variation_id
D = [[["user_parameters","use_simple_ecm_to_cell_interactions"],[false,true]]]
for reference_variation_id in reference_variation_ids
    VCTModule.addGridVariationToTable(1, D; reference_variation=reference_variation_id)
end

D = [[["cell_definitions","cell_definition:name:mesenchymal_tumor","custom_data","ecm_sensitivity_anisotropy_ec50_slope"],[-1.0,-0.9,-0.8]]]
VCTModule.addGridVariationToTable(1, D; reference_variation=reference_variation_ids[1])
D = [[["cell_definitions","cell_definition:name:mesenchymal_tumor","custom_data","ecm_sensitivity_anisotropy_ec50_slope"],[-1.00,-0.90,-00.8000]]]
variation_ids, is_new_variation_id = VCTModule.addGridVariationToTable(1, D; reference_variation=reference_variation_ids[1])
# xml_paths = [["cell_definitions","cell_definition:name:PD-L1hi_tumor","phenotype","cycle","phase_transition_rates","rate"]]
# push!(xml_paths,["cell_definitions","cell_definition:name:PD-L1hi_tumor","phenotype","death","model:name:apoptosis","death_rate"])
# new_values = [[2.2e-3,4.4e-2]]
# push!(new_values, [7e-5,8e-4])
# variation_ids2, is_new_variation_id = VCTModule.addGridVariationToTable(1,xml_paths,new_values; reference_variation=5)

# VCTModule.addVariation(1,["cell_definitions","cell_definition:name:PD-L1lo_tumor","phenotype","cycle","phase_transition_rates","rate"],[1e-4,1e-3])
# VCTModule.addVariation(1,["cell_definitions","cell_definition:name:PD-L1lo_tumor","phenotype","death","model:name:apoptosis","death_rate"],[0,1e-6])
# gvax_cohort_id = VCTModule.addGVAX(1)
# VCTModule.runVirtualClinicalTrial(1,[variation_ids1...,variation_ids2...],[VCTModule.control_cohort_id,gvax_cohort_id],2)
VCTModule.runVirtualClinicalTrial(1,VCTModule.control_cohort_id,num_samples)
