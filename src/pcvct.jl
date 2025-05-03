module pcvct

using SQLite, DataFrames, LightXML, Dates, CSV, Tables, Distributions, Statistics, Random, QuasiMonteCarlo, Sobol, Compat
using PhysiCellXMLRules, PhysiCellCellCreator

export initializeModelManager, getSimulationIDs, setNumberOfParallelSims

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
include("version.jl")
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

inputs_dict = Dict{Symbol, Any}()

initialized = false

physicell_dir::String = abspath("PhysiCell")
current_physicell_version_id = missing
data_dir::String = abspath("data")
PHYSICELL_CPP::String = haskey(ENV, "PHYSICELL_CPP") ? ENV["PHYSICELL_CPP"] : "g++"
if Sys.iswindows()
    baseToExecutable(s::String) = "$(s).exe"
else
    baseToExecutable(s::String) = s
end

run_on_hpc = isRunningOnHPC()
max_number_of_parallel_simulations = 1
march_flag::String = run_on_hpc ? "x86-64" : "native"

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
    success = initializeDatabase(joinpath(data_dir, "vct.db"); auto_upgrade=auto_upgrade)
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

function initializeModelManager()
    physicell_dir = "PhysiCell"
    data_dir = "data"
    return initializeModelManager(physicell_dir, data_dir)
end

################## Selection Functions ##################

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

readMonadSimulationIDs(monad_id::Int) = readConstituentIDs(joinpath(trialFolder("monad", monad_id), "simulations.csv"))
readMonadSimulationIDs(monad::Monad) = readMonadSimulationIDs(monad.id)
readSamplingMonadIDs(sampling_id::Int) = readConstituentIDs(joinpath(trialFolder("sampling", sampling_id), "monads.csv"))
readSamplingMonadIDs(sampling::Sampling) = readSamplingMonadIDs(sampling.id)
readTrialSamplingIDs(trial_id::Int) = readConstituentIDs(joinpath(trialFolder("trial", trial_id), "samplings.csv"))
readTrialSamplingIDs(trial::Trial) = readTrialSamplingIDs(trial.id)

function getSamplingSimulationIDs(sampling_id::Int)
    monad_ids = readSamplingMonadIDs(sampling_id)
    return vcat([readMonadSimulationIDs(monad_id) for monad_id in monad_ids]...)
end

function getTrialSimulationIDs(trial_id::Int)
    sampling_ids = readTrialSamplingIDs(trial_id)
    return vcat([getSamplingSimulationIDs(sampling_id) for sampling_id in sampling_ids]...)
end

"""
    getSimulationIDs()

Return a vector of all simulation IDs in the database.

Alternate forms take a simulation, monad, sampling, or trial object (or an array of any combination of them) and return the corresponding simulation IDs.

# Examples
```
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
getSimulationIDs(monad::Monad) = readMonadSimulationIDs(monad)
getSimulationIDs(sampling::Sampling) = getSamplingSimulationIDs(sampling.id)
getSimulationIDs(trial::Trial) = getTrialSimulationIDs(trial.id)
getSimulationIDs(Ts::AbstractArray{<:AbstractTrial}) = reduce(vcat, getSimulationIDs.(Ts))

function getTrialMonads(trial_id::Int)
    sampling_ids = readTrialSamplingIDs(trial_id)
    return vcat([readSamplingMonadIDs(sampling_id) for sampling_id in sampling_ids]...)
end

getMonadIDs() = constructSelectQuery("monads"; selection="monad_id") |> queryToDataFrame |> x -> x.monad_id
getMonadIDs(monad::Monad) = [monad.id]
getMonadIDs(sampling::Sampling) = readSamplingMonadIDs(sampling)
getMonadIDs(trial::Trial) = getTrialMonads(trial.id)

################## Miscellaneous Functions ##################

function trialFolder(lower_class_str::AbstractString, id::Int)
    return joinpath(data_dir, "outputs", lower_class_str * "s", string(id))
end

function trialFolder(T::AbstractTrial)
    name = typeof(T) |> string |> lowercase
    name = split(name, ".")[end] #! remove module name that comes with the type, e.g. main.vctmodule.sampling -> sampling
    return trialFolder(name, T.id)
end

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