abstract type AbstractTrial end
abstract type AbstractSampling <: AbstractTrial end

##########################################
#############   Simulation   #############
##########################################

struct Simulation <: AbstractSampling
    id::Int # integer uniquely identifying this simulation
    base_config_id::Int # integer identifying the base configuration folder id for lookup in the db (config_$(base_config_id)/)
    rulesets_collection_id::Int # integer identifying which rulesets collection to use as a framework
    ic_id::Int # integer identifying the ICs folder for lookup in the db
    custom_code_id::Int # integer identifyng the custom code folder (with {main.cpp,Makefile,custom_modules/{custom.cpp,custom.h}} as folder structure) for lookup in the db
    
    base_config_folder::String # path to config folder
    rulesets_collection_folder::String # path to rulesets collection folder
    ic_folder::String # path to ics folder
    custom_code_folder::String # path to custom code folder
    
    variation_id::Int # integer identifying which variation on the base config file to use (variations.db)
    rulesets_variation_id::Int # integer identifying which variation on the ruleset file to use (rulesets_variations.db)
end

function Simulation(base_config_id::Int, rulesets_collection_id::Int , ic_id::Int, custom_code_id::Int)
    variation_id = 0 # base variation (no variation)
    rulesets_variation_id = 0 # base ruleset parameters applied
    return Simulation(base_config_id, rulesets_collection_id, ic_id, custom_code_id, variation_id, rulesets_variation_id)
end

function Simulation(base_config_id::Int, rulesets_collection_id::Int , ic_id::Int, custom_code_id::Int, variation_id::Int, rulesets_variation_id::Int)
    base_config_folder, rulesets_collection_folder, ic_folder, custom_code_folder = retrievePathInfo(base_config_id, rulesets_collection_id, ic_id, custom_code_id)
    return Simulation(base_config_id, rulesets_collection_id, ic_id, custom_code_id, base_config_folder, rulesets_collection_folder, ic_folder, custom_code_folder, variation_id, rulesets_variation_id)
end

function Simulation(base_config_id::Int, rulesets_collection_id::Int , ic_id::Int, custom_code_id::Int, base_config_folder::String, rulesets_collection_folder::String, ic_folder::String, custom_code_folder::String, variation_id::Int, rulesets_variation_id::Int)
    simulation_id = DBInterface.execute(db, "INSERT INTO simulations (base_config_id,rulesets_collection_id,ic_id,custom_code_id,variation_id,rulesets_variation_id) VALUES($(base_config_id),$(rulesets_collection_id),$(ic_id),$(custom_code_id),$(variation_id),$(rulesets_variation_id)) RETURNING simulation_id;") |> DataFrame |> x -> x.simulation_id[1]
    return Simulation(simulation_id, base_config_id, rulesets_collection_id, ic_id, custom_code_id, base_config_folder, rulesets_collection_folder, ic_folder, custom_code_folder, variation_id, rulesets_variation_id)
end

##########################################
###############   Monad   ################
##########################################

struct Monad <: AbstractSampling
    # a monad is a group of simulation replicates, i.e. identical up to randomness
    id::Int # integer uniquely identifying this monad
    min_length::Int # (minimum) number of simulations belonging to this monad
    simulation_ids::Vector{Int} # simulation ids belonging to this monad
    
    base_config_id::Int # integer identifying the base configuration folder id for lookup in the db (config_$(base_config_id)/)
    rulesets_collection_id::Int # integer identifying which rulesets collection to use as a framework
    ic_id::Int # integer identifying the ICs folder for lookup in the db
    custom_code_id::Int # integer identifyng the custom code folder (with {main.cpp,Makefile,custom_modules/{custom.cpp,custom.h}} as folder structure) for lookup in the db
    
    base_config_folder::String # path to config folder
    rulesets_collection_folder::String # path to rulesets collection folder
    ic_folder::String # path to ics folder
    custom_code_folder::String # path to custom code folder

    variation_id::Int # integer identifying which variation on the base config file to use (variations_$(base_config_id).db)
    rulesets_variation_id::Int # integer identifying which variation on the ruleset file to use (rulesets_variations_$(ruleset_id).db)
end

Base.size(monad::Monad) = size(monad.simulation_ids)

function Simulation(monad::Monad)
    return Simulation(monad.base_config_id, monad.rulesets_collection_id, monad.ic_id, monad.custom_code_id, monad.base_config_folder, monad.rulesets_collection_folder, monad.ic_folder, monad.custom_code_folder, monad.variation_id, monad.rulesets_variation_id)
end

function Monad(min_length::Int, base_config_id::Int, rulesets_collection_id::Int , ic_id::Int, custom_code_id::Int)
    base_config_folder, rulesets_collection_folder, ic_folder, custom_code_folder = retrievePathInfo(base_config_id, rulesets_collection_id, ic_id, custom_code_id)
    return Monad(min_length, base_config_id, rulesets_collection_id, ic_id, custom_code_id, base_config_folder, rulesets_collection_folder, ic_folder, custom_code_folder)
end

function Monad(min_length::Int, base_config_id::Int, rulesets_collection_id::Int , ic_id::Int, custom_code_id::Int, base_config_folder::String, rulesets_collection_folder::String, ic_folder::String, custom_code_folder::String)
    variation_id = 0
    rulesets_variation_id = 0
    return Monad(min_length, base_config_id, rulesets_collection_id, ic_id, custom_code_id, base_config_folder, rulesets_collection_folder, ic_folder, custom_code_folder, variation_id, rulesets_variation_id)
end

function Monad(min_length::Int, base_config_id::Int, rulesets_collection_id::Int , ic_id::Int, custom_code_id::Int, base_config_folder::String, rulesets_collection_folder::String, ic_folder::String, custom_code_folder::String, variation_id::Int, rulesets_variation_id::Int)
    monad_ids = DBInterface.execute(db, "INSERT OR IGNORE INTO monads (base_config_id,rulesets_collection_id,ic_id,custom_code_id,variation_id,rulesets_variation_id) VALUES($(base_config_id),$(rulesets_collection_id),$(ic_id),$(custom_code_id),$(variation_id),$(rulesets_variation_id)) RETURNING monad_id;") |> DataFrame |> x -> x.monad_id
    if isempty(monad_ids) # if monad insert command was ignored, then the monad already exists
        monad_id = DBInterface.execute(db, "SELECT monad_id FROM monads WHERE (base_config_id,rulesets_collection_id,ic_id,custom_code_id,variation_id,rulesets_variation_id)=($(base_config_id),$(rulesets_collection_id),$(ic_id),$(custom_code_id),$(variation_id),$(rulesets_variation_id));") |> DataFrame |> x -> x.monad_id[1] # get the monad_id
    else # if monad insert command was successful, then the monad is new
        monad_id = monad_ids[1] # get the monad_id
    end
    simulation_ids = getMondadSimulations(monad_id) # get the simulation ids belonging to this monad
    return Monad(monad_id, min_length, simulation_ids, base_config_id, rulesets_collection_id, ic_id, custom_code_id, base_config_folder, rulesets_collection_folder, ic_folder, custom_code_folder, variation_id, rulesets_variation_id) # return the monad
end

##########################################
##############   Sampling   ##############
##########################################

struct Sampling <: AbstractSampling
    # sampling is a group of monads with config parameters varied
    id::Int # integer uniquely identifying this sampling
    monad_min_length::Int # minimum length of each monad belonging to this sampling
    monad_ids::Array{Int} # array of monad indices belonging to this sampling

    base_config_id::Int # integer identifying the base configuration folder id for lookup in the db (config_$(base_config_id)/)
    rulesets_collection_id::Int # integer identifying which rulesets collection to use as a framework
    ic_id::Int # integer identifying the ICs folder for lookup in the db
    custom_code_id::Int # integer identifyng the custom code folder (with {main.cpp,Makefile,custom_modules/{custom.cpp,custom.h}} as folder structure) for lookup in the db
    
    base_config_folder::String # path to config folder
    rulesets_collection_folder::String # path to rulesets collection folder
    ic_folder::String # path to ics folder
    custom_code_folder::String # path to custom code folder

    variation_ids::Array{Int} # variation_id associated with each monad
    rulesets_variation_ids::Array{Int} # rulesets_variation_id associated with each monad

    function Sampling(id, monad_min_length, monad_ids, base_config_id, rulesets_collection_id, ic_id, custom_code_id, base_config_folder, rulesets_collection_folder, ic_folder, custom_code_folder, variation_ids, rulesets_variation_ids)
        n_monads = length(monad_ids)
        n_variations = length(variation_ids)
        n_rulesets_variations = length(rulesets_variation_ids)
        if n_monads != n_variations || n_monads != n_rulesets_variations # the negation of this is n_monads == n_variations && n_monads == n_rulesets_variations, which obviously means they're all the same
            throw(ArgumentError("Number of monads, variations, and rulesets variations must be the same"))
        end
        return new(id, monad_min_length, monad_ids, base_config_id, rulesets_collection_id, ic_id, custom_code_id, base_config_folder, rulesets_collection_folder, ic_folder, custom_code_folder, variation_ids, rulesets_variation_ids)
    end
end

Base.size(sampling::Sampling) = size(sampling.monad_ids)

function Monad(sampling::Sampling, variation_id::Int, rulesets_variation_id::Int)
    return Monad(sampling.monad_min_length, sampling.base_config_id, sampling.rulesets_collection_id, sampling.ic_id, sampling.custom_code_id, sampling.base_config_folder, sampling.rulesets_collection_folder, sampling.ic_folder, sampling.custom_code_folder, variation_id, rulesets_variation_id)
end

function Sampling(monad_min_length::Int, base_config_id::Int, rulesets_collection_id::Int , ic_id::Int, custom_code_id::Int, variation_ids::Array{Int}, rulesets_variation_ids::Array{Int})
    base_config_folder, rulesets_collection_folder, ic_folder, custom_code_folder = retrievePathInfo(base_config_id, rulesets_collection_id, ic_id, custom_code_id)
    return Sampling(monad_min_length, base_config_id, rulesets_collection_id, ic_id, custom_code_id, base_config_folder, rulesets_collection_folder, ic_folder, custom_code_folder, variation_ids, rulesets_variation_ids)
end

function Sampling(id::Int, monad_min_length::Int, base_config_id::Int, rulesets_collection_id::Int , ic_id::Int, custom_code_id::Int, base_config_folder::String, rulesets_collection_folder::String, ic_folder::String, custom_code_folder::String, variation_ids::Array{Int}, rulesets_variation_ids::Array{Int})
    monad_ids = createMonadIDs(monad_min_length, base_config_id, rulesets_collection_id, ic_id, custom_code_id, base_config_folder, rulesets_collection_folder, ic_folder, custom_code_folder, variation_ids, rulesets_variation_ids)
    return Sampling(id, monad_min_length, monad_ids, base_config_id, rulesets_collection_id, ic_id, custom_code_id, base_config_folder, rulesets_collection_folder, ic_folder, custom_code_folder, variation_ids, rulesets_variation_ids)
end

function Sampling(monad_min_length::Int, base_config_id::Int, rulesets_collection_id::Int , ic_id::Int, custom_code_id::Int, base_config_folder::String, rulesets_collection_folder::String, ic_folder::String, custom_code_folder::String, variation_ids::Array{Int}, rulesets_variation_ids::Array{Int})
    monad_ids = createMonadIDs(monad_min_length, base_config_id, rulesets_collection_id, ic_id, custom_code_id, base_config_folder, rulesets_collection_folder, ic_folder, custom_code_folder, variation_ids, rulesets_variation_ids)
    
    id = -1
    sampling_ids = DBInterface.execute(db, "SELECT sampling_id FROM samplings WHERE (base_config_id,rulesets_collection_id,ic_id,custom_code_id)=($(base_config_id),$(rulesets_collection_id),$(ic_id),$(custom_code_id));") |> DataFrame |> x -> x.sampling_id
    if !isempty(sampling_ids) # if there are previous samplings with the same parameters
        for sampling_id in sampling_ids # check if the monad_ids are the same with any previous monad_ids
            monad_ids_in_db = getSamplingMonads(sampling_id) # get the monad_ids belonging to this sampling
            if symdiff(monad_ids_in_db, monad_ids) |> isempty # if the monad_ids are the same
                id = sampling_id # use the existing sampling_id
                break
            end
        end
    end
    
    if id==-1 # if no previous sampling was found matching these parameters
        id = DBInterface.execute(db, "INSERT INTO samplings (base_config_id,rulesets_collection_id,ic_id,custom_code_id) VALUES($(base_config_id),$(rulesets_collection_id),$(ic_id),$(custom_code_id)) RETURNING sampling_id;") |> DataFrame |> x -> x.sampling_id[1] # get the sampling_id
    end
    return Sampling(id, monad_min_length, monad_ids, base_config_id, rulesets_collection_id, ic_id, custom_code_id, base_config_folder, rulesets_collection_folder, ic_folder, custom_code_folder, variation_ids, rulesets_variation_ids)
end

function createMonadIDs(monad_min_length::Int, base_config_id::Int, rulesets_collection_id::Int, ic_id::Int, custom_code_id::Int, base_config_folder::String, rulesets_collection_folder::String, ic_folder::String, custom_code_folder::String, variation_ids::Vector{Int}, rulesets_variation_ids::Vector{Int})
    _size = size(variation_ids)
    monad_ids = -ones(Int, _size)
    
    for i in eachindex(monad_ids)
        monad = Monad(monad_min_length, base_config_id, rulesets_collection_id, ic_id, custom_code_id, base_config_folder, rulesets_collection_folder, ic_folder, custom_code_folder, variation_ids[i], rulesets_variation_ids[i])
        monad_ids[i] = monad.id
    end
    return monad_ids
end

##########################################
###############   Trial   ################
##########################################

struct Trial <: AbstractTrial
    # trial is a group of samplings with different ICs, custom codes, and rulesets
    id::Int # integer uniquely identifying this trial
    monad_min_length::Int # minimum length of each monad belonging to the samplings in this trial
    sampling_ids::Vector{Int} # array of sampling indices belonging to this trial

    base_config_ids::Vector{Int} # integer identifying the base configuration folder id for each sampling
    rulesets_collection_ids::Vector{Int} # integer identifying which rulesets collection to use as a framework for each sampling
    ic_ids::Vector{Int} # integer identifying the ICs folder for each sampling
    custom_code_ids::Vector{Int} # integer identifyng the custom code folder (with {main.cpp,Makefile,custom_modules/{custom.cpp,custom.h}} as folder structure) for each sampling

    base_config_folders::Vector{String} # path to config folder for each sampling
    rulesets_collection_folders::Vector{String} # path to rulesets collection folder for each sampling
    ic_folders::Vector{String} # path to ics folder for each sampling
    custom_code_folders::Vector{String} # path to custom code folder for each sampling

    variation_ids::Vector{Vector{Int}} # variation_id associated with each monad for each sampling
    rulesets_variation_ids::Vector{Vector{Int}} # rulesets_variation_id associated with each monad for each sampling

    function Trial(id::Int, monad_min_length::Int, sampling_ids::Vector{Int}, base_config_ids::Vector{Int}, rulesets_collection_ids::Vector{Int}, ic_ids::Vector{Int}, custom_code_ids::Vector{Int}, base_config_folders::Vector{String}, rulesets_collection_folders::Vector{String}, ic_folders::Vector{String}, custom_code_folders::Vector{String}, variation_ids::Vector{Vector{Int}}, rulesets_variation_ids::Vector{Vector{Int}})
        n_samplings = length(sampling_ids)
        n_base_configs = length(base_config_ids)
        n_rulesets_collections = length(rulesets_collection_ids)
        n_ics = length(ic_ids)
        n_custom_codes = length(custom_code_ids)
        n_variations = length(variation_ids)
        n_rulesets_variations = length(rulesets_variation_ids)
        if n_samplings != n_base_configs || n_samplings != n_rulesets_collections || n_samplings != n_ics || n_samplings != n_custom_codes || n_samplings != n_variations || n_samplings != n_rulesets_variations # the negation of this is n_samplings == n_base_configs && n_samplings == n_rulesets_collections && n_samplings == n_ics && n_samplings == n_custom_codes && n_samplings == n_variations && n_samplings == n_rulesets_variations, which obviously means they're all the same
            throw(ArgumentError("Number of samplings, base configs, rulesets collections, ICs, custom codes, variations, and rulesets variations must be the same"))
        end

        return new(id, monad_min_length, sampling_ids, base_config_ids, rulesets_collection_ids, ic_ids, custom_code_ids, base_config_folders, rulesets_collection_folders, ic_folders, custom_code_folders, variation_ids, rulesets_variation_ids)
    end
end

Base.size(trial::Trial) = size(trial.sampling_ids)

function Sampling(trial::Trial, index::Int)
    return Sampling(trial.sampling_ids[index], trial.monad_min_length, trial.base_config_ids[index], trial.rulesets_collection_ids[index], trial.ic_ids[index], trial.custom_code_ids[index], trial.base_config_folders[index], trial.rulesets_collection_folders[index], trial.ic_folders[index], trial.custom_code_folders[index], trial.variation_ids[index], trial.rulesets_variation_ids[index])
end

function Trial(monad_min_length::Int, base_config_ids::Vector{Int}, rulesets_collection_ids::Vector{Int}, ic_ids::Vector{Int}, custom_code_ids::Vector{Int}, variation_ids::Vector{Vector{Int}}, rulesets_variation_ids::Vector{Vector{Int}})
    base_config_folders, rulesets_collection_folders, ic_folders, custom_code_folders = [retrievePathInfo(base_config_id, rulesets_collection_id, ic_id, custom_code_id) for (base_config_id, rulesets_collection_id, ic_id, custom_code_id) in zip(base_config_ids, rulesets_collection_ids, ic_ids, custom_code_ids)]
    return Trial(monad_min_length, base_config_ids, rulesets_collection_ids, ic_ids, custom_code_ids, base_config_folders, rulesets_collection_folders, ic_folders, custom_code_folders, variation_ids, rulesets_variation_ids)
end

function Trial(monad_min_length::Int, base_config_folders::Vector{String}, rulesets_collection_folders::Vector{String}, ic_folders::Vector{String}, custom_code_folders::Vector{String}, variation_ids::Vector{Vector{Int}}, rulesets_variation_ids::Vector{Vector{Int}})
    base_config_ids = [retrieveID("base_configs", folder) for folder in base_config_folders] |> x -> reshape(x, size(base_config_folders))
    rulesets_collection_ids = [retrieveID("rulesets_collections", rulesets_collection_folder, db=getRulesetsCollectionsDB(base_config_folder)) for (base_config_folder, rulesets_collection_folder) in zip(base_config_folders, rulesets_collection_folders)] |> x -> reshape(x, size(base_config_folders))
    ic_ids = [retrieveID("ics", folder) for folder in ic_folders] |> x -> reshape(x, size(base_config_folders))
    custom_code_ids = [retrieveID("custom_codes", folder) for folder in custom_code_folders] |> x -> reshape(x, size(base_config_folders))
    return Trial(monad_min_length, base_config_ids, rulesets_collection_ids, ic_ids, custom_code_ids, base_config_folders, rulesets_collection_folders, ic_folders, custom_code_folders, variation_ids, rulesets_variation_ids)
end

function Trial(monad_min_length::Int, base_config_ids::Vector{Int}, rulesets_collection_ids::Vector{Int}, ic_ids::Vector{Int}, custom_code_ids::Vector{Int}, base_config_folders::Vector{String}, rulesets_collection_folders::Vector{String}, ic_folders::Vector{String}, custom_code_folders::Vector{String}, variation_ids::Vector{Vector{Int}}, rulesets_variation_ids::Vector{Vector{Int}})
    _size = size(base_config_ids)
    sampling_ids = -ones(Int, _size)
    
    for i in eachindex(sampling_ids)
        sampling = Sampling(monad_min_length, base_config_ids[i], rulesets_collection_ids[i], ic_ids[i], custom_code_ids[i], base_config_folders[i], rulesets_collection_folders[i], ic_folders[i], custom_code_folders[i], variation_ids[i], rulesets_variation_ids[i])
        sampling_ids[i] = sampling.id
    end
    id = -1
    trial_ids = DBInterface.execute(db, "SELECT trial_id FROM trials;") |> DataFrame |> x -> x.trial_id
    if !isempty(trial_ids) # if there are previous trials
        for trial_id in trial_ids # check if the sampling_ids are the same with any previous sampling_ids
            sampling_ids_in_db = getTrialSamplings(trial_id) # get the sampling_ids belonging to this trial
            if symdiff(sampling_ids_in_db, sampling_ids) |> isempty # if the sampling_ids are the same
                id = trial_id # use the existing trial_id
                break
            end
        end
    end
    
    if id==-1 # if no previous trial was found matching these parameters
        id = DBInterface.execute(db, "INSERT INTO trials (datetime) VALUES($(Dates.format(now(),"yymmddHHMM"))) RETURNING trial_id;") |> DataFrame |> x -> x.trial_id[1] # get the trial_id
    end

    return Trial(id, monad_min_length, sampling_ids, base_config_ids, rulesets_collection_ids, ic_ids, custom_code_ids, base_config_folders, rulesets_collection_folders, ic_folders, custom_code_folders, variation_ids, rulesets_variation_ids)
end


####### trials defined parameterically

# ##########################################
# ###############   Trial   ################
# ##########################################

# struct Trial{M, N} <: AbstractTrial where M<:Integer where N<:Integer
#     # trial is a group of samplings with different ICs, custom codes, and rulesets
#     id::Int # integer uniquely identifying this trial
#     monad_min_length::Int # minimum length of each monad belonging to the samplings in this trial
#     sampling_ids::Array{Int, N} # array of sampling indices belonging to this trial

#     base_config_ids::Array{Int, N} # integer identifying the base configuration folder id for each sampling
#     rulesets_collection_ids::Array{Int, N} # integer identifying which rulesets collection to use as a framework for each sampling
#     ic_ids::Array{Int, N} # integer identifying the ICs folder for each sampling
#     custom_code_ids::Array{Int, N} # integer identifyng the custom code folder (with {main.cpp,Makefile,custom_modules/{custom.cpp,custom.h}} as folder structure) for each sampling

#     base_config_folders::Array{String, N} # path to config folder for each sampling
#     rulesets_collection_folders::Array{String, N} # path to rulesets collection folder for each sampling
#     ic_folders::Array{String, N} # path to ics folder for each sampling
#     custom_code_folders::Array{String, N} # path to custom code folder for each sampling

#     variation_ids::Array{Array{Int, M}, N} # variation_id associated with each monad for each sampling
#     rulesets_variation_ids::Array{Array{Int, M}, N} # rulesets_variation_id associated with each monad for each sampling

#     function Trial{M,N}(id::Int, monad_min_length::Int, sampling_ids::Array{Int, N}, base_config_ids::Array{Int, N}, rulesets_collection_ids::Array{Int, N}, ic_ids::Array{Int, N}, custom_code_ids::Array{Int, N}, base_config_folders::Array{String, N}, rulesets_collection_folders::Array{String, N}, ic_folders::Array{String, N}, custom_code_folders::Array{String, N}, variation_ids::Array{Array{Int, M}, N}, rulesets_variation_ids::Array{Array{Int, M}, N}) where {M,N}
#         n_samplings = length(sampling_ids)
#         n_base_configs = length(base_config_ids)
#         n_rulesets_collections = length(rulesets_collection_ids)
#         n_ics = length(ic_ids)
#         n_custom_codes = length(custom_code_ids)
#         n_variations = length(variation_ids)
#         n_rulesets_variations = length(rulesets_variation_ids)
#         if n_samplings != n_base_configs || n_samplings != n_rulesets_collections || n_samplings != n_ics || n_samplings != n_custom_codes || n_samplings != n_variations || n_samplings != n_rulesets_variations # the negation of this is n_samplings == n_base_configs && n_samplings == n_rulesets_collections && n_samplings == n_ics && n_samplings == n_custom_codes && n_samplings == n_variations && n_samplings == n_rulesets_variations, which obviously means they're all the same
#             throw(ArgumentError("Number of samplings, base configs, rulesets collections, ICs, custom codes, variations, and rulesets variations must be the same"))
#         end

#         return new(id, monad_min_length, sampling_ids, base_config_ids, rulesets_collection_ids, ic_ids, custom_code_ids, base_config_folders, rulesets_collection_folders, ic_folders, custom_code_folders, variation_ids, rulesets_variation_ids)
#     end
# end

# Base.size(trial::Trial) = size(trial.sampling_ids)

# function Sampling(trial::Trial, index::Int)
#     return Sampling(trial.monad_min_length, trial.base_config_ids[index], trial.rulesets_collection_ids[index], trial.ic_ids[index], trial.custom_code_ids[index], trial.base_config_folders[index], trial.rulesets_collection_folders[index], trial.ic_folders[index], trial.custom_code_folders[index], variation_ids[index], rulesets_variation_ids[index])
# end


# function Trial(monad_min_length::Int, base_config_ids::Array{Int, N}, rulesets_collection_ids::Array{Int, N}, ic_ids::Array{Int, N}, custom_code_ids::Array{Int, N}, base_config_folders::Array{String, N}, rulesets_collection_folders::Array{String, N}, ic_folders::Array{String, N}, custom_code_folders::Array{String, N}, variation_ids::Array{Array{Int, M}, N}, rulesets_variation_ids::Array{Array{Int, M}, N}) where {M,N}
#     _size = size(base_config_ids)
#     sampling_ids = -ones(Int, _size)
    
#     for i in eachindex(sampling_ids)
#         sampling = Sampling(monad_min_length, base_config_ids[i], rulesets_collection_ids[i], ic_ids[i], custom_code_ids[i], base_config_folders[i], rulesets_collection_folders[i], ic_folders[i], custom_code_folders[i], variation_ids[i], rulesets_variation_ids[i])
#         sampling_ids[i] = sampling.id
#     end
#     id = -1
#     trial_ids = DBInterface.execute(db, "SELECT trial_id FROM trials;") |> DataFrame |> x -> x.trial_id
#     if !isempty(trial_ids) # if there are previous trials
#         for trial_id in trial_ids # check if the sampling_ids are the same with any previous sampling_ids
#             sampling_ids_in_db = getTrialSamplings(trial_id) # get the sampling_ids belonging to this trial
#             if symdiff(sampling_ids_in_db, sampling_ids) |> isempty # if the sampling_ids are the same
#                 id = trial_id # use the existing trial_id
#                 break
#             end
#         end
#     end
    
#     if id==-1 # if no previous trial was found matching these parameters
#         id = DBInterface.execute(db, "INSERT INTO trials (datetime) VALUES($(Dates.format(now(),"yymmddHHMM"))) RETURNING trial_id;") |> DataFrame |> x -> x.trial_id[1] # get the trial_id
#     end

#     println("size(base_config_ids): $(size(base_config_ids))")
#     println("size(rulesets_collection_ids): $(size(rulesets_collection_ids))")
#     println("size(ic_ids): $(size(ic_ids))")
#     println("size(custom_code_ids): $(size(custom_code_ids))")
#     println("size(base_config_folders): $(size(base_config_folders))")
#     println("size(rulesets_collection_folders): $(size(rulesets_collection_folders))")
#     println("size(ic_folders): $(size(ic_folders))")
#     println("size(custom_code_folders): $(size(custom_code_folders))")
#     println("size(variation_ids): $(size(variation_ids))")
#     println("size(rulesets_variation_ids): $(size(rulesets_variation_ids))")

#     println("typeof(base_config_ids): $(typeof(base_config_ids))")
#     println("typeof(rulesets_collection_ids): $(typeof(rulesets_collection_ids))")
#     println("typeof(ic_ids): $(typeof(ic_ids))")
#     println("typeof(custom_code_ids): $(typeof(custom_code_ids))")
#     println("typeof(base_config_folders): $(typeof(base_config_folders))")
#     println("typeof(rulesets_collection_folders): $(typeof(rulesets_collection_folders))")
#     println("typeof(ic_folders): $(typeof(ic_folders))")
#     println("typeof(custom_code_folders): $(typeof(custom_code_folders))")
#     println("typeof(variation_ids): $(typeof(variation_ids))")
#     println("typeof(rulesets_variation_ids): $(typeof(rulesets_variation_ids))")

#     return Trial{M,N}(id, monad_min_length, sampling_ids, base_config_ids, rulesets_collection_ids, ic_ids, custom_code_ids, base_config_folders, rulesets_collection_folders, ic_folders, custom_code_folders, variation_ids, rulesets_variation_ids)
# end

# function Trial(monad_min_length::Int, base_config_ids::Array{Int, N}, rulesets_collection_ids::Array{Int, N}, ic_ids::Array{Int, N}, custom_code_ids::Array{Int, N}, variation_ids::Array{Array{Int, M}, N}, rulesets_variation_ids::Array{Array{Int, M}, N}) where {M,N}
#     base_config_folders, rulesets_collection_folders, ic_folders, custom_code_folders = [retrievePathInfo(base_config_id, rulesets_collection_id, ic_id, custom_code_id) for (base_config_id, rulesets_collection_id, ic_id, custom_code_id) in zip(base_config_ids, rulesets_collection_ids, ic_ids, custom_code_ids)]
#     return Trial{M,N}(monad_min_length, base_config_ids, rulesets_collection_ids, ic_ids, custom_code_ids, base_config_folders, rulesets_collection_folders, ic_folders, custom_code_folders, variation_ids, rulesets_variation_ids)
# end

# function Trial(monad_min_length::Int, base_config_folders::Array{String, N}, rulesets_collection_folders::Array{String, N}, ic_folders::Array{String, N}, custom_code_folders::Array{String, N}, variation_ids::Array{Array{Int, M}, N}, rulesets_variation_ids::Array{Array{Int, M}, N}) where {M,N}
#     base_config_ids = [retrieveID("base_configs", folder) for folder in base_config_folders] |> x -> reshape(x, size(base_config_folders))
#     rulesets_collection_ids = [retrieveID("rulesets_collections", rulesets_collection_folder, db=getRulesetsCollectionsDB(base_config_folder)) for (base_config_folder, rulesets_collection_folder) in zip(base_config_folders, rulesets_collection_folders)] |> x -> reshape(x, size(base_config_folders))
#     ic_ids = [retrieveID("ics", folder) for folder in ic_folders] |> x -> reshape(x, size(base_config_folders))
#     custom_code_ids = [retrieveID("custom_codes", folder) for folder in custom_code_folders] |> x -> reshape(x, size(base_config_folders))

#     println("size(base_config_ids): $(size(base_config_ids))")
#     println("size(rulesets_collection_ids): $(size(rulesets_collection_ids))")
#     println("size(ic_ids): $(size(ic_ids))")
#     println("size(custom_code_ids): $(size(custom_code_ids))")
#     println("size(base_config_folders): $(size(base_config_folders))")
#     println("size(rulesets_collection_folders): $(size(rulesets_collection_folders))")
#     println("size(ic_folders): $(size(ic_folders))")
#     println("size(custom_code_folders): $(size(custom_code_folders))")
#     println("size(variation_ids): $(size(variation_ids))")
#     println("size(rulesets_variation_ids): $(size(rulesets_variation_ids))")

#     println("typeof(base_config_ids): $(typeof(base_config_ids))")
#     println("typeof(rulesets_collection_ids): $(typeof(rulesets_collection_ids))")
#     println("typeof(ic_ids): $(typeof(ic_ids))")
#     println("typeof(custom_code_ids): $(typeof(custom_code_ids))")
#     println("typeof(base_config_folders): $(typeof(base_config_folders))")
#     println("typeof(rulesets_collection_folders): $(typeof(rulesets_collection_folders))")
#     println("typeof(ic_folders): $(typeof(ic_folders))")
#     println("typeof(custom_code_folders): $(typeof(custom_code_folders))")
#     println("typeof(variation_ids): $(typeof(variation_ids))")
#     println("typeof(rulesets_variation_ids): $(typeof(rulesets_variation_ids))")

#     println("base_config_ids: $(base_config_ids)")
#     println("rulesets_collection_ids: $(rulesets_collection_ids)")
#     println("ic_ids: $(ic_ids)")
#     println("custom_code_ids: $(custom_code_ids)")
#     println("base_config_folders: $(base_config_folders)")
#     println("rulesets_collection_folders: $(rulesets_collection_folders)")
#     println("ic_folders: $(ic_folders)")
#     println("custom_code_folders: $(custom_code_folders)")
#     println("variation_ids: $(variation_ids)")
#     println("rulesets_variation_ids: $(rulesets_variation_ids)")

#     println("size(base_config_ids)==(1,): $(size(base_config_ids)==(1,))")
#     println("size(rulesets_collection_ids)==(1,): $(size(rulesets_collection_ids)==(1,))")
#     println("size(ic_ids)==(1,): $(size(ic_ids)==(1,))")
#     println("size(custom_code_ids)==(1,): $(size(custom_code_ids)==(1,))")
#     println("size(base_config_folders)==(1,): $(size(base_config_folders)==(1,))")
#     println("size(rulesets_collection_folders)==(1,): $(size(rulesets_collection_folders)==(1,))")
#     println("size(ic_folders)==(1,): $(size(ic_folders)==(1,))")
#     println("size(custom_code_folders)==(1,): $(size(custom_code_folders)==(1,))")
#     println("size(variation_ids)==(1,): $(size(variation_ids)==(1,))")
#     println("size(rulesets_variation_ids)==(1,): $(size(rulesets_variation_ids)==(1,))")

#     println("size(variation_ids[1])==(1,): $(size(variation_ids[1])==(1,))")
#     println("size(rulesets_variation_ids[1])==(1,): $(size(rulesets_variation_ids[1])==(1,))")


#     return Trial{M,N}(monad_min_length, base_config_ids, rulesets_collection_ids, ic_ids, custom_code_ids, base_config_folders, rulesets_collection_folders, ic_folders, custom_code_folders, variation_ids, rulesets_variation_ids)
# end