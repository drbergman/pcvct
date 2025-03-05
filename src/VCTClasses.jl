export Simulation, Monad, Sampling, Trial, InputFolders

abstract type AbstractTrial end
abstract type AbstractSampling <: AbstractTrial end
abstract type AbstractMonad <: AbstractSampling end

Base.length(T::AbstractTrial) = getSimulationIDs(T) |> length

##########################################
############   InputFolders   ############
##########################################

"""
    InputFolder

Hold the information for a single input folder.

# Fields
- `location::Symbol`: The location of the input folder, e.g. `:config`, `:custom_code`, etc. Options are defined in `data/inputs.toml`.
- `id::Int`: The ID of the input folder in the database.
- `folder::String`: The name of the input folder. It will be in `data/inputs/<path_from_inputs>`.
- `basename::Union{String,Missing}`: The basename of the input file. This can be used to determine if the input file is varied.
- `required::Bool`: Whether the input folder is required. This is defined in `data/inputs.toml`.
- `varied::Bool`: Whether the input folder is varied. This is determined by the presence of a varied basename in the input folder.
- `path_from_inputs::String`: The path from the `data/inputs` directory to the input folder. This is defined in `data/inputs.toml`.
"""
struct InputFolder
    location::Symbol
    id::Int
    folder::String
    basename::Union{String,Missing}
    required::Bool
    varied::Bool
    path_from_inputs::String

    function InputFolder(location::Symbol, id::Int, folder::String)
        location_dict = inputs_dict[location]
        required = location_dict["required"]
        if isempty(folder)
            if required
                error("Folder for $location must be provided")
            end
            return new(location, id, folder, missing, required, false, "")
        end
        path_from_inputs = joinpath(location_dict["path_from_inputs"], folder)
        basename = location_dict["basename"]
        varied = folderIsVaried(location, folder)
        if basename isa Vector
            possible_files = [joinpath(locationPath(location, folder), x) for x in basename]
            basename_index = possible_files .|> isfile |> findfirst
            if isnothing(basename_index)
                error("Neither of $possible_files exist")
            end
            basename = basename[basename_index]
        end
        return new(location, id, folder, basename, required, varied, path_from_inputs)
    end
    function InputFolder(location::Symbol, id::Int)
        folder = inputFolderName(location, id)
        return InputFolder(location, id, folder)
    end
    function InputFolder(location::Symbol, folder::String)
        id = retrieveID(location, folder)
        return InputFolder(location, id, folder)
    end
end

"""
    InputFolders

Consolidate the folder information for a simulation/monad/sampling.

Pass the folder names within the `inputs/<path_from_inputs>` directory to create an `InputFolders` object.
The `path_from_inputs` is defined in the `data/inputs.toml` file for each.
It is possible to acces the [`InputFolder`](@ref) values using index notation, e.g. `input_folders[:config]`.

Several constructors exist:
1. All folders passed as keyword arguments. Omitted folders are assumed to be \"\", i.e. those inputs are unused.
```julia
InputFolders(; config="default", custom_codes="default", rulesets_collection="default")
```
2. Pass in the required inputs as arguments and the optional inputs as keyword arguments. The required folders must be passed in alphabetical order.
Refer to the names defined in `data/inputs.toml` to see this order. Omitted optional folders are assumed to be \"\", i.e. those inputs are unused.
```julia
config_folder = "default"
custom_code_folder = "default"
ic_cell_folder = "cells_in_disc"
InputFolders(config_folder, custom_code_folder; ic_cell=ic_cell_folder)
```

# Fields
- `input_folders::NamedTuple`: The input locations defined in `data/inputs.toml` define the keys. The values are [`InputFolder`](@ref)s.
"""
struct InputFolders
    input_folders::NamedTuple

    function InputFolders(location_pairs::Vector{<:Pair{Symbol,<:Union{String,Int}}})
        locs_already_here = first.(location_pairs)
        invalid_locations = setdiff(locs_already_here, project_locations.all)
        @assert isempty(invalid_locations) "Invalid locations: $invalid_locations.\nPossible locations are: $(project_locations.all)"
        for loc in setdiff(project_locations.all, locs_already_here)
            push!(location_pairs, loc => "")
        end
        return new([loc => InputFolder(loc, val) for (loc, val) in location_pairs] |> NamedTuple)
    end

    function InputFolders(; kwargs...)
        return InputFolders([loc => val for (loc, val) in kwargs])
    end
end

function createSimpleInputFolders()
    fn_args = join(["$(location)::String" for location in project_locations.required], ", ")
    fn_kwargs = join(["$(location)::String=\"\"" for location in setdiff(project_locations.all, project_locations.required)], ", ")
    ret_val = "[$(join([":$(location) => $(location)" for location in project_locations.all], ", "))] |> InputFolders"
    """
    function InputFolders($(fn_args); $(fn_kwargs))
        return $(ret_val)
    end
    """ |> Meta.parse |> eval
    return
end

Base.getindex(input_folders::InputFolders, loc::Symbol) = input_folders.input_folders[loc]

##########################################
############   Variation IDs  ############
##########################################

"""
    VariationID

The variation IDs for any of the possibly varying inputs.

For each input type that can be varied, a record of the current variation ID for that input type.
By convention, a values of `-1` indicates that the input is not being used (hence this is disallowed for a `required` input type).
A value of `0` indicates that the base file is being used, unvaried.
Hence, if the input type is sometimes varied (such as `ic_cell` with a `cells.csv` file), this value must be `0` in such conditions.
"""
struct VariationID
    ids::NamedTuple

    function VariationID(inputs::InputFolders)
        return new((loc => inputs[loc].id == -1 ? -1 : 0 for loc in project_locations.varied) |> NamedTuple)
    end

    function VariationID(x::Vector{Pair{Symbol,Int}})
        #! this is slightly dangerous since no checks are made that the locations are valid.
        #! but it is called often enough internally that it is worth it to have this constructor without checks
        #! if this is added to the public API, then checks should be added
        return new(x |> NamedTuple)
    end
end

Base.getindex(variation_id::VariationID, loc::Symbol) = variation_id.ids[loc]

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
- `variation_id::VariationID`: contains the variation IDs for this simulation.
"""
struct Simulation <: AbstractMonad
    id::Int #! integer uniquely identifying this simulation
    inputs::InputFolders 
    variation_id::VariationID

    function Simulation(id::Int, inputs::InputFolders, variation_id::VariationID)
        @assert id > 0 "id must be positive"
        for location in project_locations.varied
            if inputs[location].required
                @assert variation_id[location] >= 0 "$(location) variation id must be non-negative"
            elseif inputs[location].id == -1
                @assert variation_id[location] == -1 "$(location) variation id must be -1 because there is associated folder indicating $(location) is not in use."
            #! now we know this location is not required and it is in use
            elseif !inputs[location].varied
                #! this particular folder is not varying it, so make sure its variation id is 0, i.e. the base file in this folder
                @assert variation_id[location] == 0 "$(inputs[location].folder) in $(location) is not varying but the variation id is not 0."
            #! now we know that the folder is being varied, so just make sure the variation id is >=0
            else
                @assert variation_id[location] >= 0 "$(location) variation id must be non-negative as the folder $(inputs[location].folder) is varying."
            end
        end
        return new(id, inputs, variation_id)
    end
end

function Simulation(inputs::InputFolders, variation_id::VariationID=VariationID(inputs))
    simulation_id = DBInterface.execute(db, 
    """
    INSERT INTO simulations (\
    physicell_version_id,\
    $(join(locationIDNames(), ",")),\
    $(join(locationVariationIDNames(), ",")),\
    status_code_id\
    ) \
    VALUES(\
    $(physicellVersionDBEntry()),\
    $(join([inputs[loc].id for loc in project_locations.all], ",")),\
    $(join([variation_id[loc] for loc in project_locations.varied],",")),\
    $(getStatusCodeID("Not Started"))
    )
    RETURNING simulation_id;
    """
    ) |> DataFrame |> x -> x.simulation_id[1]
    return Simulation(simulation_id, inputs, variation_id)
end

function getSimulation(simulation_id::Int)
    df = constructSelectQuery("simulations", "WHERE simulation_id=$(simulation_id);") |> queryToDataFrame
    if isempty(df)
        error("Simulation $(simulation_id) not in the database.")
    end
    inputs = [loc => df[1, locationIDName(loc)] for loc in project_locations.all] |> InputFolders
    variation_id = [loc => df[1, locationVarIDName(loc)] for loc in project_locations.varied] |> VariationID

    return Simulation(simulation_id, inputs, variation_id)
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
- `variation_id::VariationID`: contains the variation IDs for this monad.
"""
struct Monad <: AbstractMonad
    #! a monad is a group of simulation replicates, i.e. identical up to randomness
    id::Int #! integer uniquely identifying this monad
    n_replicates::Int #! (minimum) number of simulations belonging to this monad
    simulation_ids::Vector{Int} #! simulation ids belonging to this monad
    inputs::InputFolders #! contains the folder names for the simulations in this monad
    variation_id::VariationID

    function Monad(n_replicates::Int, inputs::InputFolders, variation_id::VariationID, use_previous::Bool)
        feature_str = """
        (\
        physicell_version_id,\
        $(join(locationIDNames(), ",")),\
        $(join(locationVariationIDNames(), ","))\
        ) \
        """
        value_str = """
        (\
        $(physicellVersionDBEntry()),\
        $(join([inputs[loc].id for loc in project_locations.all], ",")),\
        $(join([variation_id[loc] for loc in project_locations.varied],","))\
        ) \
        """
        monad_id = DBInterface.execute(db,
            """
            INSERT OR IGNORE INTO monads $feature_str VALUES $value_str RETURNING monad_id;
            """
        ) |> DataFrame |> x -> x.monad_id
        if isempty(monad_id)
            monad_id = constructSelectQuery(
                "monads",
                """
                WHERE $feature_str=$value_str
                """;
                selection="monad_id"
            ) |> queryToDataFrame |> x -> x.monad_id[1] #! get the monad_id
        else
            monad_id = monad_id[1] #! get the monad_id
        end
        return Monad(monad_id, n_replicates, inputs, variation_id, use_previous)
    end

    function Monad(id::Int, n_replicates::Int, inputs::InputFolders, variation_id::VariationID, use_previous::Bool)
        @assert id > 0 "id must be positive"
        @assert n_replicates >= 0 "n_replicates must be non-negative"

        previous_simulation_ids = readMonadSimulationIDs(id)
        new_simulation_ids = Int[]
        num_sims_to_add = n_replicates - (use_previous ? length(previous_simulation_ids) : 0)
        if num_sims_to_add > 0
            for _ = 1:num_sims_to_add
                simulation = Simulation(inputs, variation_id) #! create a new simulation
                push!(new_simulation_ids, simulation.id)
            end
            recordSimulationIDs(id, [previous_simulation_ids; new_simulation_ids]) #! record the simulation ids in a .csv file
        end

        simulation_ids = use_previous ? [previous_simulation_ids; new_simulation_ids] : new_simulation_ids

        return new(id, n_replicates, simulation_ids, inputs, variation_id)
    end

end

function Monad(inputs::InputFolders, variation_id::VariationID; use_previous::Bool=true, n_replicates::Int=0)
    Monad(n_replicates, inputs, variation_id, use_previous)
end

function getMonad(monad_id::Int, n_replicates::Int, use_previous::Bool)
    df = constructSelectQuery("monads", "WHERE monad_id=$(monad_id);") |> queryToDataFrame
    if isempty(df)
        error("Monad $(monad_id) not in the database.")
    end
    inputs = [loc => df[1, locationIDName(loc)] for loc in project_locations.all] |> InputFolders
    variation_id = [loc => df[1, locationVarIDName(loc)] for loc in project_locations.varied] |> VariationID
    return Monad(monad_id, n_replicates, inputs, variation_id, use_previous)
end

Monad(monad_id::Integer; n_replicates::Integer=0, use_previous::Bool=true) = getMonad(monad_id, n_replicates, use_previous)

function Simulation(monad::Monad)
    return Simulation(monad.inputs, monad.variation_id)
end

function Monad(simulation::Simulation)
    n_replicates = 0 #! do not impose a min length on this monad
    use_previous = true
    monad = Monad(n_replicates, simulation.inputs, simulation.variation_id, use_previous)
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

getVariationIDs(M::AbstractMonad) = [M.variation_id]

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
- `variation_ids::Vector{VariationID}`: contains the variation IDs for each monad.
"""
struct Sampling <: AbstractSampling
    #! sampling is a group of monads with config parameters varied
    id::Int #! integer uniquely identifying this sampling
    n_replicates::Int #! minimum length of each monad belonging to this sampling
    monad_ids::Vector{Int} #! array of monad indices belonging to this sampling

    inputs::InputFolders #! contains the folder names for this sampling

    variation_ids::Vector{VariationID} #! variation_ids associated with each monad

    function Sampling(id::Int, n_replicates::Int, monad_ids::AbstractVector{<:Integer}, inputs::InputFolders, variation_ids::AbstractVector{VariationID})
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
        recordMonadIDs(id, monad_ids) #! record the monad ids in a .csv file
        return new(id, n_replicates, monad_ids, inputs, variation_ids)
    end
end

function Sampling(n_replicates::Int, monad_ids::AbstractVector{<:Integer}, inputs::InputFolders, variation_ids::Vector{VariationID})
    id = -1
    sampling_ids = constructSelectQuery(
        "samplings",
        """
        WHERE (\
        physicell_version_id,\
        $(join(locationIDNames(), ","))\
        )=\
        (\
        $(physicellVersionDBEntry()),\
        $(join([inputs[loc].id for loc in project_locations.all], ","))\
        );\
        """;
        selection="sampling_id"
    ) |> queryToDataFrame |> x -> x.sampling_id
    if !isempty(sampling_ids) #! if there are previous samplings with the same parameters
        for sampling_id in sampling_ids #! check if the monad_ids are the same with any previous monad_ids
            monad_ids_in_db = readSamplingMonadIDs(sampling_id) #! get the monad_ids belonging to this sampling
            if symdiff(monad_ids_in_db, monad_ids) |> isempty #! if the monad_ids are the same
                id = sampling_id #! use the existing sampling_id
                break
            end
        end
    end

    if id==-1 #! if no previous sampling was found matching these parameters
        id = DBInterface.execute(db, 
            """
            INSERT INTO samplings \
            (\
            physicell_version_id,\
            $(join(locationIDNames(), ","))\
            ) \
            VALUES(\
            $(physicellVersionDBEntry()),\
            $(join([inputs[loc].id for loc in project_locations.all], ","))\
            ) RETURNING sampling_id;
            """
        ) |> DataFrame |> x -> x.sampling_id[1] #! get the sampling_id
    end
    return Sampling(id, n_replicates, monad_ids, inputs, variation_ids)
end

function Sampling(n_replicates::Int, inputs::InputFolders, variation_ids::AbstractArray{VariationID}; use_previous::Bool=true)
    monad_ids = createMonadIDs(n_replicates, inputs, variation_ids; use_previous=use_previous)
    return Sampling(n_replicates, monad_ids, inputs, variation_ids)
end

function Sampling(inputs::InputFolders;
                n_replicates::Integer=0,
                location_variation_ids::Dict{Symbol,<:Union{Integer,AbstractArray{<:Integer}}},
                use_previous::Bool=true)
    #! allow for passing in a single config_variation_id and/or rulesets_collection_variation_id
    #! later, can support passing in (for example) a 3x6 config_variation_ids and a 3x1 rulesets_collection_variation_ids and expanding the rulesets_collection_variation_ids to 3x6, but that can get tricky fast
    if all(x->x isa Integer, values(location_variation_ids))
        for (loc, loc_var_ids) in pairs(location_variation_ids)
            location_variation_ids[loc] = [loc_var_ids]
        end
    else
        ns = [length(x) for x in values(location_variation_ids) if !(x isa Integer)]
        @assert all(x->x==ns[1], ns) "location variation ids must have the same length if they are not integers"
        for (loc, loc_var_ids) in pairs(location_variation_ids)
            if loc_var_ids isa Integer
                location_variation_ids[loc] = fill(loc_var_ids, ns[1])
            end
        end
    end
    n = location_variation_ids |> values |> first |> length
    for loc in setdiff(project_locations.varied, keys(location_variation_ids))
        location_variation_ids[loc] = fill(inputs[loc].id==-1 ? -1 : 0, n)
    end
    variation_ids = [([loc => loc_var_ids[i] for (loc, loc_var_ids) in pairs(location_variation_ids)] |> VariationID) for i in 1:n]
    return Sampling(n_replicates, inputs, variation_ids; use_previous=use_previous) 
end

function Sampling(n_replicates::Int, monads::AbstractArray{<:AbstractMonad})
    inputs = monads[1].inputs
    for monad in monads
        if monad.inputs != inputs
            error("All monads must have the same inputs")
            #! could choose to make a trial from these here...
        end
    end
    variation_ids = [monad.variation_id for monad in monads]
    monad_ids = [monad.id for monad in monads]
    return Sampling(n_replicates, monad_ids, inputs, variation_ids) 
end

function createMonadIDs(n_replicates::Int, inputs::InputFolders, variation_ids::AbstractArray{VariationID}; use_previous::Bool=true)
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
    inputs = [loc => df[1, locationIDName(loc)] for loc in project_locations.all] |> InputFolders
    monad_df = constructSelectQuery("monads", "WHERE monad_id IN ($(join(monad_ids,",")))") |> queryToDataFrame
    variation_ids = [([loc => monad_df[i, locationVarIDName(loc)] for loc in project_locations.varied] |> VariationID) for i in 1:length(monad_ids)]
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

getVariationIDs(sampling::Sampling) = sampling.variation_ids

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
- `variation_ids::Vector{Vector{VariationID}}`: contains the variation IDs for each monad in each sampling in this trial.
"""
struct Trial <: AbstractTrial
    #! trial is a group of samplings with different ICs, custom codes, rulesets, and/or intracellulars
    id::Int #! integer uniquely identifying this trial
    n_replicates::Int #! minimum length of each monad belonging to the samplings in this trial
    sampling_ids::Vector{Int} #! array of sampling indices belonging to this trial

    inputs::Vector{InputFolders} #! contains the folder names for the samplings in this trial
    variation_ids::Vector{Vector{VariationID}} #! variation_ids associated with each monad for each sampling

    function Trial(id::Int, n_replicates::Int, sampling_ids::Vector{Int}, inputs::Vector{InputFolders}, variation_ids::Vector{Vector{VariationID}})
        @assert id > 0 "id must be positive"
        n_samplings = length(sampling_ids)
        n_inputs = length(inputs)
        n_variations = length(variation_ids)
        if n_samplings != n_inputs || n_samplings != n_variations #! the negation of this is n_samplings == n_inputs && n_samplings == n_folder_names && n_samplings == n_variations, which obviously means they're all the same
            throw(ArgumentError("Number of samplings, inputs, and variations must be the same"))
        end

        recordSamplingIDs(id, sampling_ids) #! record the sampling ids in a .csv file

        return new(id, n_replicates, sampling_ids, inputs, variation_ids)
    end
end

function Trial(n_replicates::Int, sampling_ids::Vector{Int}, inputs::Vector{InputFolders}, variation_ids::Vector{Vector{VariationID}}; use_previous::Bool=true)
    id = getTrialID(sampling_ids)
    return Trial(id, n_replicates, sampling_ids, inputs, variation_ids)
end

function getTrialID(sampling_ids::Vector{Int})
    id = -1
    trial_ids = constructSelectQuery("trials"; selection="trial_id") |> queryToDataFrame |> x -> x.trial_id
    if !isempty(trial_ids) #! if there are previous trials
        for trial_id in trial_ids #! check if the sampling_ids are the same with any previous sampling_ids
            sampling_ids_in_db = readTrialSamplingIDs(trial_id) #! get the sampling_ids belonging to this trial
            if symdiff(sampling_ids_in_db, sampling_ids) |> isempty #! if the sampling_ids are the same
                id = trial_id #! use the existing trial_id
                break
            end
        end
    end

    if id==-1 #! if no previous trial was found matching these parameters
        id = DBInterface.execute(db, "INSERT INTO trials (datetime) VALUES($(Dates.format(now(),"yymmddHHMM"))) RETURNING trial_id;") |> DataFrame |> x -> x.trial_id[1] #! get the trial_id
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

function Sampling(id::Int, n_replicates::Int, inputs::InputFolders, variation_ids::Vector{VariationID}; use_previous::Bool=true)
    monad_ids = createMonadIDs(n_replicates, inputs, variation_ids; use_previous=use_previous)
    return Sampling(id, n_replicates, monad_ids, inputs, variation_ids)
end 

function Sampling(trial::Trial, index::Int)
    return Sampling(trial.sampling_ids[index], trial.n_replicates, trial.inputs[index], trial.variation_ids[index])
end