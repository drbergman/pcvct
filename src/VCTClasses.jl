export Simulation, Monad, Sampling, Trial, getTrial, VCTClassID, InputFolders

abstract type AbstractTrial end
abstract type AbstractSampling <: AbstractTrial end
abstract type AbstractMonad <: AbstractSampling end

Base.length(T::AbstractTrial) = getSimulationIDs(T) |> length

##########################################
############   InputFolders   ############
##########################################

struct InputFolder
    id::Int
    folder::String
end

"""
    struct InputFolders

Consolidate the folder information for a simulation/monad/sampling.

Pass the folder names within the `inputs/<input_type>` directory to create an `InputFolders` object.
Pass them in the order of `config`, `custom_code`, `rulesets_collection`, `ic_cell`, `ic_substrate`, and `ic_ecm`.
Or use the keyword-based constructors:

`InputFolders(config, custom_code; rulesets_collection="", ic_cell="", ic_substrate="", ic_ecm="")`
`InputFolders(; config="", custom_code="", rulesets_collection="", ic_cell="", ic_substrate="", ic_ecm="")`

# Fields
- `config::InputFolder`: id and folder name for the base configuration folder.
- `custom_code::InputFolder`: id and folder name for the custom code folder.
- `rulesets_collection::InputFolder`: id and folder name for the rulesets collection folder.
- `ic_cell::InputFolder`: id and folder name for the initial condition (IC) cells folder.
- `ic_substrate::InputFolder`: id and folder name for the initial condition (IC) substrate folder.
- `ic_ecm::InputFolder`: id and folder name for the initial condition (IC) extracellular matrix (ECM) folder.
"""
struct InputFolders
    config::InputFolder # id and folder name for the base configuration folder
    custom_code::InputFolder # id and folder name for the custom code folder
    rulesets_collection::InputFolder # id and folder name for the rulesets collection folder
    ic_cell::InputFolder # id and folder name for the initial condition (IC) cells folder
    ic_substrate::InputFolder # id and folder name for the initial condition (IC) substrate folder
    ic_ecm::InputFolder # id and folder name for the initial condition (IC) extracellular matrix (ECM) folder

    function InputFolders(config_folder::String, custom_code_folder::String, rulesets_collection_folder::String, ic_cell_folder::String, ic_substrate_folder::String, ic_ecm_folder::String)
        @assert config_folder != "" "config_folder must be provided"
        @assert custom_code_folder != "" "custom_code_folder must be provided"
        config = InputFolder(retrieveID("configs", config_folder), config_folder)
        custom_code = InputFolder(retrieveID("custom_codes", custom_code_folder), custom_code_folder)
        rulesets_collection = InputFolder(retrieveID("rulesets_collections", rulesets_collection_folder), rulesets_collection_folder)
        ic_cell = InputFolder(retrieveID("ic_cells", ic_cell_folder), ic_cell_folder)
        ic_substrate = InputFolder(retrieveID("ic_substrates", ic_substrate_folder), ic_substrate_folder)
        ic_ecm = InputFolder(retrieveID("ic_ecms", ic_ecm_folder), ic_ecm_folder)
        return new(config, custom_code, rulesets_collection, ic_cell, ic_substrate, ic_ecm)
    end
    function InputFolders(config_id::Int, custom_code_id::Int, rulesets_collection_id::Int, ic_cell_id::Int, ic_substrate_id::Int, ic_ecm_id::Int)
        @assert config_id > 0 "config_id must be positive"
        @assert custom_code_id > 0 "custom_code_id must be positive"
        config = InputFolder(config_id, configFolder(config_id))
        custom_code = InputFolder(custom_code_id, customCodesFolder(custom_code_id))
        rulesets_collection = InputFolder(rulesets_collection_id, rulesetsCollectionFolder(rulesets_collection_id))
        ic_cell = InputFolder(ic_cell_id, icCellFolder(ic_cell_id))
        ic_substrate = InputFolder(ic_substrate_id, icSubstrateFolder(ic_substrate_id))
        ic_ecm = InputFolder(ic_ecm_id, icECMFolder(ic_ecm_id))
        return new(config, custom_code, rulesets_collection, ic_cell, ic_substrate, ic_ecm)
    end
end

function InputFolders(config::String, custom_code::String; rulesets_collection::String="", ic_cell::String="", ic_substrate::String="", ic_ecm::String="")
    return InputFolders(config, custom_code, rulesets_collection, ic_cell, ic_substrate, ic_ecm)
end

function InputFolders(; config::String="", custom_code::String="", rulesets_collection::String="", ic_cell::String="", ic_substrate::String="", ic_ecm::String="")
    return InputFolders(config, custom_code, rulesets_collection, ic_cell, ic_substrate, ic_ecm)
end

##########################################
############   Variation IDs  ############
##########################################

struct VariationIDs
    config::Int # integer identifying which variation on the base config file to use (config_variations.db)
    rulesets::Int # integer identifying which variation on the ruleset file to use (rulesets_variations.db)
    ic_cell::Int # integer identifying which variation on the ic cell file to use (ic_cell_variations.db) (only used if cells.xml, not used for cells.csv)
end

variationIDNames() = (fieldnames(VariationIDs) .|> string) .* "_variation_id"

##########################################
#############   Simulation   #############
##########################################

struct Simulation <: AbstractMonad
    id::Int # integer uniquely identifying this simulation
    inputs::InputFolders 
    variation_ids::VariationIDs

    function Simulation(id::Int, inputs::InputFolders, variation_ids::VariationIDs)
        @assert id > 0 "id must be positive"
        @assert variation_ids.config >= 0 "config variation id must be non-negative"
        @assert variation_ids.rulesets >= -1 "rulesets variation id must be non-negative or -1 (indicating no rules)"
        @assert variation_ids.ic_cell >= -1 "ic_cell variation id must be non-negative or -1 (indicating no ic cells)"
        if variation_ids.rulesets != -1
            @assert inputs.rulesets_collection.folder != "" "rulesets_collection folder must be provided if rulesets variation id is not -1 (indicating that the rules are in use)"
        end
        if variation_ids.ic_cell == -1
            @assert inputs.ic_cell.folder == "" "ic_cell variation_id must be >=0 if ic_cell folder is provided"
        else
            @assert inputs.ic_cell.folder != "" "ic_cell folder must be provided if ic_cell variation_id is not -1 (indicating that the cells are in use)"
            @assert variation_ids.ic_cell == 0 || isfile(joinpath(data_dir, "inputs", "ics", "cells", inputs.ic_cell.folder, "cells.xml")) "cells.xml must be provided if ic_cell variation_id is >1 (indicating that the cell ic parameters are being varied)"
        end
        return new(id, inputs, variation_ids)
    end
end

function Simulation(inputs::InputFolders, variation_ids::VariationIDs=VariationIDs(0,0,0))
    simulation_id = DBInterface.execute(db, 
    """
    INSERT INTO simulations (physicell_version_id,\
    config_id,rulesets_collection_id,\
    ic_cell_id,ic_substrate_id,ic_ecm_id,custom_code_id,\
    $(join(variationIDNames(), ",")),\
    status_code_id) \
    VALUES(\
        $(physicellVersionDBEntry()),\
        $(inputs.config.id),$(inputs.rulesets_collection.id),\
        $(inputs.ic_cell.id),$(inputs.ic_substrate.id),\
        $(inputs.ic_ecm.id),$(inputs.custom_code.id),\
        $(join([string(getfield(variation_ids, field)) for field in fieldnames(VariationIDs)],",")),\
        $(getStatusCodeID("Not Started"))
    )
    RETURNING simulation_id;
    """
    ) |> DataFrame |> x -> x.simulation_id[1]
    return Simulation(simulation_id, inputs, variation_ids)
end

function getSimulation(simulation_id::Int)
    df = constructSelectQuery("simulations", "WHERE simulation_id=$(simulation_id);") |> queryToDataFrame
    if isempty(df)
        error("No simulations found for simulation_id=$simulation_id. This simulation has not been created yet.")
    end
    inputs = InputFolders(df.config_id[1], df.custom_code_id[1], df.rulesets_collection_id[1], df.ic_cell_id[1], df.ic_substrate_id[1], df.ic_ecm_id[1])
    variation_ids = VariationIDs(df.config_variation_id[1], df.rulesets_variation_id[1], df.ic_cell_variation_id[1])
    return Simulation(simulation_id, inputs, variation_ids)
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

    inputs::InputFolders # contains the folder names for the simulations in this monad

    variation_ids::VariationIDs

    function Monad(id::Int, min_length::Int, simulation_ids::Vector{Int}, inputs::InputFolders, variation_ids::VariationIDs)
        @assert id > 0 "id must be positive"
        @assert min_length >= 0 "min_length must be non-negative"

        # this could be done when adding new simulation ids to save some fie I/O
        # doing it here just to make sure it is always up to date (and for consistency across classes)
        recordSimulationIDs(id, simulation_ids) # record the simulation ids in a .csv file

        return new(id, min_length, simulation_ids, inputs, variation_ids)
    end
end

function Monad(min_length::Int, inputs::InputFolders, variation_ids::VariationIDs; use_previous_simulations::Bool=true)
    monad_id = DBInterface.execute(db, 
    """
    INSERT OR IGNORE INTO monads (physicell_version_id,\
    config_id,custom_code_id,\
    rulesets_collection_id,\
    ic_cell_id,ic_substrate_id,ic_ecm_id,\
    $(join(variationIDNames(), ","))\
    ) \
    VALUES(\
        $(physicellVersionDBEntry()),\
        $(inputs.config.id),$(inputs.custom_code.id),\
        $(inputs.rulesets_collection.id),\
        $(inputs.ic_cell.id),$(inputs.ic_substrate.id),\
        $(inputs.ic_ecm.id),\
        $(join([string(getfield(variation_ids, field)) for field in fieldnames(VariationIDs)],","))
    ) \
    RETURNING monad_id;
    """
    ) |> DataFrame |> x -> x.monad_id
    if isempty(monad_id)
        monad_id = constructSelectQuery(
            "monads",
            """
            WHERE (physicell_version_id,config_id,custom_code_id,\
            rulesets_collection_id,\
            ic_cell_id,ic_substrate_id,\
            ic_ecm_id,\
            $(join(variationIDNames(), ",")))=\
            (\
                $(physicellVersionDBEntry()),\
                $(inputs.config.id),$(inputs.custom_code.id),\
                $(inputs.rulesets_collection.id),\
                $(inputs.ic_cell.id),$(inputs.ic_substrate.id),\
                $(inputs.ic_ecm.id),\
                $(join([string(getfield(variation_ids, field)) for field in fieldnames(VariationIDs)],","))
            );\
            """,
            selection="monad_id"
        ) |> queryToDataFrame |> x -> x.monad_id[1] # get the monad_id
    else
        monad_id = monad_id[1] # get the monad_id
    end
    simulation_ids = use_previous_simulations ? readMonadSimulationIDs(monad_id) : Int[]
    num_sims_to_add = min_length - length(simulation_ids)
    if num_sims_to_add > 0
        for _ = 1:num_sims_to_add
            simulation = Simulation(inputs, variation_ids) # create a new simulation
            push!(simulation_ids, simulation.id) # add the simulation id to the monad
        end
    end

    return Monad(monad_id, min_length, simulation_ids, inputs, variation_ids)
end

function Monad(inputs::InputFolders, variation_ids::VariationIDs; use_previous_simulations::Bool=true)
    min_length = 0 # not making a monad to run if not supplying the min_length info
    Monad(min_length, inputs, variation_ids; use_previous_simulations=use_previous_simulations)
end

function getMonad(monad_id::Int)
    df = constructSelectQuery("monads", "WHERE monad_id=$(monad_id);") |> queryToDataFrame
    simulation_ids = readMonadSimulationIDs(monad_id)
    if isempty(df) || isempty(simulation_ids)
        error("No monads found for monad_id=$monad_id. This monad did not run.")
    end
    min_length = 0
    inputs = InputFolders(df.config_id[1], df.custom_code_id[1], df.rulesets_collection_id[1], df.ic_cell_id[1], df.ic_substrate_id[1], df.ic_ecm_id[1])
    variation_ids = VariationIDs(df.config_variation_id[1], df.rulesets_variation_id[1], df.ic_cell_variation_id[1])
    return Monad(monad_id, min_length, simulation_ids, inputs, variation_ids)
end

Monad(monad_id::Int) = getMonad(monad_id)

function Simulation(monad::Monad)
    return Simulation(monad.inputs, monad.variation_ids)
end

function Monad(simulation::Simulation)
    min_length = 0 # do not impose a min length on this monad
    monad = Monad(min_length, simulation.inputs, simulation.variation_ids)
    addSimulationID!(monad, simulation.id)
    return monad
end

function addSimulationID!(monad::Monad, simulation_id::Int)
    if simulation_id in monad.simulation_ids
        return
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
    monad_ids::Vector{Int} # array of monad indices belonging to this sampling

    inputs::InputFolders # contains the folder names for this sampling

    variation_ids::Vector{VariationIDs} # variation_ids associated with each monad

    function Sampling(id, monad_min_length, monad_ids, inputs, variation_ids)
        @assert id > 0 "id must be positive"
        n_monads = length(monad_ids)
        n_variations = length(variation_ids)
        if n_monads != n_variations
            error_message = """
                Number of monads and variations must be the same
                \tn_monads = $n_monads
                \tn_variations = $n_variations
            """
            throw(ArgumentError(error_message))
        end
        recordMonadIDs(id, monad_ids) # record the monad ids in a .csv file
        return new(id, monad_min_length, monad_ids, inputs, variation_ids)
    end
end

function Sampling(monad_min_length::Int, monad_ids::AbstractVector{<:Integer}, inputs::InputFolders, variation_ids::Vector{VariationIDs})
    id = -1
    sampling_ids = constructSelectQuery(
        "samplings",
        """
        WHERE (physicell_version_id,\
        config_id,custom_code_id,\
        rulesets_collection_id,\
        ic_cell_id,ic_substrate_id,ic_ecm_id)=\
        (\
            $(physicellVersionDBEntry()),\
            $(inputs.config.id),$(inputs.custom_code.id),\
            $(inputs.rulesets_collection.id),\
            $(inputs.ic_cell.id),$(inputs.ic_substrate.id),$(inputs.ic_ecm.id)\
        );\
        """;
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
        id = DBInterface.execute(db, 
        """
        INSERT INTO samplings \
        (physicell_version_id,\
        config_id,custom_code_id,\
        rulesets_collection_id,\
        ic_cell_id,ic_substrate_id,ic_ecm_id) \
        VALUES($(physicellVersionDBEntry()),\
        $(inputs.config.id),$(inputs.custom_code.id),\
        $(inputs.rulesets_collection.id),\
        $(inputs.ic_cell.id),$(inputs.ic_substrate.id),\
        $(inputs.ic_ecm.id)) RETURNING sampling_id;
        """
        ) |> DataFrame |> x -> x.sampling_id[1] # get the sampling_id
    end
    return Sampling(id, monad_min_length, monad_ids, inputs, variation_ids)
end

function Sampling(monad_min_length::Int, inputs::InputFolders, variation_ids::AbstractArray{VariationIDs}; use_previous_simulations::Bool=true)
    monad_ids = createMonadIDs(monad_min_length, inputs, variation_ids; use_previous_simulations=use_previous_simulations)
    return Sampling(monad_min_length, monad_ids, inputs, variation_ids)
end

function Sampling(inputs::InputFolders;
                monad_min_length::Integer=0,
                config_variation_ids::Union{Int,AbstractArray{<:Integer}}=Int[], 
                rulesets_variation_ids::Union{Int,AbstractArray{<:Integer}}=fill(inputs.rulesets_collection.folder=="" ? -1 : 0, size(config_variation_ids)),
                ic_cell_variation_ids::Union{Int,AbstractArray{<:Integer}}=fill(inputs.ic_cell.folder=="" ? -1 : 0, size(config_variation_ids)),
                use_previous_simulations::Bool=true) 
    # allow for passing in a single config_variation_id and/or rulesets_variation_id
    # later, can support passing in (for example) a 3x6 config_variation_ids and a 3x1 rulesets_variation_ids and expanding the rulesets_variation_ids to 3x6, but that can get tricky fast
    if all(x->x isa Integer, [config_variation_ids, rulesets_variation_ids, ic_cell_variation_ids])
        config_variation_ids = [config_variation_ids]
        rulesets_variation_ids = [rulesets_variation_ids]
        ic_cell_variation_ids = [ic_cell_variation_ids]
    else
        ns = [length(x) for x in [config_variation_ids, rulesets_variation_ids, ic_cell_variation_ids] if !(x isa Integer)]
        @assert all(x->x==ns[1], ns) "config_variation_ids, rulesets_variation_ids, and ic_cell_variation_ids must have the same length if they are not integers"
        config_variation_ids = config_variation_ids isa Integer ? fill(config_variation_ids, ns[1]) : config_variation_ids
        rulesets_variation_ids = rulesets_variation_ids isa Integer ? fill(rulesets_variation_ids, ns[1]) : rulesets_variation_ids
        ic_cell_variation_ids = ic_cell_variation_ids isa Integer ? fill(ic_cell_variation_ids, ns[1]) : ic_cell_variation_ids
    end
    variation_ids = [VariationIDs(config_variation_ids[i], rulesets_variation_ids[i], ic_cell_variation_ids[i]) for i in 1:length(config_variation_ids)]
    return Sampling(monad_min_length, inputs, variation_ids; use_previous_simulations=use_previous_simulations) 
end

function Sampling(monad_min_length::Int, monads::AbstractArray{<:AbstractMonad})
    inputs = monads[1].inputs
    for monad in monads
        if monad.inputs != inputs
            error("All monads must have the same inputs")
            # could choose to make a trial from these here...
        end
    end
    variation_ids = [monad.variation_ids for monad in monads]
    monad_ids = [monad.id for monad in monads]
    return Sampling(monad_min_length, monad_ids, inputs, variation_ids) 
end

function createMonadIDs(monad_min_length::Int, inputs::InputFolders, variation_ids::AbstractArray{VariationIDs}; use_previous_simulations::Bool=true)
    _size = length(variation_ids)
    monad_ids = -ones(Int, _size)
    
    for (i, vid) in enumerate(variation_ids) 
        monad = Monad(monad_min_length, inputs, vid; use_previous_simulations=use_previous_simulations) 
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
    inputs = InputFolders(df.config_id[1], df.custom_code_id[1], df.rulesets_collection_id[1], df.ic_cell_id[1], df.ic_substrate_id[1], df.ic_ecm_id[1])
    monad_df = constructSelectQuery("monads", "WHERE monad_id IN ($(join(monad_ids,",")))") |> queryToDataFrame
    variation_ids = [VariationIDs(monad_df.config_variation_id[i], monad_df.rulesets_variation_id[i], monad_df.ic_cell_variation_id[i]) for i in 1:length(monad_ids)]
    return Sampling(sampling_id, monad_min_length, monad_ids, inputs, variation_ids)
end

Sampling(sampling_id::Int) = getSampling(sampling_id)

function Monad(sampling::Sampling, index::Int; use_previous_simulations::Bool=true)
    return Monad(sampling.monad_min_length, sampling.inputs, sampling.variation_ids[index]; use_previous_simulations=use_previous_simulations)
end

##########################################
###############   Trial   ################
##########################################

struct Trial <: AbstractTrial
    # trial is a group of samplings with different ICs, custom codes, and rulesets
    id::Int # integer uniquely identifying this trial
    monad_min_length::Int # minimum length of each monad belonging to the samplings in this trial
    sampling_ids::Vector{Int} # array of sampling indices belonging to this trial

    inputs::Vector{InputFolders} # contains the folder names for the samplings in this trial
    variation_ids::Vector{Vector{VariationIDs}} # variation_ids associated with each monad for each sampling

    function Trial(id::Int, monad_min_length::Int, sampling_ids::Vector{Int}, inputs::Vector{InputFolders}, variation_ids::Vector{Vector{VariationIDs}})
        @assert id > 0 "id must be positive"
        n_samplings = length(sampling_ids)
        n_inputs = length(inputs)
        n_variations = length(variation_ids)
        if n_samplings != n_inputs || n_samplings != n_variations # the negation of this is n_samplings == n_inputs && n_samplings == n_folder_names && n_samplings == n_variations, which obviously means they're all the same
            throw(ArgumentError("Number of samplings, inputs, and variations must be the same"))
        end

        recordSamplingIDs(id, sampling_ids) # record the sampling ids in a .csv file

        return new(id, monad_min_length, sampling_ids, inputs, variation_ids)
    end
end

function Trial(monad_min_length::Int, inputs::Vector{InputFolders}, variation_ids::Vector{Vector{VariationIDs}})
    sampling_ids = createSamplingIDs(monad_min_length, inputs, variation_ids)
    id = getTrialID(sampling_ids)
    return Trial(id, monad_min_length, sampling_ids, inputs, variation_ids)
end

function createSamplingIDs(monad_min_length::Int, inputs::Vector{InputFolders}, variation_ids::Vector{Vector{VariationIDs}}; use_previous_simulations::Bool=true)
    _size = size(inputs)
    sampling_ids = -ones(Int, _size)
    
    for i in eachindex(sampling_ids)
        sampling = Sampling(monad_min_length, inputs[i], variation_ids[i]; use_previous_simulations=use_previous_simulations)
        sampling_ids[i] = sampling.id
    end
    return sampling_ids
end

function Trial(monad_min_length::Int, sampling_ids::Vector{Int}, inputs::Vector{InputFolders}, variation_ids::Vector{Vector{VariationIDs}}; use_previous_simulations::Bool=true)
    id = getTrialID(sampling_ids)
    return Trial(id, monad_min_length, sampling_ids, inputs, variation_ids)
end

function getTrialID(sampling_ids::Vector{Int})
    id = -1
    trial_ids = constructSelectQuery("trials"; selection="trial_id") |> queryToDataFrame |> x -> x.trial_id
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
    inputs = [sampling.inputs for sampling in samplings]
    variation_ids = [sampling.variation_ids for sampling in samplings]
    return Trial(monad_min_length, sampling_ids, inputs, variation_ids)
end

function Trial(; monad_min_length::Int=0, sampling_ids::AbstractArray{<:Integer}=Int[], config_folders::Vector{<:AbstractString}=String[],
                rulesets_collection_folders::Vector{<:AbstractString}=String[], ic_cell_folders::Vector{<:AbstractString}=String[], 
                ic_substrate_folders::Vector{<:AbstractString}=String[], ic_ecm_folders::Vector{<:AbstractString}=String[], custom_code_folders::Vector{<:AbstractString}=String[],
                config_variation_ids::AbstractArray{<:AbstractArray{<:Integer}}=AbstractArray{<:Integer}[],
                rulesets_variation_ids::AbstractArray{<:AbstractArray{<:Integer}}=AbstractArray{<:Integer}[],
                ic_cell_variation_ids::AbstractArray{<:AbstractArray{<:Integer}}=AbstractArray{<:Integer}[],
                use_previous_simulations::Bool=true)

    inputs = [InputFolders(config_folder, custom_code_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder) for (config_folder, custom_code_folder, rulesets_collection_folder, ic_cell_folder, ic_substrate_folder, ic_ecm_folder) in zip(config_folders, custom_code_folders, rulesets_collection_folders, ic_cell_folders, ic_substrate_folders, ic_ecm_folders)]
    variation_ids = [VariationIDs(config_variation_ids[i], rulesets_variation_ids[i], ic_cell_variation_ids[i]) for i in 1:length(config_variation_ids)]
    return Trial(monad_min_length, sampling_ids, inputs, variation_ids; use_previous_simulations=use_previous_simulations)
end

function getTrial(trial_id::Int)
    df = constructSelectQuery("trials", "WHERE trial_id=$(trial_id);") |> queryToDataFrame
    if isempty(df) || isempty(readTrialSamplingIDs(trial_id))
        error("No samplings found for trial_id=$trial_id. This trial did not run.")
    end
    sampling_ids = readTrialSamplingIDs(trial_id)
    return Trial([Sampling(id) for id in sampling_ids])
end

Trial(trial_id::Int) = getTrial(trial_id)

function Sampling(id::Int, monad_min_length::Int, inputs::InputFolders, variation_ids::Vector{VariationIDs}; use_previous_simulations::Bool=true)
    monad_ids = createMonadIDs(monad_min_length, inputs, variation_ids; use_previous_simulations=use_previous_simulations)
    return Sampling(id, monad_min_length, monad_ids, inputs, variation_ids)
end 

function Sampling(trial::Trial, index::Int)
    return Sampling(trial.sampling_ids[index], trial.monad_min_length, trial.inputs[index], trial.variation_ids[index])
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
