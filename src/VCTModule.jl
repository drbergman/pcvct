using SQLite, DataFrames, LightXML, Dates, CSV, Tables, Distributions, Statistics, Random, QuasiMonteCarlo, Sobol
using PhysiCellXMLRules, PhysiCellCellCreator

export initializeVCT, getSimulationIDs, setNumberOfParallelSims

# put these first as they define classes the rest rely on
include("VCTClasses.jl")
include("VCTPruner.jl")
include("VCTVariations.jl")

include("VCTCompilation.jl")
include("VCTConfiguration.jl")
include("VCTCreation.jl")
include("VCTDatabase.jl") 
include("VCTDeletion.jl")
include("VCTICCell.jl")
include("VCTRunner.jl")
include("VCTRecorder.jl")
include("VCTUp.jl")
include("VCTVersion.jl")
include("VCTPhysiCellVersion.jl")
include("VCTHPC.jl")

include("VCTUserAPI.jl")

include("VCTLoader.jl")

include("VCTAnalysis.jl")
include("VCTSensitivity.jl")
include("VCTImport.jl")
include("VCTMovie.jl")

include("VCTPhysiCellStudio.jl")
include("VCTExport.jl")

VERSION >= v"1.11" && include("public.julia")

initialized = false

physicell_dir::String = abspath("PhysiCell")
current_physicell_version_id = missing
data_dir::String = abspath("data")
PHYSICELL_CPP::String = haskey(ENV, "PHYSICELL_CPP") ? ENV["PHYSICELL_CPP"] : "/opt/homebrew/bin/g++-14"
if Sys.iswindows()
    baseToExecutable(s::String) = "$(s).exe"
else
    baseToExecutable(s::String) = s
end

run_on_hpc = isRunningOnHPC()
max_number_of_parallel_simulations = 1
march_flag = run_on_hpc ? "x86-64" : "native"

sbatch_options = defaultJobOptions() # this is a dictionary that will be used to pass options to the sbatch command

function __init__()
    global max_number_of_parallel_simulations = haskey(ENV, "PCVCT_NUM_PARALLEL_SIMS") ? parse(Int, ENV["PCVCT_NUM_PARALLEL_SIMS"]) : 1
    global path_to_python = haskey(ENV, "PCVCT_PYTHON_PATH") ? ENV["PCVCT_PYTHON_PATH"] : missing 
    global path_to_studio = haskey(ENV, "PCVCT_STUDIO_PATH") ? ENV["PCVCT_STUDIO_PATH"] : missing
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
    initializeVCT(path_to_physicell::String, path_to_data::String)

Initialize the VCT environment by setting the paths to PhysiCell and data directories, and initializing the database.

# Arguments
- `path_to_physicell::String`: Path to the PhysiCell directory as either an absolute or relative path.
- `path_to_data::String`: Path to the data directory as either an absolute or relative path.
"""
function initializeVCT(path_to_physicell::String, path_to_data::String; auto_upgrade::Bool=false)
    # print big logo of PCVCT here
    println(pcvctLogo())
    println("----------INITIALIZING----------")
    global physicell_dir = abspath(path_to_physicell)
    global data_dir = abspath(path_to_data)
    println(rpad("Path to PhysiCell:", 20, ' ') * physicell_dir)
    println(rpad("Path to data:", 20, ' ') * data_dir)
    success = initializeDatabase(joinpath(data_dir, "vct.db"); auto_upgrade=auto_upgrade)
    if !success
        global db = SQLite.DB()
        println("Database initialization failed.")
        return
    end
    println(rpad("PhysiCell version:", 20, ' ') * physicellInfo())
    println(rpad("pcvct version:", 20, ' ') * string(pcvctVersion()))
    println(rpad("Compiler:", 20, ' ') * PHYSICELL_CPP)
    println(rpad("Running on HPC:", 20, ' ') * string(run_on_hpc))
    println(rpad("Max parallel sims:", 20, ' ') * string(max_number_of_parallel_simulations))
    flush(stdout)
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

readMonadSimulationIDs(monad_id::Int) = readConstituentIDs(joinpath(outputFolder("monad", monad_id), "simulations.csv"))
readMonadSimulationIDs(monad::Monad) = readMonadSimulationIDs(monad.id)
readSamplingMonadIDs(sampling_id::Int) = readConstituentIDs(joinpath(outputFolder("sampling", sampling_id), "monads.csv"))
readSamplingMonadIDs(sampling::Sampling) = readSamplingMonadIDs(sampling.id)
readTrialSamplingIDs(trial_id::Int) = readConstituentIDs(joinpath(outputFolder("trial", trial_id), "samplings.csv"))
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
getSimulationIDs(Ts::AbstractArray{<:AbstractTrial}) = vcat([getSimulationIDs(T) for T in Ts]...)

function getTrialMonads(trial_id::Int)
    sampling_ids = readTrialSamplingIDs(trial_id)
    return vcat([readSamplingMonadIDs(sampling_id) for sampling_id in sampling_ids]...)
end

getMonadIDs() = constructSelectQuery("monads"; selection="monad_id") |> queryToDataFrame |> x -> x.monad_id
getMonadIDs(monad::Monad) = [monad.id]
getMonadIDs(sampling::Sampling) = readSamplingMonadIDs(sampling)
getMonadIDs(trial::Trial) = getTrialMonads(trial.id)

################## Miscellaneous Functions ##################

function outputFolder(lower_class_str::AbstractString, id::Int)
    return joinpath(data_dir, "outputs", lower_class_str * "s", string(id))
end

function outputFolder(T::AbstractTrial)
    name = typeof(T) |> string |> lowercase
    name = split(name, ".")[end] # remove module name that comes with the type, e.g. main.vctmodule.sampling -> sampling
    return outputFolder(name, T.id)
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