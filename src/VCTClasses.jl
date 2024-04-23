abstract type AbstractTrial end
abstract type AbstractSampling <: AbstractTrial end
abstract type AbstractMonad <: AbstractSampling end

##########################################
########   AbstractSamplingIDs   #########
##########################################

struct AbstractSamplingIDs
    base_config_id::Int # integer identifying the base configuration folder id for lookup in the db (config_$(base_config_id)/)
    rulesets_collection_id::Int # integer identifying which rulesets collection to use as a framework
    ic_cell_id::Int # integer identifying the ic cells folder for lookup in the db
    ic_substrate_id::Int # integer identifying the ic substrate folder for lookup in the db
    ic_ecm_id::Int # integer identifying the ic ecm folder for lookup in the db
    custom_code_id::Int # integer identifyng the custom code folder (with {main.cpp,Makefile,custom_modules/{custom.cpp,custom.h}} as folder structure) for lookup in the db
end

##########################################
######   AbstractSamplingFolders   #######
##########################################

struct AbstractSamplingFolders
    base_config_folder::String # path to config folder
    rulesets_collection_folder::String # path to rulesets collection folder
    ic_cell_folder::String # path to ic cells folder
    ic_substrate_folder::String # path to ic substrate folder
    ic_ecm_folder::String # path to ic ecm folder
    custom_code_folder::String # path to custom code folder
end

function AbstractSamplingFolders(ids::AbstractSamplingIDs)
    base_config_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder, custom_code_folder = retrievePathInfo(ids.base_config_id, ids.rulesets_collection_id, ids.ic_cell_id, ids.ic_substrate_id, ids.ic_ecm_id, ids.custom_code_id)
    return AbstractSamplingFolders(base_config_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder, custom_code_folder)
end

function AbstractSamplingIDs(folder_names::AbstractSamplingFolders)
    return AbstractSamplingIDs(retrieveID(folder_names)...)
end

##########################################
############   AddonMacros   #############
##########################################

# @kwdef mutable struct AddonMacros
#     initialized::Bool = false # whether the addon macros have been determined
#     macros::Vector{Symbol} = [] # the addon macros
# end

##########################################
#############   Simulation   #############
##########################################

struct Simulation <: AbstractMonad
    id::Int # integer uniquely identifying this simulation

    folder_ids::AbstractSamplingIDs # contains the ids of the folders that define this simulation
    folder_names::AbstractSamplingFolders # contains the paths to the folders that define this simulation
    
    variation_id::Int # integer identifying which variation on the base config file to use (variations.db)
    rulesets_variation_id::Int # integer identifying which variation on the ruleset file to use (rulesets_variations.db)

    # addon_macros::Union{AddonMacros,Nothing} # addon macros for this simulation
end

function Simulation(folder_ids::AbstractSamplingIDs, variation_id::Int, rulesets_variation_id::Int) # ; addon_macros::Union{AddonMacros,Nothing}=AddonMacros())
    folder_names = AbstractSamplingFolders(folder_ids)
    return Simulation(folder_ids, folder_names, variation_id, rulesets_variation_id) # ; addon_macros=addon_macros)
end

function Simulation(base_config_id::Int, rulesets_collection_id::Int, ic_substrate_id::Int, ic_ecm_id::Int, custom_code_id::Int, variation_id::Int, rulesets_variation_id::Int) # ; addon_macros::Union{AddonMacros,Nothing}=AddonMacros())
    folder_ids = AbstractSamplingIDs(base_config_id, rulesets_collection_id, ic_cell_id, ic_substrate_id, ic_ecm_id, custom_code_id)
    folder_names  = AbstractSamplingFolders(folder_ids)
    return Simulation(folder_ids, folder_names, variation_id, rulesets_variation_id) # ; addon_macros=addon_macros)
end

function Simulation(folder_ids::AbstractSamplingIDs, folder_names::AbstractSamplingFolders, variation_id::Int, rulesets_variation_id::Int) # ; addon_macros::Union{AddonMacros,Nothing}=AddonMacros())
    simulation_id = DBInterface.execute(db, "INSERT INTO simulations (base_config_id,rulesets_collection_id,ic_cell_id,ic_substrate_id,ic_ecm_id,custom_code_id,variation_id,rulesets_variation_id) VALUES($(folder_ids.base_config_id),$(folder_ids.rulesets_collection_id),$(folder_ids.ic_cell_id),$(folder_ids.ic_substrate_id),$(folder_ids.ic_ecm_id),$(folder_ids.custom_code_id),$(variation_id),$(rulesets_variation_id)) RETURNING simulation_id;") |> DataFrame |> x -> x.simulation_id[1]
    return Simulation(simulation_id, folder_ids, folder_names, variation_id, rulesets_variation_id) # , addon_macros)
end

##########################################
###############   Monad   ################
##########################################

struct Monad <: AbstractMonad
    # a monad is a group of simulation replicates, i.e. identical up to randomness
    id::Int # integer uniquely identifying this monad
    min_length::Int # (minimum) number of simulations belonging to this monad
    simulation_ids::Vector{Int} # simulation ids belonging to this monad

    folder_ids::AbstractSamplingIDs # contains the ids of the folders that define this monad
    folder_names::AbstractSamplingFolders # contains the paths to the folders that define this monad

    variation_id::Int # integer identifying which variation on the base config file to use (variations_$(base_config_id).db)
    rulesets_variation_id::Int # integer identifying which variation on the ruleset file to use (rulesets_variations_$(ruleset_id).db)

    # addon_macros::Union{AddonMacros,Nothing} # addon macros for this simulation
end

Base.size(monad::Monad) = size(monad.simulation_ids)

function Simulation(monad::Monad)
    return Simulation(monad.folder_ids, monad.folder_names, monad.variation_id, monad.rulesets_variation_id) # ; addon_macros=nothing)
end

function Monad(min_length::Int, folder_ids::AbstractSamplingIDs, folder_names::AbstractSamplingFolders, variation_id::Int, rulesets_variation_id::Int) # ; addon_macros::Union{AddonMacros,Nothing}=AddonMacros())
    monad_ids = DBInterface.execute(db, "INSERT OR IGNORE INTO monads (base_config_id,rulesets_collection_id,ic_cell_id,ic_substrate_id,ic_ecm_id,custom_code_id,variation_id,rulesets_variation_id) VALUES($(folder_ids.base_config_id),$(folder_ids.rulesets_collection_id),$(folder_ids.ic_cell_id),$(folder_ids.ic_substrate_id),$(folder_ids.ic_ecm_id),$(folder_ids.custom_code_id),$(variation_id),$(rulesets_variation_id)) RETURNING monad_id;") |> DataFrame |> x -> x.monad_id
    if isempty(monad_ids) # if monad insert command was ignored, then the monad already exists
        monad_id = DBInterface.execute(
            db,
            """
                SELECT monad_id FROM monads 
                WHERE (base_config_id,rulesets_collection_id,ic_cell_id,ic_substrate_id,ic_ecm_id,custom_code_id,variation_id,rulesets_variation_id)=
                (
                    $(folder_ids.base_config_id),$(folder_ids.rulesets_collection_id),$(folder_ids.ic_cell_id),$(folder_ids.ic_substrate_id),$(folder_ids.ic_ecm_id),$(folder_ids.custom_code_id),$(variation_id),$(rulesets_variation_id)
                );
            """
            ) |> DataFrame |> x -> x.monad_id[1] # get the monad_id
    else # if monad insert command was successful, then the monad is new
        monad_id = monad_ids[1] # get the monad_id
    end
    simulation_ids = getMonadSimulations(monad_id) # get the simulation ids belonging to this monad
    return Monad(monad_id, min_length, simulation_ids, folder_ids, folder_names, variation_id, rulesets_variation_id) # , addon_macros) # return the monad
end

##########################################
##############   Sampling   ##############
##########################################

struct Sampling <: AbstractSampling
    # sampling is a group of monads with config parameters varied
    id::Int # integer uniquely identifying this sampling
    monad_min_length::Int # minimum length of each monad belonging to this sampling
    monad_ids::Array{Int} # array of monad indices belonging to this sampling

    folder_ids::AbstractSamplingIDs # contains the ids of the folders that define this sampling
    folder_names::AbstractSamplingFolders # contains the paths to the folders that define this sampling

    variation_ids::Array{Int} # variation_id associated with each monad
    rulesets_variation_ids::Array{Int} # rulesets_variation_id associated with each monad

    # addon_macros::AddonMacros # addon macros for this simulation

    function Sampling(id, monad_min_length, monad_ids, folder_ids, folder_names, variation_ids, rulesets_variation_ids) # , addon_macros)
        n_monads = length(monad_ids)
        n_variations = length(variation_ids)
        n_rulesets_variations = length(rulesets_variation_ids)
        if n_monads != n_variations || n_monads != n_rulesets_variations # the negation of this is n_monads == n_variations && n_monads == n_rulesets_variations, which obviously means they're all the same
            throw(ArgumentError("Number of monads, variations, and rulesets variations must be the same"))
        end
        return new(id, monad_min_length, monad_ids, folder_ids, folder_names, variation_ids, rulesets_variation_ids) # , addon_macros)
    end
end

Base.size(sampling::Sampling) = size(sampling.monad_ids)

function Monad(sampling::Sampling, index::Int)
    return Monad(sampling.monad_min_length, sampling.folder_ids, sampling.folder_names, sampling.variation_ids[index], sampling.rulesets_variation_ids[index]) # ; addon_macros=nothing)
end

function Sampling(monad_min_length::Int, base_config_id::Int, rulesets_collection_id::Int, ic_substrate_id::Int, ic_ecm_id::Int, custom_code_id::Int, variation_ids::Array{Int}, rulesets_variation_ids::Array{Int}) # ; addon_macros::AddonMacros=AddonMacros())
    folder_ids = AbstractSamplingIDs(base_config_id, rulesets_collection_id, ic_cell_id, ic_substrate_id, ic_ecm_id, custom_code_id)
    return Sampling(monad_min_length, folder_ids, variation_ids, rulesets_variation_ids) # ; addon_macros=addon_macros)
end

function Sampling(monad_min_length::Int, folder_ids::AbstractSamplingIDs, variation_ids::Array{Int}, rulesets_variation_ids::Array{Int}; 
    )
    folder_names = AbstractSamplingFolders(folder_ids)
    return Sampling(monad_min_length, folder_ids, folder_names, variation_ids, rulesets_variation_ids) # ; addon_macros=addon_macros)
end

function Sampling(monad_min_length::Int, base_config_folder::String, rulesets_collection_folder::String, ic_cell_folder::String, ic_substrate_folder::String, ic_ecm_folder::String, custom_code_folder::String, variation_ids::Array{Int}, rulesets_variation_ids::Array{Int}) # ; addon_macros::AddonMacros=AddonMacros())
    folder_names = AbstractSamplingFolders(base_config_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder, custom_code_folder)
    return Sampling(monad_min_length, folder_names, variation_ids, rulesets_variation_ids) # ; addon_macros=addon_macros)
end

function Sampling(monad_min_length::Int, folder_names::AbstractSamplingFolders, variation_ids::Array{Int}, rulesets_variation_ids::Array{Int}) # ; addon_macros::AddonMacros=AddonMacros())  
    folder_ids = AbstractSamplingIDs(folder_names)
    return Sampling(monad_min_length, folder_ids, folder_names, variation_ids, rulesets_variation_ids) # ; addon_macros=addon_macros)
end

function Sampling(id::Int, monad_min_length::Int, folder_ids::AbstractSamplingIDs, folder_names::AbstractSamplingFolders, variation_ids::Array{Int}, rulesets_variation_ids::Array{Int}) # ; addon_macros::AddonMacros=AddonMacros())
    monad_ids = createMonadIDs(monad_min_length, folder_ids, folder_names, variation_ids, rulesets_variation_ids)
    return Sampling(id, monad_min_length, monad_ids, folder_ids, folder_names, variation_ids, rulesets_variation_ids) # , addon_macros)
end

function Sampling(monad_min_length::Int, folder_ids::AbstractSamplingIDs, folder_names::AbstractSamplingFolders, variation_ids::Array{Int}, rulesets_variation_ids::Array{Int}) # ; addon_macros::AddonMacros=AddonMacros())
    monad_ids = createMonadIDs(monad_min_length, folder_ids, folder_names, variation_ids, rulesets_variation_ids)
    
    id = -1
    sampling_ids = DBInterface.execute(db, "SELECT sampling_id FROM samplings WHERE (base_config_id,rulesets_collection_id,ic_cell_id,ic_substrate_id,ic_ecm_id,custom_code_id)=($(folder_ids.base_config_id),$(folder_ids.rulesets_collection_id),$(folder_ids.ic_cell_id),$(folder_ids.ic_substrate_id),$(folder_ids.ic_ecm_id),$(folder_ids.custom_code_id));") |> DataFrame |> x -> x.sampling_id
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
        id = DBInterface.execute(db, "INSERT INTO samplings (base_config_id,rulesets_collection_id,ic_cell_id,ic_substrate_id,ic_ecm_id,custom_code_id) VALUES($(folder_ids.base_config_id),$(folder_ids.rulesets_collection_id),$(folder_ids.ic_cell_id),$(folder_ids.ic_substrate_id),$(folder_ids.ic_ecm_id),$(folder_ids.custom_code_id)) RETURNING sampling_id;") |> DataFrame |> x -> x.sampling_id[1] # get the sampling_id
    end
    return Sampling(id, monad_min_length, monad_ids, folder_ids, folder_names, variation_ids, rulesets_variation_ids) # , addon_macros)
end

function createMonadIDs(monad_min_length::Int, folder_ids::AbstractSamplingIDs, folder_names::AbstractSamplingFolders, variation_ids::Vector{Int}, rulesets_variation_ids::Vector{Int})
    _size = size(variation_ids)
    monad_ids = -ones(Int, _size)
    
    for i in eachindex(monad_ids)
        monad = Monad(monad_min_length, folder_ids, folder_names, variation_ids[i], rulesets_variation_ids[i])
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

    folder_ids::Vector{AbstractSamplingIDs} # contains the ids of the folders that define this trial
    folder_names::Vector{AbstractSamplingFolders} # contains the paths to the folders that define this trial

    variation_ids::Vector{Vector{Int}} # variation_id associated with each monad for each sampling
    rulesets_variation_ids::Vector{Vector{Int}} # rulesets_variation_id associated with each monad for each sampling

    # addon_macros::Vector{AddonMacros} # addon macros for each sampling

    function Trial(id::Int, monad_min_length::Int, sampling_ids::Vector{Int}, folder_ids::Vector{AbstractSamplingIDs}, folder_names::Vector{AbstractSamplingFolders}, variation_ids::Vector{Vector{Int}}, rulesets_variation_ids::Vector{Vector{Int}}) # , addon_macros::Vector{AddonMacros})
        n_samplings = length(sampling_ids)
        n_folder_ids = length(folder_ids)
        n_folder_names = length(folder_names)
        n_variations = length(variation_ids)
        n_rulesets_variations = length(rulesets_variation_ids)
        if n_samplings != n_folder_ids || n_samplings != n_folder_names || n_samplings != n_variations || n_samplings != n_rulesets_variations # the negation of this is n_samplings == n_folder_ids && n_samplings == n_folder_names && n_samplings == n_variations && n_samplings == n_rulesets_variations, which obviously means they're all the same
            throw(ArgumentError("Number of samplings, folder ids, folder names, variations, and rulesets variations must be the same"))
        end

        return new(id, monad_min_length, sampling_ids, folder_ids, folder_names, variation_ids, rulesets_variation_ids) # , addon_macros)
    end
end

Base.size(trial::Trial) = size(trial.sampling_ids)

function Sampling(trial::Trial, index::Int)
    return Sampling(trial.sampling_ids[index], trial.monad_min_length, trial.folder_ids[index], trial.folder_names[index], trial.variation_ids[index], trial.rulesets_variation_ids[index]) # ; addon_macros=trial.addon_macros[index])
end

function Trial(monad_min_length::Int, base_config_ids::Vector{Int}, rulesets_collection_ids::Vector{Int}, ic_cell_ids::Vector{Int}, ic_substrate_ids::Vector{Int}, ic_ecm_ids::Vector{Int}, custom_code_ids::Vector{Int}, variation_ids::Vector{Vector{Int}}, rulesets_variation_ids::Vector{Vector{Int}}) # ; addon_macros::Vector{AddonMacros}=fill(AddonMacros(), length(base_config_ids)))
    folder_ids = [AbstractSamplingIDs(base_config_id, rulesets_collection_id, ic_cell_id, ic_substrate_id, ic_ecm_id, custom_code_id) for (base_config_id, rulesets_collection_id, ic_cell_id, ic_substrate_id, ic_ecm_id, custom_code_id) in zip(base_config_ids, rulesets_collection_ids, ic_cell_ids, ic_substrate_ids, ic_ecm_ids, custom_code_ids)]
    return Trial(monad_min_length, folder_ids, variation_ids, rulesets_variation_ids) # ; addon_macros=addon_macros)
end

function Trial(monad_min_length::Int, folder_ids::Vector{AbstractSamplingIDs}, variation_ids::Vector{Vector{Int}}, rulesets_variation_ids::Vector{Vector{Int}}) # ; addon_macros::Vector{AddonMacros}=fill(AddonMacros(), length(folder_ids)))
    folder_names = [AbstractSamplingFolders(folder_id) for folder_id in folder_ids]
    return Trial(monad_min_length, folder_ids, folder_names, variation_ids, rulesets_variation_ids) # ; addon_macros=addon_macros)
end

function Trial(monad_min_length::Int, base_config_folders::Vector{String}, rulesets_collection_folders::Vector{String}, ic_cell_folders::Vector{String}, ic_substrate_folders::Vector{String}, ic_ecm_folders::Vector{String}, custom_code_folders::Vector{String}, variation_ids::Vector{Vector{Int}}, rulesets_variation_ids::Vector{Vector{Int}}) # ; addon_macros::Vector{AddonMacros}=fill(AddonMacros(), length(base_config_folders)))
    folder_names = [AbstractSamplingFolders(base_config_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder, custom_code_folder) for (base_config_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder, custom_code_folder) in zip(base_config_folders, rulesets_collection_folders, ic_cell_folders, ic_substrate_folders, ic_ecm_folders, custom_code_folders)]
    return Trial(monad_min_length, folder_names, variation_ids, rulesets_variation_ids) # ; addon_macros=addon_macros)
end

function Trial(id::Int, monad_min_length::Int, folder_names::Vector{AbstractSamplingFolders}, variation_ids::Vector{Vector{Int}}, rulesets_variation_ids::Vector{Vector{Int}}) # ; addon_macros::Vector{AddonMacros}=fill(AddonMacros(), length(folder_names)))
    folder_ids = [AbstractSamplingIDs(folder_name) for folder_name in folder_names]
    return Trial(monad_min_length, folder_ids, folder_names, variation_ids, rulesets_variation_ids) # ; addon_macros=addon_macros)
end

function Trial(monad_min_length::Int, folder_ids, folder_names, variation_ids::Vector{Vector{Int}}, rulesets_variation_ids::Vector{Vector{Int}}) # ; addon_macros::Vector{AddonMacros}=fill(AddonMacros(), length(folder_ids)))
    sampling_ids = createSamplingIDs(monad_min_length, folder_ids, folder_names, variation_ids, rulesets_variation_ids)
    id = getTrialId(sampling_ids)

    return Trial(id, monad_min_length, sampling_ids, folder_ids, folder_names, variation_ids, rulesets_variation_ids) # , addon_macros)
end

function createSamplingIDs(monad_min_length::Int, folder_ids::Vector{AbstractSamplingIDs}, folder_names::Vector{AbstractSamplingFolders}, variation_ids::Vector{Vector{Int}}, rulesets_variation_ids::Vector{Vector{Int}})
    _size = size(folder_ids)
    sampling_ids = -ones(Int, _size)
    
    for i in eachindex(sampling_ids)
        sampling = Sampling(monad_min_length, folder_ids[i], folder_names[i], variation_ids[i], rulesets_variation_ids[i])
        sampling_ids[i] = sampling.id
    end
    return sampling_ids
end

function getTrialId(sampling_ids::Vector{Int})
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

    return id
end

function Trial(samplings::Vector{Sampling})
    monad_min_length = samplings[1].monad_min_length
    sampling_ids = [sampling.id for sampling in samplings]
    folder_ids = [sampling.folder_ids for sampling in samplings]
    folder_names = [sampling.folder_names for sampling in samplings]
    variation_ids = [sampling.variation_ids for sampling in samplings]
    rulesets_variation_ids = [sampling.rulesets_variation_ids for sampling in samplings]
    # addon_macros = [sampling.addon_macros for sampling in samplings]
    return Trial(monad_min_length, sampling_ids, folder_ids, folder_names, variation_ids, rulesets_variation_ids) # ; addon_macros=addon_macros)
end

function Trial(monad_min_length::Int, sampling_ids::Vector{Int}, folder_ids::Vector{AbstractSamplingIDs}, folder_names::Vector{AbstractSamplingFolders}, variation_ids::Vector{Vector{Int}}, rulesets_variation_ids::Vector{Vector{Int}}) # ; addon_macros::Vector{AddonMacros}=fill(AddonMacros(), length(sampling_ids)))
    id = getTrialId(sampling_ids)
    return Trial(id, monad_min_length, sampling_ids, folder_ids, folder_names, variation_ids, rulesets_variation_ids) # , addon_macros)
end

function Trial(trial_id::Int; full_initialization::Bool=false)
    df = DBInterface.execute(db, "SELECT * FROM trials WHERE trial_id=$trial_id;") |> DataFrame
    if isempty(df) || isempty(getTrialSamplings(trial_id))
        error("No samplings found for trial_id=$trial_id. This trial did not run.")
    end
    if full_initialization
        error("Full initialization of Trials from trial_id not yet implemented")
        sampling_ids = getTrialSamplings(trial_id)
        monad_min_length = minimum([getSamplingMonads(sampling_id) for sampling_id in sampling_ids])
        sampling_df = DBInterface.execute(db, "SELECT * FROM samplings WHERE sampling_id IN ($(join(sampling_ids,",")))") |> DataFrame
        folder_ids = [getSamplingFolderIDs(sampling_id) for sampling_id in sampling_ids]
        folder_names = [getSamplingFolderNames(sampling_id) for sampling_id in sampling_ids]
        variation_ids = [getSamplingVariationIDs(sampling_id) for sampling_id in sampling_ids]
        rulesets_variation_ids = [getSamplingRulesetsVariationIDs(sampling_id) for sampling_id in sampling_ids]
    else
        monad_min_length = 0
        sampling_ids = Int[]
        folder_ids = AbstractSamplingIDs[]
        folder_names = AbstractSamplingFolders[]
        variation_ids = Vector{Int}[]
        rulesets_variation_ids = Vector{Int}[]
    end
    return Trial(trial_id, monad_min_length, sampling_ids, folder_ids, folder_names, variation_ids, rulesets_variation_ids) # , addon_macros)
end