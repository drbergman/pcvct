abstract type AbstractSimulation end

##########################################
#############   Simulation   #############
##########################################

struct Simulation <: AbstractSimulation
    id::Int # integer uniquely identifying this simulation
    base_config_id::Int # integer identifying the base configuration folder id for lookup in the db (config_$(base_config_id)/)
    ic_id::Int # integer identifying the ICs folder for lookup in the db
    custom_code_id::Int # integer identifyng the custom code folder (with {main.cpp,Makefile,custom_modules/{custom.cpp,custom.h}} as folder structure) for lookup in the db
    
    base_config_path::String # path to config folder
    ics_path::String # path to ics folder
    custom_code_path::String # path to custom code folder

    variation_id::Int # integer identifying which variation on the base config file to use (variations_$(base_config_id).db)
end

function Simulation(base_config_id::Int, ic_id::Int, custom_code_id::Int)
    variation_id = 0 # base variation (no variation)
    return Simulation(base_config_id, ic_id, custom_code_id, variation_id)
end

function Simulation(base_config_id::Int, ic_id::Int, custom_code_id::Int, variation_id::Int)
    base_config_path, ics_path, custom_code_path = retrievePathInfo(base_config_id::Int, ic_id::Int, custom_code_id::Int)
    return Simulation(base_config_id, ic_id, custom_code_id, base_config_path, ics_path, custom_code_path, variation_id)
end

function Simulation(base_config_id::Int, ic_id::Int, custom_code_id::Int, base_config_path::String, ics_path::String, custom_code_path::String, variation_id::Int)
    simulation_id = DBInterface.execute(db, "INSERT INTO simulations (base_config_id,ic_id,custom_code_id,variation_id) VALUES($(base_config_id),$(ic_id),$(custom_code_id),$(variation_id)) RETURNING simulation_id;") |> DataFrame |> x -> x.simulation_id[1]
    return Simulation(simulation_id, base_config_id, ic_id, custom_code_id, base_config_path, ics_path, custom_code_path, variation_id)
end

# function Simulation(patient_id::Int, variation_id::Int, cohort_id::Int, folder_id::Int)
#     simulation_id = DBInterface.execute(getDB(), "INSERT INTO simulations (patient_id,variation_id,cohort_id,folder_id) VALUES($(patient_id),$(variation_id),$(cohort_id),$(folder_id)) RETURNING simulation_id;") |> DataFrame |> x->x.simulation_id[1]
#     Simulation(simulation_id, patient_id, variation_id, cohort_id, folder_id)
# end

# function Simulation(patient_id::Int, cohort_id::Int, folder_id::Int)
#     variation_id = 0 # base variation (no variation)
#     Simulation(simulation_id, patient_id, variation_id, cohort_id, folder_id)
# end

##########################################
###############   Monad   ################
##########################################

struct Monad <: AbstractSimulation
    # a monad is a group of simulation replicates, i.e. identical up to randomness
    id::Int # integer uniquely identifying this monad
    size::Int # number of simulations belonging to this monad
    simulation_ids::Vector{Int} # simulation ids belonging to this monad
    simulations::Vector{Simulation} # simulations that belong to this monad
    
    base_config_id::Int # integer identifying the base configuration folder id for lookup in the db (config_$(base_config_id)/)
    ic_id::Int # integer identifying the ICs folder for lookup in the db
    custom_code_id::Int # integer identifyng the custom code folder (with {main.cpp,Makefile,custom_modules/{custom.cpp,custom.h}} as folder structure) for lookup in the db
    
    base_config_path::String # path to config folder
    ics_path::String # path to ics folder
    custom_code_path::String # path to custom code folder

    variation_id::Int # integer identifying which variation on the base config file to use (variations_$(base_config_id).db)
end

function Monad(size::Int, base_config_id::Int, ic_id::Int, custom_code_id::Int)
    base_config_path, ics_path, custom_code_path = retrievePathInfo(base_config_id, ic_id, custom_code_id)
    return Monad(size, base_config_id, ic_id, custom_code_id, base_config_path, ics_path, custom_code_path)
end

function Monad(size::Int, base_config_id::Int, ic_id::Int, custom_code_id::Int, base_config_path::String, ics_path::String, custom_code_path::String)
    variation_id = 0
    return Monad(size, base_config_id, ic_id, custom_code_id, base_config_path, ics_path, custom_code_path, variation_id)
end

function Monad(size::Int, base_config_id::Int, ic_id::Int, custom_code_id::Int, base_config_path::String, ics_path::String, custom_code_path::String, variation_id::Int)
    monad_id = DBInterface.execute(db, "INSERT INTO monads (base_config_id,ic_id,custom_code_id,variation_id) VALUES($(base_config_id),$(ic_id),$(custom_code_id),$(variation_id)) RETURNING monad_id;") |> DataFrame |> x -> x.monad_id[1]
    simulation_ids = Int[]
    simulations = Simulation[]
    return Monad(monad_id, size, simulation_ids, simulations, base_config_id, ic_id, custom_code_id, base_config_path, ics_path, custom_code_path, variation_id)
end

# function Monad(monad_id::Int, size::Int, simulation_ids::Vector{Int}, patient_id::Int, variation_id::Int, cohort_id::Int)
#     folder_id = getFolderID(patient_id,cohort_id)
#     Monad(monad_id, size, simulation_ids, patient_id, variation_id, cohort_id, folder_id)
# end

##########################################
##############   Sampling   ##############
##########################################

struct Sampling
    # sampling is a group of monads with config parameters varied
    id::Int # integer uniquely identifying this sampling
    monad_ids::Array{Int} # array of monad indices belonging to this sampling
end