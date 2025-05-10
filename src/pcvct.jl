module pcvct

using SQLite, DataFrames, LightXML, Dates, CSV, Tables, Distributions, Statistics, Random, QuasiMonteCarlo, Sobol, Compat
using PhysiCellXMLRules, PhysiCellCellCreator

export initializeModelManager, getSimulationIDs, setNumberOfParallelSims, getMonadIDs

#! put these first as they define classes the rest rely on
include("classes.jl")
include("pruner.jl")
include("variations.jl")

include("project_configuration.jl")
include("compilation.jl")
include("configuration.jl")
include("creation.jl")
include("database.jl")
include("deletion.jl")
include("ic_cell.jl")
include("ic_ecm.jl")
include("runner.jl")
include("recorder.jl")
include("up.jl")
include("pcvct_version.jl")
include("physicell_version.jl")
include("hpc.jl")
include("components.jl")

include("user_api.jl")

include("loader.jl")

include("analysis/analysis.jl")
include("sensitivity.jl")
include("import.jl")
include("movie.jl")

include("physicell_studio.jl")
include("export.jl")

"""
    inputs_dict::Dict{Symbol, Any}

A dictionary that maps the types of inputs to the data that defines how they are set up and what they can do.
Read in from the `inputs.toml` file in the `data` directory.
"""
inputs_dict = Dict{Symbol, Any}()

"""
    initialized::Bool

A boolean that indicates whether a project database has been initialized to be used with pcvct.
"""
initialized = false

"""
    physicell_dir::String

The path to the PhysiCell directory. This is set when the model manager is initialized.
"""
physicell_dir::String = abspath("PhysiCell")

"""
    current_physicell_version_id::Int

The ID of the current version of PhysiCell being used as defined in the database. This is set when the model manager is initialized.
"""
current_physicell_version_id = missing

"""
    data_dir::String

The path to the data directory. This is set when the model manager is initialized.
"""
data_dir::String = abspath("data")

"""
    PHYSICELL_CPP::String

The compiler used to compile the PhysiCell code. This is set when the model manager is initialized.
"""
PHYSICELL_CPP::String = haskey(ENV, "PHYSICELL_CPP") ? ENV["PHYSICELL_CPP"] : "g++"

"""
    baseToExecutable(s::String)

Convert a string to an executable name based on the operating system.
If the operating system is Windows, append ".exe" to the string.
"""
function baseToExecutable end
if Sys.iswindows()
    baseToExecutable(s::String) = "$(s).exe"
else
    baseToExecutable(s::String) = s
end

"""
    run_on_hpc::Bool

A boolean that indicates whether the code is running on an HPC environment.

This is set to true if the `sbatch` command is available when compiling pcvct.
"""
run_on_hpc = isRunningOnHPC()

"""
    max_number_of_parallel_simulations::Int

The maximum number of parallel simulations that can be run at once.
If running on an HPC, this is ignored and instead pcvct will queue one job per simulation.
"""
max_number_of_parallel_simulations = 1

"""
    march_flag::String

The march flag to be used when compiling the code.

If running on an HPC, this is set to "x86-64" which will work across different CPU manufacturers that may be present on an HPC.
Otherwise, set to "native".
"""
march_flag::String = run_on_hpc ? "x86-64" : "native"

"""
    sbatch_options::Dict{String,Any}

A dictionary that will be used to pass options to the sbatch command.

The keys are the flag names and the values are the values used for the flag.
This is initialized using [`defaultJobOptions`](@ref) and can be modified using [`setJobOptions`](@ref).
"""
sbatch_options::Dict{String,Any} = defaultJobOptions() #! this is a dictionary that will be used to pass options to the sbatch command

function __init__()
    global max_number_of_parallel_simulations = haskey(ENV, "PCVCT_NUM_PARALLEL_SIMS") ? parse(Int, ENV["PCVCT_NUM_PARALLEL_SIMS"]) : 1
    global path_to_python = haskey(ENV, "PCVCT_PYTHON_PATH") ? ENV["PCVCT_PYTHON_PATH"] : missing
    global path_to_studio = haskey(ENV, "PCVCT_STUDIO_PATH") ? ENV["PCVCT_STUDIO_PATH"] : missing
    global path_to_magick = haskey(ENV, "PCVCT_IMAGEMAGICK_PATH") ? ENV["PCVCT_IMAGEMAGICK_PATH"] : (Sys.iswindows() ? missing : "/opt/homebrew/bin")
    global path_to_ffmpeg = haskey(ENV, "PCVCT_FFMPEG_PATH") ? ENV["PCVCT_FFMPEG_PATH"] : (Sys.iswindows() ? missing : "/opt/homebrew/bin")
end

################## Initialization Functions ##################

"""
    pcvctLogo()

Return a string representation of the awesome pcvct logo.
"""
function pcvctLogo()
    return """
    \n
    ▐▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▌
    ▐                                                                     ▌
    ▐   ███████████    █████████  █████   █████   █████████  ███████████  ▌
    ▐  ░░███░░░░░███  ███░░░░░███░░███   ░░███   ███░░░░░███░█░░░███░░░█  ▌
    ▐   ░███    ░███ ███     ░░░  ░███    ░███  ███     ░░░ ░   ░███  ░   ▌
    ▐   ░██████████ ░███          ░███    ░███ ░███             ░███      ▌
    ▐   ░███░░░░░░  ░███          ░░███   ███  ░███             ░███      ▌
    ▐   ░███        ░░███     ███  ░░░█████░   ░░███     ███    ░███      ▌
    ▐   █████        ░░█████████     ░░███      ░░█████████     █████     ▌
    ▐  ░░░░░          ░░░░░░░░░       ░░░        ░░░░░░░░░     ░░░░░      ▌
    ▐                                                                     ▌
    ▐▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▌
    \n
      """
end

"""
    initializeModelManager(path_to_physicell::String, path_to_data::String)

Initialize the VCT environment by setting the paths to PhysiCell and data directories, and initializing the database.

# Arguments
- `path_to_physicell::String`: Path to the PhysiCell directory as either an absolute or relative path.
- `path_to_data::String`: Path to the data directory as either an absolute or relative path.
"""
function initializeModelManager(path_to_physicell::String, path_to_data::String; auto_upgrade::Bool=false)
    #! print big logo of PCVCT here
    println(pcvctLogo())
    println("----------INITIALIZING----------")
    global physicell_dir = abspath(path_to_physicell)
    global data_dir = abspath(path_to_data)
    println(rpad("Path to PhysiCell:", 25, ' ') * physicell_dir)
    println(rpad("Path to data:", 25, ' ') * data_dir)
    success = parseProjectInputsConfigurationFile()
    if !success
        println("Project configuration file parsing failed.")
        return
    end
    println(rpad("Path to inputs.toml:", 25, ' ') * joinpath(data_dir, "inputs.toml"))
    path_to_database = joinpath(data_dir, "vct.db")
    success = initializeDatabase(path_to_database; auto_upgrade=auto_upgrade)
    println(rpad("Path to database:", 25, ' ') * path_to_database)
    if !success
        global db = SQLite.DB()
        println("Database initialization failed.")
        return
    end
    println(rpad("PhysiCell version:", 25, ' ') * physicellInfo())
    println(rpad("pcvct version:", 25, ' ') * string(pcvctVersion()))
    println(rpad("Compiler:", 25, ' ') * PHYSICELL_CPP)
    println(rpad("Running on HPC:", 25, ' ') * string(run_on_hpc))
    println(rpad("Max parallel sims:", 25, ' ') * string(max_number_of_parallel_simulations))
    flush(stdout)
end

"""
    initializeModelManager()

Initialize the VCT environment assuming that the PhysiCell and data directories are in the current working directory.
"""
function initializeModelManager()
    physicell_dir = "PhysiCell"
    data_dir = "data"
    return initializeModelManager(physicell_dir, data_dir)
end

################## Selection Functions ##################

"""
    constituentsType(T::Type{<:AbstractTrial})
    constituentsType(T::AbstractTrial)

Return the type of the constituents of `T`. Used in the [`readConstituentIDs`](@ref) function.
"""
constituentsType(::Type{Simulation}) = throw(ArgumentError("Type Simulation does not have constituents."))
constituentsType(::Type{Monad}) = Simulation
constituentsType(::Type{Sampling}) = Monad
constituentsType(::Type{Trial}) = Sampling

constituentsType(T::AbstractTrial) = constituentsType(typeof(T))

"""
    constituentsTypeFilename(T::Type{<:AbstractTrial})
    constituentsTypeFilename(T::AbstractTrial)

Return the filename of the constituents of `T`. Used in the [`readConstituentIDs`](@ref) function.
"""
constituentsTypeFilename(T) = "$(constituentsType(T))s.csv"

"""
    readConstituentIDs(T::AbstractTrial)

Read a CSV file containing constituent IDs from `T` and return them as a vector of integers.

For a trial, this is the sampling IDs.
For a sampling, this is the monad IDs.
For a monad, this is the simulation IDs.

# Examples
```julia
ids = readConstituentIDs(Sampling(1)) # read the IDs of the monads in sampling 1
ids = readConstituentIDs(Sampling, 1) # identical to above but does not need to create the Sampling object

ids = readConstituentIDs(Monad, 1) # read the IDs of the simulations in monad 1
ids = readConstituentIDs(Trial, 1) # read the IDs of the samplings in trial 1
```
"""
function readConstituentIDs(path_to_csv::String)
    if !isfile(path_to_csv)
        return Int[]
    end
    df = CSV.read(path_to_csv, DataFrame; header=false, silencewarnings=true, types=String, delim=",")
    ids = Int[]
    for i in axes(df,1)
        s = df.Column1[i]
        I = split(s,":") .|> x->parse(Int,x)
        if length(I)==1
            push!(ids,I[1])
        else
            append!(ids,I[1]:I[2])
        end
    end
    return ids
end

readConstituentIDs(T::AbstractTrial) = readConstituentIDs(joinpath(trialFolder(T), constituentsTypeFilename(T)))
readConstituentIDs(T::Type{<:AbstractTrial}, id::Int) = readConstituentIDs(joinpath(trialFolder(T, id), constituentsTypeFilename(T)))

"""
    getSamplingSimulationIDs(sampling_id::Int)

Internal function to get the simulation IDs for a given sampling ID. Users should use [`getSimulationIDs`](@ref) instead.
"""
function getSamplingSimulationIDs(sampling_id::Int)
    monad_ids = readConstituentIDs(Sampling, sampling_id)
    return vcat([readConstituentIDs(Monad, monad_id) for monad_id in monad_ids]...)
end

"""
    getTrialSimulationIDs(trial_id::Int)

Internal function to get the simulation IDs for a given trial ID. Users should use [`getSimulationIDs`](@ref) instead.
"""
function getTrialSimulationIDs(trial_id::Int)
    sampling_ids = readConstituentIDs(Trial, trial_id)
    return vcat([getSamplingSimulationIDs(sampling_id) for sampling_id in sampling_ids]...)
end

"""
    getSimulationIDs()

Return a vector of all simulation IDs in the database.

Alternate forms take a simulation, monad, sampling, or trial object (or an array of any combination of them) and return the corresponding simulation IDs.

# Examples
```julia
getSimulationIDs() # all simulation IDs in the database
getSimulationIDs(simulation) # just a vector with the simulation ID, i.e. [simulation.id]
getSimulationIDs(monad) # all simulation IDs in a monad
getSimulationIDs(sampling) # all simulation IDs in a sampling
getSimulationIDs(trial) # all simulation IDs in a trial
getSimulationIDs([trial1, trial2]) # all simulation IDs between trial1 and trial2
```
"""
getSimulationIDs() = constructSelectQuery("simulations"; selection="simulation_id") |> queryToDataFrame |> x -> x.simulation_id
getSimulationIDs(simulation::Simulation) = [simulation.id]
getSimulationIDs(monad::Monad) = readConstituentIDs(monad)
getSimulationIDs(sampling::Sampling) = getSamplingSimulationIDs(sampling.id)
getSimulationIDs(trial::Trial) = getTrialSimulationIDs(trial.id)
getSimulationIDs(Ts::AbstractArray{<:AbstractTrial}) = reduce(vcat, getSimulationIDs.(Ts))

"""
    getTrialMonads(trial_id::Int)

Internal function to get the monad IDs for a given trial ID. Users should use [`getMonadIDs`](@ref) instead.
"""
function getTrialMonads(trial_id::Int)
    sampling_ids = readConstituentIDs(Trial, trial_id)
    return vcat([readConstituentIDs(Sampling, sampling_id) for sampling_id in sampling_ids]...)
end

"""
    getMonadIDs()

Return a vector of all monad IDs in the database.

Alternate forms take a monad, sampling, or trial object (or an array of any combination of them) and return the corresponding monad IDs.

# Examples
```julia
getMonadIDs() # all monad IDs in the database
getMonadIDs(monad) # just a vector with the monad ID, i.e. [monad.id]
getMonadIDs(sampling) # all monad IDs in a sampling
getMonadIDs(trial) # all monad IDs in a trial
getMonadIDs([trial1, trial2]) # all monad IDs between trial1 and trial2
```
"""
getMonadIDs() = constructSelectQuery("monads"; selection="monad_id") |> queryToDataFrame |> x -> x.monad_id
getMonadIDs(monad::Monad) = [monad.id]
getMonadIDs(sampling::Sampling) = readConstituentIDs(sampling)
getMonadIDs(trial::Trial) = getTrialMonads(trial.id)
getMonadIDs(Ts::AbstractArray{<:AbstractTrial}) = reduce(vcat, getMonadIDs.(Ts))

################## Miscellaneous Functions ##################

# """
#     trialFolder(lower_class_str::AbstractString, id::Int)

# Return the path to the [`AbstractTrial`](@ref) folder for a given class string and ID.
# """
# function trialFolder(lower_class_str::AbstractString, id::Int)
#     return joinpath(data_dir, "outputs", lower_class_str * "s", string(id))
# end

"""
    trialFolder(T::Type{<:AbstractTrial}, id::Int)

Return the path to the folder for a given subtype of [`AbstractTrial`](@ref) and ID.

# Examples
```julia
trialFolder(Simulation, 1)
# output
"abs/path/to/data/outputs/simulations/1"
```
"""
trialFolder(T::Type{<:AbstractTrial}, id::Int) = joinpath(data_dir, "outputs", "$(lowerClassString(T))s", string(id))

"""
    trialFolder(T::Type{<:AbstractTrial})

Return the path to the folder for the [`AbstractTrial`](@ref) object, `T`.

# Examples
```julia
simulation = Simulation(1)
trialFolder(Simulation)
# output
"abs/path/to/data/outputs/simulations/1"
```
"""
trialFolder(T::AbstractTrial) = trialFolder(typeof(T), T.id)

"""
    lowerClassString(T::AbstractTrial)
    lowerClassString(T::Type{<:AbstractTrial})

Return the lowercase string representation of the type of `T`, excluding the module name. Without this, it may return, e.g., Main.pcvct.Sampling.

# Examples
```julia
lowerClassString(Simulation) # "simulation"
lowerClassString(Simulation(1)) # "simulation"
```
"""
function lowerClassString(T::Type{<:AbstractTrial})
    name = string(T) |> lowercase
    return split(name, ".")[end]
end

lowerClassString(T::AbstractTrial) = lowerClassString(typeof(T))

"""
    setMarchFlag(flag::String)

Set the march flag to `flag`. Used for compiling the PhysiCell code.
"""
function setMarchFlag(flag::String)
    global march_flag = flag
end

"""
    setNumberOfParallelSims(n::Int)

Set the maximum number of parallel simulations to `n`.
"""
function setNumberOfParallelSims(n::Int)
    global max_number_of_parallel_simulations = n
end

end