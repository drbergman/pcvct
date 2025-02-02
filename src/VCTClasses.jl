export Simulation, Monad, Sampling, Trial, InputFolders

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
    InputFolders

Consolidate the folder information for a simulation/monad/sampling.

Pass the folder names within the `inputs/<input_type>` directory to create an `InputFolders` object.
Pass them in the order of `config`, `custom_code`, `rulesets_collection`, `ic_cell`, `ic_substrate`, `ic_ecm`, `ic_dc`.
Or use the keyword-based constructors:

```julia
InputFolders(config, custom_code; rulesets_collection="", ic_cell="", ic_substrate="", ic_ecm="", ic_dc="")
```
```julia
InputFolders(; config="", custom_code="", rulesets_collection="", ic_cell="", ic_substrate="", ic_ecm="", ic_dc="")
```

# Fields
- `config::InputFolder`: id and folder name for the base configuration folder.
- `custom_code::InputFolder`: id and folder name for the custom code folder.
- `rulesets_collection::InputFolder`: id and folder name for the rulesets collection folder.
- `ic_cell::InputFolder`: id and folder name for the initial condition (IC) cells folder.
- `ic_substrate::InputFolder`: id and folder name for the initial condition (IC) substrate folder.
- `ic_ecm::InputFolder`: id and folder name for the initial condition (IC) extracellular matrix (ECM) folder.
- `ic_dc::InputFolder`: id and folder name for the initial condition (IC) dirichlet conditions (DC) folder.
"""
struct InputFolders
    config::InputFolder # id and folder name for the base configuration folder
    custom_code::InputFolder # id and folder name for the custom code folder
    rulesets_collection::InputFolder # id and folder name for the rulesets collection folder
    ic_cell::InputFolder # id and folder name for the initial condition (IC) cells folder
    ic_substrate::InputFolder # id and folder name for the initial condition (IC) substrate folder
    ic_ecm::InputFolder # id and folder name for the initial condition (IC) extracellular matrix (ECM) folder
    ic_dc::InputFolder # id and folder name for the initial condition (IC) dirichlet conditions (DC) folder

    function InputFolders(config_folder::String, custom_code_folder::String, rulesets_collection_folder::String, ic_cell_folder::String, ic_substrate_folder::String, ic_ecm_folder::String, ic_dc_folder::String)
        @assert config_folder != "" "config_folder must be provided"
        @assert custom_code_folder != "" "custom_code_folder must be provided"
        config = InputFolder(retrieveID("configs", config_folder), config_folder)
        custom_code = InputFolder(retrieveID("custom_codes", custom_code_folder), custom_code_folder)
        rulesets_collection = InputFolder(retrieveID("rulesets_collections", rulesets_collection_folder), rulesets_collection_folder)
        ic_cell = InputFolder(retrieveID("ic_cells", ic_cell_folder), ic_cell_folder)
        ic_substrate = InputFolder(retrieveID("ic_substrates", ic_substrate_folder), ic_substrate_folder)
        ic_ecm = InputFolder(retrieveID("ic_ecms", ic_ecm_folder), ic_ecm_folder)
        ic_dc = InputFolder(retrieveID("ic_dcs", ic_dc_folder), ic_dc_folder)
        return new(config, custom_code, rulesets_collection, ic_cell, ic_substrate, ic_ecm, ic_dc)
    end
    function InputFolders(config_id::Int, custom_code_id::Int, rulesets_collection_id::Int, ic_cell_id::Int, ic_substrate_id::Int, ic_ecm_id::Int, ic_dc_id::Int)
        @assert config_id > 0 "config_id must be positive"
        @assert custom_code_id > 0 "custom_code_id must be positive"
        config = InputFolder(config_id, configFolder(config_id))
        custom_code = InputFolder(custom_code_id, customCodesFolder(custom_code_id))
        rulesets_collection = InputFolder(rulesets_collection_id, rulesetsCollectionFolder(rulesets_collection_id))
        ic_cell = InputFolder(ic_cell_id, icCellFolder(ic_cell_id))
        ic_substrate = InputFolder(ic_substrate_id, icSubstrateFolder(ic_substrate_id))
        ic_ecm = InputFolder(ic_ecm_id, icECMFolder(ic_ecm_id))
        ic_dc = InputFolder(ic_dc_id, icDCFolder(ic_dc_id))
        return new(config, custom_code, rulesets_collection, ic_cell, ic_substrate, ic_ecm, ic_dc)
    end
end

function InputFolders(config::String, custom_code::String; rulesets_collection::String="", ic_cell::String="", ic_substrate::String="", ic_ecm::String="", ic_dc::String="")
    return InputFolders(config, custom_code, rulesets_collection, ic_cell, ic_substrate, ic_ecm, ic_dc)
end

function InputFolders(; config::String="", custom_code::String="", rulesets_collection::String="", ic_cell::String="", ic_substrate::String="", ic_ecm::String="", ic_dc::String="")
    return InputFolders(config, custom_code, rulesets_collection, ic_cell, ic_substrate, ic_ecm, ic_dc)
end

##########################################
############   Variation IDs  ############
##########################################

struct VariationIDs
    config::Int # integer identifying which variation on the base config file to use (config_variations.db)
    rulesets_collection::Int # integer identifying which variation on the ruleset file to use (rulesets_collection_variations.db)
    ic_cell::Int # integer identifying which variation on the ic cell file to use (ic_cell_variations.db) (only used if cells.xml, not used for cells.csv)
end

function VariationIDs(inputs::InputFolders)
    fns = fieldnames(VariationIDs)
    base_variation_ids = [(getfield(inputs, fn).id==-1 ? -1 : 0) for fn in fns]
    return VariationIDs(base_variation_ids...)
end

variationIDNames() = (fieldnames(VariationIDs) .|> string) .* "_variation_id"

##########################################
#############   Simulation   #############
##########################################

"""
    Simulation

A simulation that represents a single run of the model.

To create a new simulation, best practice is to use `createTrial` and supply it with the `InputFolders` and any number of single-valued DiscreteVariations:
```
inputs = InputFolders(config_folder, custom_code_folder)
simulation = createTrial(inputs) # uses the default config file as-is

ev = DiscreteVariation(["overall","max_time"], 1440)
simulation = createTrial(inputs, ev) # uses the config file with the specified variation
```

If there is a previously created simulation that you wish to access, you can use its ID to create a `Simulation` object:
```
simulation = Simulation(simulation_id)
```

# Fields
- `id::Int`: integer uniquely identifying this simulation. Matches with the folder in `data/outputs/simulations/`
- `inputs::InputFolders`: contains the folder info for this simulation.
- `variation_ids::VariationIDs`: contains the variation IDs for this simulation.
"""
struct Simulation <: AbstractMonad
    id::Int # integer uniquely identifying this simulation
    inputs::InputFolders 
    variation_ids::VariationIDs

    function Simulation(id::Int, inputs::InputFolders, variation_ids::VariationIDs)
        @assert id > 0 "id must be positive"
        @assert variation_ids.config >= 0 "config variation id must be non-negative"
        @assert variation_ids.rulesets_collection >= -1 "rulesets_collection variation id must be non-negative or -1 (indicating no rules)"
        @assert variation_ids.ic_cell >= -1 "ic_cell variation id must be non-negative or -1 (indicating no ic cells)"
        if variation_ids.rulesets_collection != -1
            @assert inputs.rulesets_collection.folder != "" "rulesets_collection folder must be provided if rulesets_collection variation id is not -1 (indicating that the rules are in use)"
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

function Simulation(inputs::InputFolders, variation_ids::VariationIDs=VariationIDs(inputs))
    simulation_id = DBInterface.execute(db, 
    """
    INSERT INTO simulations (physicell_version_id,\
    config_id,rulesets_collection_id,\
    ic_cell_id,ic_substrate_id,ic_ecm_id,ic_dc_id,\
    custom_code_id,\
    $(join(variationIDNames(), ",")),\
    status_code_id) \
    VALUES(\
        $(physicellVersionDBEntry()),\
        $(inputs.config.id),$(inputs.rulesets_collection.id),\
        $(inputs.ic_cell.id),$(inputs.ic_substrate.id),\
        $(inputs.ic_ecm.id),$(inputs.ic_dc.id),$(inputs.custom_code.id),\
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
        error("Simulation $(simulation_id) not in the database.")
    end
    inputs = InputFolders(df.config_id[1], df.custom_code_id[1], df.rulesets_collection_id[1], df.ic_cell_id[1], df.ic_substrate_id[1], df.ic_ecm_id[1], df.ic_dc_id[1])
    variation_ids = VariationIDs(df.config_variation_id[1], df.rulesets_collection_variation_id[1], df.ic_cell_variation_id[1])
    return Simulation(simulation_id, inputs, variation_ids)
end

Simulation(simulation_id::Int) = getSimulation(simulation_id)

Base.length(simulation::Simulation) = 1

##########################################
###############   Monad   ################
##########################################

"""
    Monad

A group of simulations that are identical up to randomness.

To create a new monad, best practice is to use `createTrial` and supply it with the `InputFolders` and any number of single-valued DiscreteVariations.
Set `n_replicates=0` to avoid adding new simulations to the database. This is useful for creating references for later use.
Otherwise, set `n_replicates` > 1 to create the simulations to go with this monad.
If `n_replicates` = 1, it will return a `Simulation` object.
```
inputs = InputFolders(config_folder, custom_code_folder)
monad = createTrial(inputs; n_replicates=0) # uses the default config file as-is

ev = DiscreteVariation(["overall","max_time"], 1440)
monad = createTrial(inputs, ev; n_replicates=10) # uses the config file with the specified variation

monad = createTrial(inputs, ev; n_replicates=10, use_previous=false) # changes the default behavior and creates 10 new simulations for this monad
```

If there is a previously created monad that you wish to access, you can use its ID to create a `Monad` object:
```
monad = Monad(monad_id)
monad = Monad(monad_id; n_replicates=5) # ensures at least 5 simulations in the monad (using previous sims)
```

# Fields
- `id::Int`: integer uniquely identifying this monad. Matches with the folder in `data/outputs/monads/`
- `n_replicates::Int`: minimum number of simulations to ensure are part of this monad when running this monad.
- `simulation_ids::Vector{Int}`: array of simulation IDs belonging to this monad. This need not have length equal to `n_replicates`.
- `inputs::InputFolders`: contains the folder info for this monad.
- `variation_ids::VariationIDs`: contains the variation IDs for this monad.
"""
struct Monad <: AbstractMonad
    # a monad is a group of simulation replicates, i.e. identical up to randomness
    id::Int # integer uniquely identifying this monad
    n_replicates::Int # (minimum) number of simulations belonging to this monad
    simulation_ids::Vector{Int} # simulation ids belonging to this monad

    inputs::InputFolders # contains the folder names for the simulations in this monad

    variation_ids::VariationIDs

    function Monad(n_replicates::Int, inputs::InputFolders, variation_ids::VariationIDs, use_previous::Bool)
        monad_id = DBInterface.execute(db,
                       """
                       INSERT OR IGNORE INTO monads (physicell_version_id,\
                       config_id,custom_code_id,\
                       rulesets_collection_id,\
                       ic_cell_id,ic_substrate_id,ic_ecm_id,ic_dc_id,\
                       $(join(variationIDNames(), ","))\
                       ) \
                       VALUES(\
                           $(physicellVersionDBEntry()),\
                           $(inputs.config.id),$(inputs.custom_code.id),\
                           $(inputs.rulesets_collection.id),\
                           $(inputs.ic_cell.id),$(inputs.ic_substrate.id),\
                           $(inputs.ic_ecm.id),$(inputs.ic_dc.id),\
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
                           ic_ecm_id,ic_dc_id,\
                           $(join(variationIDNames(), ",")))=\
                           (\
                               $(physicellVersionDBEntry()),\
                               $(inputs.config.id),$(inputs.custom_code.id),\
                               $(inputs.rulesets_collection.id),\
                               $(inputs.ic_cell.id),$(inputs.ic_substrate.id),\
                               $(inputs.ic_ecm.id),$(inputs.ic_dc.id),\
                               $(join([string(getfield(variation_ids, field)) for field in fieldnames(VariationIDs)],","))
                           );\
                           """,
                           selection="monad_id"
                       ) |> queryToDataFrame |> x -> x.monad_id[1] # get the monad_id
        else
            monad_id = monad_id[1] # get the monad_id
        end
        return Monad(monad_id, n_replicates, inputs, variation_ids, use_previous)
    end
    function Monad(id::Int, n_replicates::Int, inputs::InputFolders, variation_ids::VariationIDs, use_previous::Bool)
        simulation_ids = use_previous ? readMonadSimulationIDs(id) : Int[]
        num_sims_to_add = n_replicates - length(simulation_ids)
        if num_sims_to_add > 0
            for _ = 1:num_sims_to_add
                simulation = Simulation(inputs, variation_ids) # create a new simulation
                push!(simulation_ids, simulation.id) # add the simulation id to the monad
            end
        end

        @assert id > 0 "id must be positive"
        @assert n_replicates >= 0 "n_replicates must be non-negative"

        # this could be done when adding new simulation ids to save some fie I/O
        # doing it here just to make sure it is always up to date (and for consistency across classes)
        recordSimulationIDs(id, simulation_ids) # record the simulation ids in a .csv file

        return new(id, n_replicates, simulation_ids, inputs, variation_ids)
    end

end

function Monad(inputs::InputFolders, variation_ids::VariationIDs; use_previous::Bool=true)
    n_replicates = 0 # not making a monad to run if not supplying the n_replicates info
    Monad(n_replicates, inputs, variation_ids, use_previous)
end

function getMonad(monad_id::Int, n_replicates::Int)
    df = constructSelectQuery("monads", "WHERE monad_id=$(monad_id);") |> queryToDataFrame
    if isempty(df)
        error("Monad $(monad_id) not in the database.")
    end
    inputs = InputFolders(df.config_id[1], df.custom_code_id[1], df.rulesets_collection_id[1], df.ic_cell_id[1], df.ic_substrate_id[1], df.ic_ecm_id[1], df.ic_dc_id[1])
    variation_ids = VariationIDs(df.config_variation_id[1], df.rulesets_collection_variation_id[1], df.ic_cell_variation_id[1])
    use_previous = true
    return Monad(monad_id, n_replicates, inputs, variation_ids, use_previous)
end

Monad(monad_id::Integer; n_replicates::Integer=0) = getMonad(monad_id, n_replicates)

function Simulation(monad::Monad)
    return Simulation(monad.inputs, monad.variation_ids)
end

function Monad(simulation::Simulation)
    n_replicates = 0 # do not impose a min length on this monad
    use_previous = true
    monad = Monad(n_replicates, simulation.inputs, simulation.variation_ids, use_previous)
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

"""
    Sampling

A group of monads that have the same input folders, but differ in parameter values.

To create a new sampling, best practice is to use `createTrial` and supply it with the `InputFolders` and any number of DiscreteVariations.
At least one should have multiple values to create a sampling.
```
inputs = InputFolders(config_folder, custom_code_folder)
ev = DiscreteVariation(["overall","max_time"], [1440, 2880]))
sampling = createTrial(inputs, ev; n_replicates=3, use_previous=true)
```

If there is a previously created sampling that you wish to access, you can use its ID to create a `Sampling` object:
```
sampling = Sampling(sampling_id)
sampling = Sampling(sampling_id; n_replicates=5) # ensures at least 5 simulations in each monad (using previous sims)
```

# Fields
- `id::Int`: integer uniquely identifying this sampling. Matches with the folder in `data/outputs/samplings/`
- `n_replicates::Int`: minimum number of simulations to ensure are part of each monad when running this sampling.
- `monad_ids::Vector{Int}`: array of monad IDs belonging to this sampling.
- `inputs::InputFolders`: contains the folder info for this sampling.
- `variation_ids::Vector{VariationIDs}`: contains the variation IDs for each monad.
"""
struct Sampling <: AbstractSampling
    # sampling is a group of monads with config parameters varied
    id::Int # integer uniquely identifying this sampling
    n_replicates::Int # minimum length of each monad belonging to this sampling
    monad_ids::Vector{Int} # array of monad indices belonging to this sampling

    inputs::InputFolders # contains the folder names for this sampling

    variation_ids::Vector{VariationIDs} # variation_ids associated with each monad

    function Sampling(id, n_replicates, monad_ids, inputs, variation_ids)
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
        return new(id, n_replicates, monad_ids, inputs, variation_ids)
    end
end

function Sampling(n_replicates::Int, monad_ids::AbstractVector{<:Integer}, inputs::InputFolders, variation_ids::Vector{VariationIDs})
    id = -1
    sampling_ids = constructSelectQuery(
        "samplings",
        """
        WHERE (physicell_version_id,\
        config_id,custom_code_id,\
        rulesets_collection_id,\
        ic_cell_id,ic_substrate_id,ic_ecm_id,ic_dc_id)=\
        (\
            $(physicellVersionDBEntry()),\
            $(inputs.config.id),$(inputs.custom_code.id),\
            $(inputs.rulesets_collection.id),\
            $(inputs.ic_cell.id),$(inputs.ic_substrate.id),$(inputs.ic_ecm.id),$(inputs.ic_dc.id),\
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
        ic_cell_id,ic_substrate_id,ic_ecm_id,ic_dc_id) \
        VALUES($(physicellVersionDBEntry()),\
        $(inputs.config.id),$(inputs.custom_code.id),\
        $(inputs.rulesets_collection.id),\
        $(inputs.ic_cell.id),$(inputs.ic_substrate.id),\
        $(inputs.ic_ecm.id),$(inputs.ic_dc.id)) RETURNING sampling_id;
        """
        ) |> DataFrame |> x -> x.sampling_id[1] # get the sampling_id
    end
    return Sampling(id, n_replicates, monad_ids, inputs, variation_ids)
end

function Sampling(n_replicates::Int, inputs::InputFolders, variation_ids::AbstractArray{VariationIDs}; use_previous::Bool=true)
    monad_ids = createMonadIDs(n_replicates, inputs, variation_ids; use_previous=use_previous)
    return Sampling(n_replicates, monad_ids, inputs, variation_ids)
end

function Sampling(inputs::InputFolders;
                n_replicates::Integer=0,
                config_variation_ids::Union{Int,AbstractArray{<:Integer}}=Int[], 
                rulesets_collection_variation_ids::Union{Int,AbstractArray{<:Integer}}=fill(inputs.rulesets_collection.folder=="" ? -1 : 0, size(config_variation_ids)),
                ic_cell_variation_ids::Union{Int,AbstractArray{<:Integer}}=fill(inputs.ic_cell.folder=="" ? -1 : 0, size(config_variation_ids)),
                use_previous::Bool=true) 
    # allow for passing in a single config_variation_id and/or rulesets_collection_variation_id
    # later, can support passing in (for example) a 3x6 config_variation_ids and a 3x1 rulesets_collection_variation_ids and expanding the rulesets_collection_variation_ids to 3x6, but that can get tricky fast
    if all(x->x isa Integer, [config_variation_ids, rulesets_collection_variation_ids, ic_cell_variation_ids])
        config_variation_ids = [config_variation_ids]
        rulesets_collection_variation_ids = [rulesets_collection_variation_ids]
        ic_cell_variation_ids = [ic_cell_variation_ids]
    else
        ns = [length(x) for x in [config_variation_ids, rulesets_collection_variation_ids, ic_cell_variation_ids] if !(x isa Integer)]
        @assert all(x->x==ns[1], ns) "config_variation_ids, rulesets_collection_variation_ids, and ic_cell_variation_ids must have the same length if they are not integers"
        config_variation_ids = config_variation_ids isa Integer ? fill(config_variation_ids, ns[1]) : config_variation_ids
        rulesets_collection_variation_ids = rulesets_collection_variation_ids isa Integer ? fill(rulesets_collection_variation_ids, ns[1]) : rulesets_collection_variation_ids
        ic_cell_variation_ids = ic_cell_variation_ids isa Integer ? fill(ic_cell_variation_ids, ns[1]) : ic_cell_variation_ids
    end
    variation_ids = [VariationIDs(config_variation_ids[i], rulesets_collection_variation_ids[i], ic_cell_variation_ids[i]) for i in 1:length(config_variation_ids)]
    return Sampling(n_replicates, inputs, variation_ids; use_previous=use_previous) 
end

function Sampling(n_replicates::Int, monads::AbstractArray{<:AbstractMonad})
    inputs = monads[1].inputs
    for monad in monads
        if monad.inputs != inputs
            error("All monads must have the same inputs")
            # could choose to make a trial from these here...
        end
    end
    variation_ids = [monad.variation_ids for monad in monads]
    monad_ids = [monad.id for monad in monads]
    return Sampling(n_replicates, monad_ids, inputs, variation_ids) 
end

function createMonadIDs(n_replicates::Int, inputs::InputFolders, variation_ids::AbstractArray{VariationIDs}; use_previous::Bool=true)
    _size = length(variation_ids)
    monad_ids = -ones(Int, _size)
    
    for (i, vid) in enumerate(variation_ids) 
        monad = Monad(n_replicates, inputs, vid, use_previous) 
        monad_ids[i] = monad.id
    end
    return monad_ids
end

function getSampling(sampling_id::Int, n_replicates::Int)
    df = constructSelectQuery("samplings", "WHERE sampling_id=$(sampling_id);") |> queryToDataFrame
    if isempty(df)
        error("Sampling $(sampling_id) not in the database.")
    end
    monad_ids = readSamplingMonadIDs(sampling_id)
    inputs = InputFolders(df.config_id[1], df.custom_code_id[1], df.rulesets_collection_id[1], df.ic_cell_id[1], df.ic_substrate_id[1], df.ic_ecm_id[1], df.ic_dc_id[1])
    monad_df = constructSelectQuery("monads", "WHERE monad_id IN ($(join(monad_ids,",")))") |> queryToDataFrame
    variation_ids = [VariationIDs(monad_df.config_variation_id[i], monad_df.rulesets_collection_variation_id[i], monad_df.ic_cell_variation_id[i]) for i in 1:length(monad_ids)]
    return Sampling(sampling_id, n_replicates, monad_ids, inputs, variation_ids)
end

Sampling(sampling_id::Integer; n_replicates::Integer=0) = getSampling(sampling_id, n_replicates)

function Monad(sampling::Sampling, index::Int; use_previous::Bool=true)
    return Monad(sampling.n_replicates, sampling.inputs, sampling.variation_ids[index], use_previous)
end

function Sampling(monads::Vector{Monad})
    n_replicates = [monad.n_replicates for monad in monads] |> minimum
    return Sampling(n_replicates, monads)
end

##########################################
###############   Trial   ################
##########################################

"""
    Trial

A group of samplings that can have different input folders.

To create a new trial, best practice currently is to create a vector of `Sampling` objects and passing them to `Trial`.
```
inputs_1 = InputFolders(config_folder_1, custom_code_folder_1)
inputs_2 = InputFolders(config_folder_2, custom_code_folder_2)
ev = DiscreteVariation(["overall","max_time"], [1440, 2880]))
sampling_1 = createTrial(inputs_1, ev; n_replicates=3, use_previous=true)
sampling_2 = createTrial(inputs_2, ev; n_replicates=3, use_previous=true)
trial = Trial([sampling_1, sampling_2])
```

If there is a previous trial that you wish to access, you can use its ID to create a `Trial` object:
```
trial = Trial(trial_id)
trial = Trial(trial_id; n_replicates=5) # ensures at least 5 simulations in each monad (using previous sims)
```

# Fields
- `id::Int`: integer uniquely identifying this trial. Matches with the folder in `data/outputs/trials/`
- `n_replicates::Int`: minimum number of simulations to ensure are part of each monad in each sampling in this trial.
- `sampling_ids::Vector{Int}`: array of sampling IDs belonging to this trial.
- `inputs::Vector{InputFolders}`: contains the folder info for each sampling in this trial.
- `variation_ids::Vector{Vector{VariationIDs}}`: contains the variation IDs for each monad in each sampling in this trial.
"""
struct Trial <: AbstractTrial
    # trial is a group of samplings with different ICs, custom codes, and rulesets
    id::Int # integer uniquely identifying this trial
    n_replicates::Int # minimum length of each monad belonging to the samplings in this trial
    sampling_ids::Vector{Int} # array of sampling indices belonging to this trial

    inputs::Vector{InputFolders} # contains the folder names for the samplings in this trial
    variation_ids::Vector{Vector{VariationIDs}} # variation_ids associated with each monad for each sampling

    function Trial(id::Int, n_replicates::Int, sampling_ids::Vector{Int}, inputs::Vector{InputFolders}, variation_ids::Vector{Vector{VariationIDs}})
        @assert id > 0 "id must be positive"
        n_samplings = length(sampling_ids)
        n_inputs = length(inputs)
        n_variations = length(variation_ids)
        if n_samplings != n_inputs || n_samplings != n_variations # the negation of this is n_samplings == n_inputs && n_samplings == n_folder_names && n_samplings == n_variations, which obviously means they're all the same
            throw(ArgumentError("Number of samplings, inputs, and variations must be the same"))
        end

        recordSamplingIDs(id, sampling_ids) # record the sampling ids in a .csv file

        return new(id, n_replicates, sampling_ids, inputs, variation_ids)
    end
end

function Trial(n_replicates::Int, sampling_ids::Vector{Int}, inputs::Vector{InputFolders}, variation_ids::Vector{Vector{VariationIDs}}; use_previous::Bool=true)
    id = getTrialID(sampling_ids)
    return Trial(id, n_replicates, sampling_ids, inputs, variation_ids)
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
    n_replicates = samplings[1].n_replicates
    sampling_ids = [sampling.id for sampling in samplings]
    inputs = [sampling.inputs for sampling in samplings]
    variation_ids = [sampling.variation_ids for sampling in samplings]
    return Trial(n_replicates, sampling_ids, inputs, variation_ids)
end

function getTrial(trial_id::Int, n_replicates::Int)
    df = constructSelectQuery("trials", "WHERE trial_id=$(trial_id);") |> queryToDataFrame
    if isempty(df) || isempty(readTrialSamplingIDs(trial_id))
        error("No samplings found for trial_id=$trial_id. This trial did not run.")
    end
    sampling_ids = readTrialSamplingIDs(trial_id)
    return Trial([Sampling(id; n_replicates=n_replicates) for id in sampling_ids])
end

Trial(trial_id::Integer; n_replicates::Integer=0) = getTrial(trial_id, n_replicates)

function Sampling(id::Int, n_replicates::Int, inputs::InputFolders, variation_ids::Vector{VariationIDs}; use_previous::Bool=true)
    monad_ids = createMonadIDs(n_replicates, inputs, variation_ids; use_previous=use_previous)
    return Sampling(id, n_replicates, monad_ids, inputs, variation_ids)
end 

function Sampling(trial::Trial, index::Int)
    return Sampling(trial.sampling_ids[index], trial.n_replicates, trial.inputs[index], trial.variation_ids[index])
end