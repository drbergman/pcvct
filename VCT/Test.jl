using SQLite, DataFrames, Revise, JLD2
# cd("VCT")
# using .VCTModule
home_dir = cd(pwd,homedir())
run(`cp $(home_dir)/pcvct/data/spec_folders/test/config/PhysiCell_settings_default.xml $(home_dir)/pcvct/data/spec_folders/test/config/PhysiCell_settings.xml`)
include("./VCTModule.jl")

VCTModule.resetDatabase()

cd(home_dir*"/pcvct/src")

db = VCTModule.VCTDatabase.db
# DBInterface.execute(db,"INSERT INTO patients (patient_name) VALUES('test');")
# DBInterface.execute(db,"INSERT INTO variations (variation_id) VALUES(0);")
DBInterface.execute(db,"INSERT OR IGNORE INTO cohorts (intervention) VALUES('none');")
# DBInterface.execute(db,"INSERT INTO folders (patient_id,cohort_id,path) VALUES(1,1,'/Users/bergmand/pcvct/data/spec_folders/test');")

VCTModule.addPatient("test",home_dir*"/pcvct/data/spec_folders/test/")

xml_paths = [["cell_definitions","cell_definition:name:PD-L1lo_tumor","phenotype","cycle","phase_transition_rates","rate"]]
push!(xml_paths,["cell_definitions","cell_definition:name:PD-L1lo_tumor","phenotype","death","model:name:apoptosis","death_rate"])
new_values = [[1e-2,1e-1]]
push!(new_values, [0,1e-6])

variation_ids1, is_new_variation_id = VCTModule.addGridVariationToTable(1,xml_paths,new_values)

# xml_paths = [["cell_definitions","cell_definition:name:PD-L1hi_tumor","phenotype","cycle","phase_transition_rates","rate"]]
# push!(xml_paths,["cell_definitions","cell_definition:name:PD-L1hi_tumor","phenotype","death","model:name:apoptosis","death_rate"])
# new_values = [[2.2e-3,4.4e-2]]
# push!(new_values, [7e-5,8e-4])
# variation_ids2, is_new_variation_id = VCTModule.addGridVariationToTable(1,xml_paths,new_values; reference_variation=5)

# VCTModule.addVariation(1,["cell_definitions","cell_definition:name:PD-L1lo_tumor","phenotype","cycle","phase_transition_rates","rate"],[1e-4,1e-3])
# VCTModule.addVariation(1,["cell_definitions","cell_definition:name:PD-L1lo_tumor","phenotype","death","model:name:apoptosis","death_rate"],[0,1e-6])
gvax_cohort_id = VCTModule.addGVAX(1)
# VCTModule.runVirtualClinicalTrial(1,[variation_ids1...,variation_ids2...],[VCTModule.control_cohort_id,gvax_cohort_id],2)
VCTModule.runVirtualClinicalTrial(1,variation_ids1[:],[VCTModule.control_cohort_id,gvax_cohort_id],1)
