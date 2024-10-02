export Simulation, Monad, Sampling, Trial, getTrial, VCTClassID

abstract type AbstractTrial end
abstract type AbstractSampling <: AbstractTrial end
abstract type AbstractMonad <: AbstractSampling end

Base.length(T::AbstractTrial) = getSimulationIDs(T) |> length

##########################################
########   AbstractSamplingIDs   #########
##########################################

"""
`struct AbstractSamplingIDs`

A struct representing various IDs used for sampling in the VCT environment.

# Fields
- `config_id::Int`: Integer identifying the base configuration folder ID for lookup in the database.
- `rulesets_collection_id::Int`: Integer identifying which rulesets collection to use as a framework.
- `ic_cell_id::Int`: Integer identifying the initial condition cells folder for lookup in the database.
- `ic_substrate_id::Int`: Integer identifying the initial condition substrate folder for lookup in the database.
- `ic_ecm_id::Int`: Integer identifying the initial condition extracellular matrix folder for lookup in the database.
- `custom_code_id::Int`: Integer identifying the custom code folder (with `{main.cpp, Makefile, custom_modules/{custom.cpp, custom.h}}` as folder structure) for lookup in the database.
"""
struct AbstractSamplingIDs
    config_id::Int # integer identifying the base configuration folder id for lookup in the db (config_$(config_id)/)
    rulesets_collection_id::Int # integer identifying which rulesets collection to use as a framework
    ic_cell_id::Int # integer identifying the ic cells folder for lookup in the db
    ic_substrate_id::Int # integer identifying the ic substrate folder for lookup in the db
    ic_ecm_id::Int # integer identifying the ic ecm folder for lookup in the db
    custom_code_id::Int # integer identifyng the custom code folder (with {main.cpp,Makefile,custom_modules/{custom.cpp,custom.h}} as folder structure) for lookup in the db

    function AbstractSamplingIDs(config_id::Int, rulesets_collection_id::Int, ic_cell_id::Int, ic_substrate_id::Int, ic_ecm_id::Int, custom_code_id::Int)
        @assert config_id > 0 "config_id must be positive"
        return new(config_id, rulesets_collection_id, ic_cell_id, ic_substrate_id, ic_ecm_id, custom_code_id)
    end
end

##########################################
######   AbstractSamplingFolders   #######
##########################################

"""
`AbstractSamplingFolders`

A structure representing the folders used for sampling in a VCT (Virtual Cell Technology) environment.

# Fields
- `config_folder::String`: Name of the configuration folder.
- `rulesets_collection_folder::String`: Name of the rulesets collection folder.
- `ic_cell_folder::String`: Name of the initial condition (IC) cells folder.
- `ic_substrate_folder::String`: Name of the initial condition (IC) substrate folder.
- `ic_ecm_folder::String`: Name of the initial condition (IC) extracellular matrix (ECM) folder.
- `custom_code_folder::String`: Name of the custom code folder.
"""
struct AbstractSamplingFolders
    config_folder::String # name of config folder
    rulesets_collection_folder::String # name of rulesets collection folder
    ic_cell_folder::String # name of ic cells folder
    ic_substrate_folder::String # name of ic substrate folder
    ic_ecm_folder::String # name of ic ecm folder
    custom_code_folder::String # name of custom code folder

    function AbstractSamplingFolders(config_folder::String, rulesets_collection_folder::String, ic_cell_folder::String, ic_substrate_folder::String, ic_ecm_folder::String, custom_code_folder::String)
        @assert config_folder != "" "config_folder must be provided"
        return new(config_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder, custom_code_folder)
    end
end

function AbstractSamplingFolders(ids::AbstractSamplingIDs)
    config_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder, custom_code_folder = retrievePathInfo(ids.config_id, ids.rulesets_collection_id, ids.ic_cell_id, ids.ic_substrate_id, ids.ic_ecm_id, ids.custom_code_id)
    return AbstractSamplingFolders(config_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder, custom_code_folder)
end

function AbstractSamplingIDs(folder_names::AbstractSamplingFolders)
    return AbstractSamplingIDs(retrieveID(folder_names)...)
end

##########################################
#############   Simulation   #############
##########################################

struct Simulation <: AbstractMonad
    id::Int # integer uniquely identifying this simulation

    folder_ids::AbstractSamplingIDs # contains the ids of the folders that define this simulation
    folder_names::AbstractSamplingFolders # contains the paths to the folders that define this simulation
    
    variation_id::Int # integer identifying which variation on the base config file to use (variations.db)
    rulesets_variation_id::Int # integer identifying which variation on the ruleset file to use (rulesets_variations.db)

    function Simulation(id::Int, folder_ids::AbstractSamplingIDs, folder_names::AbstractSamplingFolders, variation_id::Int, rulesets_variation_id::Int)
        @assert id > 0 "id must be positive"
        @assert variation_id >= 0 "variation_id must be non-negative"
        @assert rulesets_variation_id >= -1 "rulesets_variation_id must be non-negative or -1 (indicating no rules)"
        if rulesets_variation_id != -1
            @assert folder_names.rulesets_collection_folder != "" "rulesets_collection_folder must be provided if rulesets_variation_id is not -1 (indicating that the rules are in use)"
        end
        return new(id, folder_ids, folder_names, variation_id, rulesets_variation_id)
    end
end

function Simulation(folder_ids::AbstractSamplingIDs, folder_names::AbstractSamplingFolders, variation_id::Int, rulesets_variation_id::Int) 
    simulation_id = DBInterface.execute(db, "INSERT INTO simulations (config_id,rulesets_collection_id,ic_cell_id,ic_substrate_id,ic_ecm_id,custom_code_id,variation_id,rulesets_variation_id,status_code_id) VALUES($(folder_ids.config_id),$(folder_ids.rulesets_collection_id),$(folder_ids.ic_cell_id),$(folder_ids.ic_substrate_id),$(folder_ids.ic_ecm_id),$(folder_ids.custom_code_id),$(variation_id),$(rulesets_variation_id),'$(getStatusCodeID("Not Started"))') RETURNING simulation_id;") |> DataFrame |> x -> x.simulation_id[1]
    return Simulation(simulation_id, folder_ids, folder_names, variation_id, rulesets_variation_id)
end

function Simulation(folder_ids::AbstractSamplingIDs, variation_id::Int, rulesets_variation_id::Int)
    folder_names = AbstractSamplingFolders(folder_ids)
    return Simulation(folder_ids, folder_names, variation_id, rulesets_variation_id)
end

function Simulation(config_id::Int, rulesets_collection_id::Int, ic_cell_id::Int, ic_substrate_id::Int, ic_ecm_id::Int, custom_code_id::Int, variation_id::Int, rulesets_variation_id::Int) 
    folder_ids = AbstractSamplingIDs(config_id, rulesets_collection_id, ic_cell_id, ic_substrate_id, ic_ecm_id, custom_code_id)
    folder_names  = AbstractSamplingFolders(folder_ids)
    return Simulation(folder_ids, folder_names, variation_id, rulesets_variation_id)
end

function Simulation(config_folder::String, rulesets_collection_folder::String, ic_cell_folder::String, ic_substrate_folder::String, ic_ecm_folder::String, custom_code_folder::String, variation_id::Int, rulesets_variation_id::Int) 
    folder_names = AbstractSamplingFolders(config_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder, custom_code_folder)
    folder_ids = AbstractSamplingIDs(folder_names)
    return Simulation(folder_ids, folder_names, variation_id, rulesets_variation_id)
end

function Simulation(; config_folder::String="", rulesets_collection_folder::String="", ic_cell_folder::String="", ic_substrate_folder::String="", ic_ecm_folder::String="", custom_code_folder::String="", variation_id::Int=-1, rulesets_variation_id::Int=-1)
    folder_names = AbstractSamplingFolders(config_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder, custom_code_folder)
    folder_ids = AbstractSamplingIDs(folder_names)
    return Simulation(folder_ids, folder_names, variation_id, rulesets_variation_id)
end

function getSimulation(simulation_id::Int)
    df = constructSelectQuery("simulations", "WHERE simulation_id=$(simulation_id);") |> queryToDataFrame
    if isempty(df)
        error("No simulations found for simulation_id=$simulation_id. This simulation has not been created yet.")
    end
    folder_ids = AbstractSamplingIDs(df.config_id[1], df.rulesets_collection_id[1], df.ic_cell_id[1], df.ic_substrate_id[1], df.ic_ecm_id[1], df.custom_code_id[1])
    folder_names = AbstractSamplingFolders(folder_ids)
    variation_id = df.variation_id[1]
    rulesets_variation_id = df.rulesets_variation_id[1]
    return Simulation(simulation_id, folder_ids, folder_names, variation_id, rulesets_variation_id)
end

Simulation(simulation_id::Int) = getSimulation(simulation_id)

Base.length(simulation::Simulation) = 1

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

    variation_id::Int # integer identifying which variation on the base config file to use (variations_$(config_id).db)
    rulesets_variation_id::Int # integer identifying which variation on the ruleset file to use (rulesets_variations_$(ruleset_id).db)

    function Monad(id::Int, min_length::Int, simulation_ids::Vector{Int}, folder_ids::AbstractSamplingIDs, folder_names::AbstractSamplingFolders, variation_id::Int, rulesets_variation_id::Int)
        @assert id > 0 "id must be positive"
        @assert min_length >= 0 "min_length must be non-negative"
        @assert all(simulation_id -> simulation_id > 0, simulation_ids) "simulation_ids must all be positive"
        @assert variation_id >= 0 "variation_id must be non-negative"
        @assert rulesets_variation_id >= -1 "rulesets_variation_id must be non-negative or -1 (indicating no rules)"
        if rulesets_variation_id != -1
            @assert folder_names.rulesets_collection_folder != "" "rulesets_collection_folder must be provided if rulesets_variation_id is not -1 (indicating that the rules are in use)"
        end

        # this could be done when adding new simulation ids to save some fie I/O
        # doing it here just to make sure it is always up to date (and for consistency across classes)
        recordSimulationIDs(id, simulation_ids) # record the simulation ids in a .csv file

        return new(id, min_length, simulation_ids, folder_ids, folder_names, variation_id, rulesets_variation_id)
    end
end

function Monad(min_length::Int, folder_ids::AbstractSamplingIDs, folder_names::AbstractSamplingFolders, variation_id::Int, rulesets_variation_id::Int; use_previous_simulations::Bool=true) 
    monad_ids = DBInterface.execute(db, "INSERT OR IGNORE INTO monads (config_id,rulesets_collection_id,ic_cell_id,ic_substrate_id,ic_ecm_id,custom_code_id,variation_id,rulesets_variation_id) VALUES($(folder_ids.config_id),$(folder_ids.rulesets_collection_id),$(folder_ids.ic_cell_id),$(folder_ids.ic_substrate_id),$(folder_ids.ic_ecm_id),$(folder_ids.custom_code_id),$(variation_id),$(rulesets_variation_id)) RETURNING monad_id;") |> DataFrame |> x -> x.monad_id
    if isempty(monad_ids) # if monad insert command was ignored, then the monad already exists
        monad_id = constructSelectQuery(
            "monads",
            """
            WHERE (config_id,rulesets_collection_id,ic_cell_id,ic_substrate_id,ic_ecm_id,custom_code_id,variation_id,rulesets_variation_id)=\
            (\
                $(folder_ids.config_id),$(folder_ids.rulesets_collection_id),$(folder_ids.ic_cell_id),$(folder_ids.ic_substrate_id),$(folder_ids.ic_ecm_id),$(folder_ids.custom_code_id),$(variation_id),$(rulesets_variation_id)\
            );\
            """,
            selection="monad_id"
        ) |> queryToDataFrame |> x -> x.monad_id[1] # get the monad_id
    else # if monad insert command was successful, then the monad is new
        monad_id = monad_ids[1] # get the monad_id
    end
    simulation_ids = use_previous_simulations ? readMonadSimulationIDs(monad_id) : Int[]
    if min_length - length(simulation_ids) > 0
        for _ = 1:(min_length - length(simulation_ids))
            simulation = Simulation(folder_ids, folder_names, variation_id, rulesets_variation_id) # create a new simulation
            push!(simulation_ids, simulation.id) # add the simulation id to the monad
        end
    end
    return Monad(monad_id, min_length, simulation_ids, folder_ids, folder_names, variation_id, rulesets_variation_id) # return the monad
end

function Monad(min_length::Int, folder_ids::AbstractSamplingIDs, variation_id::Int, rulesets_variation_id::Int; use_previous_simulations::Bool=true)
    folder_names = AbstractSamplingFolders(folder_ids)
    return Monad(min_length, folder_ids, folder_names, variation_id, rulesets_variation_id; use_previous_simulations=use_previous_simulations)
end

function Monad(min_length::Int, folder_names::AbstractSamplingFolders, variation_id::Int, rulesets_variation_id::Int; use_previous_simulations::Bool=true) 
    folder_ids = AbstractSamplingIDs(folder_names)
    return Monad(min_length, folder_ids, folder_names, variation_id, rulesets_variation_id; use_previous_simulations=use_previous_simulations)
end

function Monad(folder_names::AbstractSamplingFolders, variation_id::Int, rulesets_variation_id::Int; use_previous_simulations::Bool=true)
    min_length = 0 # not making a monad to run if not supplying the min_length info
    Monad(min_length, folder_names, variation_id, rulesets_variation_id; use_previous_simulations=use_previous_simulations)
end

function Monad(min_length::Int, config_id::Int, rulesets_collection_id::Int, ic_cell_id::Int, ic_substrate_id::Int, ic_ecm_id::Int, custom_code_id::Int, variation_id::Int, rulesets_variation_id::Int; use_previous_simulations::Bool=true)
    folder_ids = AbstractSamplingIDs(config_id, rulesets_collection_id, ic_cell_id, ic_substrate_id, ic_ecm_id, custom_code_id)
    return Monad(min_length, folder_ids, variation_id, rulesets_variation_id; use_previous_simulations=use_previous_simulations)
end

function Monad(min_length::Int, config_folder::String, rulesets_collection_folder::String, ic_cell_folder::String, ic_substrate_folder::String, ic_ecm_folder::String, custom_code_folder::String, variation_id::Int, rulesets_variation_id::Int; use_previous_simulations::Bool=true)
    folder_names = AbstractSamplingFolders(config_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder, custom_code_folder)
    return Monad(min_length, folder_names, variation_id, rulesets_variation_id; use_previous_simulations=use_previous_simulations)
end

function Monad(; min_length::Int=0, config_folder::String="", rulesets_collection_folder::String="", ic_cell_folder::String="", ic_substrate_folder::String="", ic_ecm_folder::String="", custom_code_folder::String="", variation_id::Int=-1, rulesets_variation_id::Int=-1, use_previous_simulations::Bool=true)
    folder_names = AbstractSamplingFolders(config_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder, custom_code_folder)
    return Monad(min_length, folder_names, variation_id, rulesets_variation_id; use_previous_simulations=use_previous_simulations)
end

function getMonad(monad_id::Int)
    df = constructSelectQuery("monads", "WHERE monad_id=$(monad_id);") |> queryToDataFrame
    simulation_ids = readMonadSimulationIDs(monad_id)
    if isempty(df) || isempty(simulation_ids)
        error("No monads found for monad_id=$monad_id. This monad did not run.")
    end
    min_length = 0
    folder_ids = AbstractSamplingIDs(df.config_id[1], df.rulesets_collection_id[1], df.ic_cell_id[1], df.ic_substrate_id[1], df.ic_ecm_id[1], df.custom_code_id[1])
    folder_names = AbstractSamplingFolders(folder_ids)
    variation_id = df.variation_id[1]
    rulesets_variation_id = df.rulesets_variation_id[1]
    return Monad(monad_id, min_length, simulation_ids, folder_ids, folder_names, variation_id, rulesets_variation_id)
end

Monad(monad_id::Int) = getMonad(monad_id)

function Simulation(monad::Monad)
    return Simulation(monad.folder_ids, monad.folder_names, monad.variation_id, monad.rulesets_variation_id)
end

function Monad(simulation::Simulation)
    min_length = 0 # do not impose a min length on this monad
    monad = Monad(min_length, simulation.folder_ids, simulation.folder_names, simulation.variation_id, simulation.rulesets_variation_id)
    addSimulationID!(monad, simulation.id)
    return monad
end

function addSimulationID!(monad::Monad, simulation_id::Int)
    if simulation_id in monad.simulation_ids
        return monad
    end
    push!(monad.simulation_ids, simulation_id)
    recordSimulationIDs(monad.id, monad.simulation_ids)
    return
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

    function Sampling(id, monad_min_length, monad_ids, folder_ids, folder_names, variation_ids, rulesets_variation_ids)
        @assert id > 0 "id must be positive"
        @assert monad_min_length >= 0 "monad_min_length must be non-negative"
        @assert all(monad_id -> monad_id > 0, monad_ids) "monad_ids must all be positive"
        @assert all(variation_id -> variation_id >= 0, variation_ids) "variation_ids must all be non-negative integers"
        @assert all(rulesets_variation_id -> rulesets_variation_id >= -1, rulesets_variation_ids) "rulesets_variation_ids must all be non-negative integers or -1 (indicating no rules)"
        if folder_names.rulesets_collection_folder == ""
            @assert all(rulesets_variation_id -> rulesets_variation_id == -1, rulesets_variation_ids) "rulesets_collection_folder must be provided if any rulesets_variation_id is not -1 (indicating that the rules are in use)"
        end
        n_monads = length(monad_ids)
        n_variations = length(variation_ids)
        n_rulesets_variations = length(rulesets_variation_ids)
        if n_monads != n_variations || n_monads != n_rulesets_variations # the negation of this is n_monads == n_variations && n_monads == n_rulesets_variations, which obviously means they're all the same
            error_message = """
                Number of monads, variations, and rulesets variations must be the same
                \tn_monads = $n_monads
                \tn_variations = $n_variations
                \tn_rulesets_variations = $n_rulesets_variations
            """
            throw(ArgumentError(error_message))
        end
        recordMonadIDs(id, monad_ids) # record the monad ids in a .csv file
        return new(id, monad_min_length, monad_ids, folder_ids, folder_names, variation_ids, rulesets_variation_ids)
    end
end

function Sampling(monad_min_length::Int, monad_ids::Array{Int}, folder_ids::AbstractSamplingIDs, folder_names::AbstractSamplingFolders, variation_ids::Array{Int}, rulesets_variation_ids::Array{Int}; use_previous_simulations::Bool=true)
    id = -1
    sampling_ids = constructSelectQuery(
        "samplings",
        """
        WHERE (config_id,rulesets_collection_id,ic_cell_id,ic_substrate_id,ic_ecm_id,custom_code_id)=\
        (\
            $(folder_ids.config_id),$(folder_ids.rulesets_collection_id),$(folder_ids.ic_cell_id),$(folder_ids.ic_substrate_id),$(folder_ids.ic_ecm_id),$(folder_ids.custom_code_id)\
        );\
        """,
        selection="sampling_id"
    ) |> queryToDataFrame |> x -> x.sampling_id
    if !isempty(sampling_ids) # if there are previous samplings with the same parameters
        for sampling_id in sampling_ids # check if the monad_ids are the same with any previous monad_ids
            monad_ids_in_db = readSamplingMonadIDs(sampling_id) # get the monad_ids belonging to this sampling
            if symdiff(monad_ids_in_db, monad_ids) |> isempty # if the monad_ids are the same
                id = sampling_id # use the existing sampling_id
                break
            end
        end
    end
    
    if id==-1 # if no previous sampling was found matching these parameters
        id = DBInterface.execute(db, "INSERT INTO samplings (config_id,rulesets_collection_id,ic_cell_id,ic_substrate_id,ic_ecm_id,custom_code_id) VALUES($(folder_ids.config_id),$(folder_ids.rulesets_collection_id),$(folder_ids.ic_cell_id),$(folder_ids.ic_substrate_id),$(folder_ids.ic_ecm_id),$(folder_ids.custom_code_id)) RETURNING sampling_id;") |> DataFrame |> x -> x.sampling_id[1] # get the sampling_id
    end
    return Sampling(id, monad_min_length, monad_ids, folder_ids, folder_names, variation_ids, rulesets_variation_ids)
end

function Sampling(id::Int, monad_min_length::Int, folder_ids::AbstractSamplingIDs, folder_names::AbstractSamplingFolders, variation_ids::Array{Int}, rulesets_variation_ids::Array{Int}; use_previous_simulations::Bool=true)
    monad_ids = createMonadIDs(monad_min_length, folder_ids, folder_names, variation_ids, rulesets_variation_ids; use_previous_simulations=use_previous_simulations)
    return Sampling(id, monad_min_length, monad_ids, folder_ids, folder_names, variation_ids, rulesets_variation_ids)
end

function Sampling(monad_min_length::Int, folder_ids::AbstractSamplingIDs, folder_names::AbstractSamplingFolders, variation_ids::Array{Int}, rulesets_variation_ids::Array{Int}; use_previous_simulations::Bool=true)
    monad_ids = createMonadIDs(monad_min_length, folder_ids, folder_names, variation_ids, rulesets_variation_ids; use_previous_simulations=use_previous_simulations)
    return Sampling(monad_min_length, monad_ids, folder_ids, folder_names, variation_ids, rulesets_variation_ids)
end

function Sampling(monad_min_length::Int, folder_ids::AbstractSamplingIDs, variation_ids::Array{Int}, rulesets_variation_ids::Array{Int}; use_previous_simulations::Bool=true)
    folder_names = AbstractSamplingFolders(folder_ids)
    return Sampling(monad_min_length, folder_ids, folder_names, variation_ids, rulesets_variation_ids; use_previous_simulations=use_previous_simulations)
end

function Sampling(monad_min_length::Int, folder_names::AbstractSamplingFolders, variation_ids::Array{Int}, rulesets_variation_ids::Array{Int}; use_previous_simulations::Bool=true)
    folder_ids = AbstractSamplingIDs(folder_names)
    return Sampling(monad_min_length, folder_ids, folder_names, variation_ids, rulesets_variation_ids; use_previous_simulations=use_previous_simulations)
end

function Sampling(monad_min_length::Int, config_id::Int, rulesets_collection_id::Int, ic_cell_id::Int, ic_substrate_id::Int, ic_ecm_id::Int, custom_code_id::Int, variation_ids::Array{Int}, rulesets_variation_ids::Array{Int}; use_previous_simulations::Bool=true)
    folder_ids = AbstractSamplingIDs(config_id, rulesets_collection_id, ic_cell_id, ic_substrate_id, ic_ecm_id, custom_code_id)
    return Sampling(monad_min_length, folder_ids, variation_ids, rulesets_variation_ids; use_previous_simulations=use_previous_simulations)
end

function Sampling(monad_min_length::Int, config_folder::String, rulesets_collection_folder::String, ic_cell_folder::String, ic_substrate_folder::String, ic_ecm_folder::String, custom_code_folder::String, variation_ids::Array{Int}, rulesets_variation_ids::Array{Int}; use_previous_simulations::Bool=true)
    folder_names = AbstractSamplingFolders(config_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder, custom_code_folder)
    return Sampling(monad_min_length, folder_names, variation_ids, rulesets_variation_ids; use_previous_simulations=use_previous_simulations)
end

function Sampling(; monad_min_length::Int=0, config_folder::String="", rulesets_collection_folder::String="", ic_cell_folder::String="", ic_substrate_folder::String="", ic_ecm_folder::String="", custom_code_folder::String="", variation_ids::Array{Int}=[], rulesets_variation_ids::Array{Int}=fill(-1, size(variation_ids)), use_previous_simulations::Bool=true)
    folder_names = AbstractSamplingFolders(config_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder, custom_code_folder)
    folder_ids = AbstractSamplingIDs(folder_names)
    return Sampling(monad_min_length, folder_ids, folder_names, variation_ids, rulesets_variation_ids; use_previous_simulations=use_previous_simulations)
end

function Sampling(monad_min_length::Int, monads::Array{<:AbstractMonad})
    folder_ids = monads[1].folder_ids
    for monad in monads
        if monad.folder_ids != folder_ids
            error("All monads must have the same folder_ids")
            # could choose to make a trial from these here...
        end
    end
    folder_names = monads[1].folder_names
    variation_ids = [monad.variation_id for monad in monads]
    rulesets_variation_ids = [monad.rulesets_variation_id for monad in monads]
    monad_ids = [monad.id for monad in monads]
    return Sampling(monad_min_length, monad_ids, folder_ids, folder_names, variation_ids, rulesets_variation_ids)
end

function createMonadIDs(monad_min_length::Int, folder_ids::AbstractSamplingIDs, folder_names::AbstractSamplingFolders, variation_ids::Vector{Int}, rulesets_variation_ids::Vector{Int}; use_previous_simulations::Bool=true)
    _size = size(variation_ids)
    monad_ids = -ones(Int, _size)
    
    for i in eachindex(monad_ids)
        monad = Monad(monad_min_length, folder_ids, folder_names, variation_ids[i], rulesets_variation_ids[i]; use_previous_simulations=use_previous_simulations)
        monad_ids[i] = monad.id
    end
    return monad_ids
end

function getSampling(sampling_id::Int)
    df = constructSelectQuery("samplings", "WHERE sampling_id=$(sampling_id);") |> queryToDataFrame
    monad_ids = readSamplingMonadIDs(sampling_id)
    if isempty(df) || isempty(monad_ids)
        error("No samplings found for sampling_id=$sampling_id. This sampling did not run.")
    end
    monad_min_length = 0 # not running more simulations for this Sampling this way
    folder_ids = AbstractSamplingIDs(df.config_id[1], df.rulesets_collection_id[1], df.ic_cell_id[1], df.ic_substrate_id[1], df.ic_ecm_id[1], df.custom_code_id[1])
    folder_names = AbstractSamplingFolders(folder_ids)
    monad_df = constructSelectQuery("monads", "WHERE monad_id IN ($(join(monad_ids,",")))") |> queryToDataFrame
    variation_ids = monad_df.variation_id
    rulesets_variation_ids = monad_df.rulesets_variation_id
    # I do not know if these will be in the proper order...
    return Sampling(sampling_id, monad_min_length, monad_ids, folder_ids, folder_names, variation_ids, rulesets_variation_ids)
end

Sampling(sampling_id::Int) = getSampling(sampling_id)

function Monad(sampling::Sampling, index::Int; use_previous_simulations::Bool=true)
    return Monad(sampling.monad_min_length, sampling.folder_ids, sampling.folder_names, sampling.variation_ids[index], sampling.rulesets_variation_ids[index]; use_previous_simulations=use_previous_simulations)
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

    function Trial(id::Int, monad_min_length::Int, sampling_ids::Vector{Int}, folder_ids::Vector{AbstractSamplingIDs}, folder_names::Vector{AbstractSamplingFolders}, variation_ids::Vector{Vector{Int}}, rulesets_variation_ids::Vector{Vector{Int}})
        @assert id > 0 "id must be positive"
        @assert monad_min_length >= 0 "monad_min_length must be non-negative"
        @assert all(sampling_id -> sampling_id > 0, sampling_ids) "sampling_ids must all be positive"
        @assert all(variation_id -> variation_id >= 0, vcat(variation_ids...)) "variation_ids must all be non-negative integers"
        @assert all(rulesets_variation_id -> rulesets_variation_id >= -1, vcat(rulesets_variation_ids...)) "rulesets_variation_ids must all be non-negative integers or -1 (indicating no rules)"
        for fn in folder_names
            if fn.rulesets_collection_folder == ""
                @assert all(rulesets_variation_id -> rulesets_variation_id == -1, vcat(rulesets_variation_ids...)) "rulesets_collection_folder must be provided if any rulesets_variation_id is not -1 (indicating that the rules are in use)"
            end
        end
        n_samplings = length(sampling_ids)
        n_folder_ids = length(folder_ids)
        n_folder_names = length(folder_names)
        n_variations = length(variation_ids)
        n_rulesets_variations = length(rulesets_variation_ids)
        if n_samplings != n_folder_ids || n_samplings != n_folder_names || n_samplings != n_variations || n_samplings != n_rulesets_variations # the negation of this is n_samplings == n_folder_ids && n_samplings == n_folder_names && n_samplings == n_variations && n_samplings == n_rulesets_variations, which obviously means they're all the same
            throw(ArgumentError("Number of samplings, folder ids, folder names, variations, and rulesets variations must be the same"))
        end

        recordSamplingIDs(id, sampling_ids) # record the sampling ids in a .csv file

        return new(id, monad_min_length, sampling_ids, folder_ids, folder_names, variation_ids, rulesets_variation_ids)
    end
end

function Trial(monad_min_length::Int, folder_ids::Vector{AbstractSamplingIDs}, folder_names::Vector{AbstractSamplingFolders}, variation_ids::Vector{Vector{Int}}, rulesets_variation_ids::Vector{Vector{Int}}; use_previous_simulations::Bool=true)
    sampling_ids = createSamplingIDs(monad_min_length, folder_ids, folder_names, variation_ids, rulesets_variation_ids; use_previous_simulations=use_previous_simulations)
    id = getTrialID(sampling_ids)
    
    return Trial(id, monad_min_length, sampling_ids, folder_ids, folder_names, variation_ids, rulesets_variation_ids)
end

function Trial(monad_min_length::Int, folder_ids::Vector{AbstractSamplingIDs}, variation_ids::Vector{Vector{Int}}, rulesets_variation_ids::Vector{Vector{Int}}; use_previous_simulations::Bool=true)
    folder_names = [AbstractSamplingFolders(folder_id) for folder_id in folder_ids]
    return Trial(monad_min_length, folder_ids, folder_names, variation_ids, rulesets_variation_ids; use_previous_simulations=use_previous_simulations)
end

function Trial(monad_min_length::Int, config_ids::Vector{Int}, rulesets_collection_ids::Vector{Int}, ic_cell_ids::Vector{Int}, ic_substrate_ids::Vector{Int}, ic_ecm_ids::Vector{Int}, custom_code_ids::Vector{Int}, variation_ids::Vector{Vector{Int}}, rulesets_variation_ids::Vector{Vector{Int}}; use_previous_simulations::Bool=true)
    folder_ids = [AbstractSamplingIDs(config_id, rulesets_collection_id, ic_cell_id, ic_substrate_id, ic_ecm_id, custom_code_id) for (config_id, rulesets_collection_id, ic_cell_id, ic_substrate_id, ic_ecm_id, custom_code_id) in zip(config_ids, rulesets_collection_ids, ic_cell_ids, ic_substrate_ids, ic_ecm_ids, custom_code_ids)]
    return Trial(monad_min_length, folder_ids, variation_ids, rulesets_variation_ids; use_previous_simulations=use_previous_simulations)
end

function Trial(monad_min_length::Int, config_folders::Vector{String}, rulesets_collection_folders::Vector{String}, ic_cell_folders::Vector{String}, ic_substrate_folders::Vector{String}, ic_ecm_folders::Vector{String}, custom_code_folders::Vector{String}, variation_ids::Vector{Vector{Int}}, rulesets_variation_ids::Vector{Vector{Int}}; use_previous_simulations::Bool=true)
    folder_names = [AbstractSamplingFolders(config_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder, custom_code_folder) for (config_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder, custom_code_folder) in zip(config_folders, rulesets_collection_folders, ic_cell_folders, ic_substrate_folders, ic_ecm_folders, custom_code_folders)]
    return Trial(monad_min_length, folder_names, variation_ids, rulesets_variation_ids; use_previous_simulations=use_previous_simulations)
end

function createSamplingIDs(monad_min_length::Int, folder_ids::Vector{AbstractSamplingIDs}, folder_names::Vector{AbstractSamplingFolders}, variation_ids::Vector{Vector{Int}}, rulesets_variation_ids::Vector{Vector{Int}}; use_previous_simulations::Bool=true)
    _size = size(folder_ids)
    sampling_ids = -ones(Int, _size)
    
    for i in eachindex(sampling_ids)
        sampling = Sampling(monad_min_length, folder_ids[i], folder_names[i], variation_ids[i], rulesets_variation_ids[i]; use_previous_simulations=use_previous_simulations)
        sampling_ids[i] = sampling.id
    end
    return sampling_ids
end

function Trial(monad_min_length::Int, sampling_ids::Vector{Int}, folder_ids::Vector{AbstractSamplingIDs}, folder_names::Vector{AbstractSamplingFolders}, variation_ids::Vector{Vector{Int}}, rulesets_variation_ids::Vector{Vector{Int}}; use_previous_simulations::Bool=true)
    id = getTrialID(sampling_ids)
    return Trial(id, monad_min_length, sampling_ids, folder_ids, folder_names, variation_ids, rulesets_variation_ids)
end

function getTrialID(sampling_ids::Vector{Int})
    id = -1
    trial_ids = constructSelectQuery("trials", "", selection="trial_id") |> queryToDataFrame |> x -> x.trial_id
    if !isempty(trial_ids) # if there are previous trials
        for trial_id in trial_ids # check if the sampling_ids are the same with any previous sampling_ids
            sampling_ids_in_db = readTrialSamplingIDs(trial_id) # get the sampling_ids belonging to this trial
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
    return Trial(monad_min_length, sampling_ids, folder_ids, folder_names, variation_ids, rulesets_variation_ids)
end

function Trial(; monad_min_length::Int=0, sampling_ids::Vector{Int}=Int[], config_folders::Vector{String}=String[], rulesets_collection_folders::Vector{String}=String[], ic_cell_folders::Vector{String}=String[], ic_substrate_folders::Vector{String}=String[], ic_ecm_folders::Vector{String}=String[], custom_code_folders::Vector{String}=String[], variation_ids::Vector{Vector{Int}}=Vector{Int}[], rulesets_variation_ids::Vector{Vector{Int}}=Vector{Int}[], use_previous_simulations::Bool=true)
    folder_names = [AbstractSamplingFolders(config_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder, custom_code_folder) for (config_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder, custom_code_folder) in zip(config_folders, rulesets_collection_folders, ic_cell_folders, ic_substrate_folders, ic_ecm_folders, custom_code_folders)]
    folder_ids = [AbstractSamplingIDs(folder_name) for folder_name in folder_names]
    return Trial(monad_min_length, sampling_ids, folder_ids, folder_names, variation_ids, rulesets_variation_ids; use_previous_simulations=use_previous_simulations)
end

function getTrial(trial_id::Int; full_initialization::Bool=false)
    df = constructSelectQuery("trials", "WHERE trial_id=$(trial_id);") |> queryToDataFrame
    if isempty(df) || isempty(readTrialSamplingIDs(trial_id))
        error("No samplings found for trial_id=$trial_id. This trial did not run.")
    end
    if full_initialization
        error("Full initialization of Trials from trial_id not yet implemented")
        sampling_ids = readTrialSamplingIDs(trial_id)
        monad_min_length = minimum([readSamplingMonadIDs(sampling_id) for sampling_id in sampling_ids])
        sampling_df = constructSelectQuery("samplings", "WHERE sampling_id IN ($(join(sampling_ids,",")))") |> queryToDataFrame
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
    return Trial(trial_id, monad_min_length, sampling_ids, folder_ids, folder_names, variation_ids, rulesets_variation_ids)
end

Trial(trial_id::Int) = getTrial(trial_id; full_initialization=false)

function Sampling(trial::Trial, index::Int)
    return Sampling(trial.sampling_ids[index], trial.monad_min_length, trial.folder_ids[index], trial.folder_names[index], trial.variation_ids[index], trial.rulesets_variation_ids[index])
end

##########################################
#############   VCTClassID   #############
##########################################

struct VCTClassID{T<:AbstractTrial} 
    id::Int
end

getVCTClassIDType(class_id::VCTClassID) = typeof(class_id).parameters[1]

function VCTClassID(class_str::String, id::Int)
    if class_str == "Simulation"
        return VCTClassID{Simulation}(id)
    elseif class_str == "Monad"
        return VCTClassID{Monad}(id)
    elseif class_str == "Sampling"
        return VCTClassID{Sampling}(id)
    elseif class_str == "Trial"
        return VCTClassID{Trial}(id)
    else
        error("class_str must be one of 'Simulation', 'Monad', 'Sampling', or 'Trial'.")
    end
end
