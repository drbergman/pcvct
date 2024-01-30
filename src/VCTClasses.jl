##########################################
#############   Simulation   #############
##########################################

struct Simulation
    id::Int # integer uniquely identifying this simulation
    patient_id::Int # integer identifying the patient that this simulation corresponds to
    variation_id::Int # integer identifying the variation (varied parameters) that this simulation corresponds to
    cohort_id::Int # integer identifying the cohort (treatment arm) this simulation belongs to
    folder_id::Int # integer identifying the folder that contains the custom and config folders
end

function Simulation(patient_id::Int, cohort_id::Int)
    folder_id = getFolderID(patient_id, cohort_id)
    variation_id = 0 # base variation (no variation)
    Simulation(patient_id, variation_id, cohort_id, folder_id)
end

function Simulation(patient_id::Int, variation_id::Int, cohort_id::Int, folder_id::Int)
    simulation_id = DBInterface.execute(getDB(), "INSERT INTO simulations (patient_id,variation_id,cohort_id,folder_id) VALUES($(patient_id),$(variation_id),$(cohort_id),$(folder_id)) RETURNING simulation_id;") |> DataFrame |> x->x.simulation_id[1]
    Simulation(simulation_id, patient_id, variation_id, cohort_id, folder_id)
end

function Simulation(patient_id::Int, cohort_id::Int, folder_id::Int)
    variation_id = 0 # base variation (no variation)
    Simulation(simulation_id, patient_id, variation_id, cohort_id, folder_id)
end

##########################################
###############   Monad   ################
##########################################

struct Monad
    # a monad is a group of simulation replicates, i.e. identical up to randomness
    id::Int # integer uniquely identifying this monad
    size::Int # number of simulations belonging to this monad
    simulation_ids::Vector{Int} # simulation ids belonging to this monad
    patient_id::Int # integer identifying the patient that this simulation corresponds to
    variation_id::Int # integer identifying the variation (varied parameters) that this simulation corresponds to
    cohort_id::Int # integer identifying the cohort (treatment arm) this simulation belongs to
    folder_id::Int # integer identifying the folder that contains the custom and config folders
end

function Monad(monad_id::Int, num_replicates::Int, simulation_ids::Vector{Int}, patient_id::Int, variation_id::Int, cohort_id::Int)
    folder_id = getFolderID(patient_id,cohort_id)
    Monad(monad_id, num_replicates, simulation_ids, patient_id, variation_id, cohort_id, folder_id)
end

##########################################
##############   Sampling   ##############
##########################################

struct Sampling
    # sampling is a group of monads with config parameters varied
    id::Int # integer uniquely identifying this sampling
    monad_ids::Array{Int} # array of monad indices belonging to this sampling
end