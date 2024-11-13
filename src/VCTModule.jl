# each file (includes below) has their own export statements
export initializeVCT, resetDatabase, runAbstractTrial, readTrialSamplingIDs, getSimulationIDs, deleteSimulation

using SQLite, DataFrames, LightXML, LazyGrids, Dates, CSV, Tables, Distributions, Statistics, Random, QuasiMonteCarlo, Sobol
using PhysiCellXMLRules

# put these first as they define classes the rest rely on
include("VCTClasses.jl")
include("VCTPruner.jl")
include("VCTVariations.jl")

include("VCTCompilation.jl")
include("VCTConfiguration.jl")
include("VCTCreation.jl")
include("VCTDatabase.jl") 
include("VCTDeletion.jl")
# include("VCTExtraction.jl")
include("VCTICCell.jl")
include("VCTLoader.jl")
include("VCTMovie.jl")
include("VCTRunner.jl")
include("VCTRecorder.jl")
include("VCTSensitivity.jl")
include("VCTVersion.jl")

include("VCTAnalysis.jl")

include("VCTPhysiCellStudio.jl")

VERSION >= v"1.11" && include("public.julia")

physicell_dir::String = abspath("PhysiCell")
data_dir::String = abspath("data")
PHYSICELL_CPP::String = haskey(ENV, "PHYSICELL_CPP") ? ENV["PHYSICELL_CPP"] : "/opt/homebrew/bin/g++-14"
if Sys.iswindows()
    baseToExecutable(s::String) = "$(s).exe"
else
    baseToExecutable(s::String) = s
end

################## Initialization Functions ##################

"""
`pcvctLogo() -> String`

Returns a string representation of the PCVCT logo.
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
`initializeVCT(path_to_physicell::String, path_to_data::String)`

Initializes the VCT environment by setting the paths to PhysiCell and data directories, and initializing the database.

# Arguments
- `path_to_physicell::String`: Path to the PhysiCell directory.
- `path_to_data::String`: Path to the data directory.
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
    println(rpad("Compiler:", 20, ' ') * PHYSICELL_CPP)
    println(rpad("pcvct version:", 20, ' ') * string(pcvctVersion()))
    flush(stdout)
end

################## Selection Functions ##################

"""
`readConstituentIDs(path_to_csv::String) -> Vector{Int}`

Reads constituent IDs from a CSV file.

# Arguments
- `path_to_csv::String`: Path to the CSV file.

# Returns
- `Vector{Int}`: A vector of constituent IDs.
"""
function readConstituentIDs(path_to_csv::String)
    if !isfile(path_to_csv)
        return Int[]
    end
    df = CSV.read(path_to_csv, DataFrame; header=false, silencewarnings=true, types=String, delim=",")
    ids = Int[]
    for i in axes(df,1)
        s = df.Column1[i]
        I = split(s,":") .|> string .|> x->parse(Int,x)
        if length(I)==1
            push!(ids,I[1])
        else
            append!(ids,I[1]:I[2])
        end
    end
    return ids
end


"""
`constituentsType(T::AbstractTrial) -> Type`

Returns the type of constituents for a given AbstractTrial.

# Arguments
- `T::AbstractTrial`: An AbstractTrial object.

# Returns
- `Type`: The type of constituents.
"""
constituentsType(trial::Trial) = Sampling
constituentsType(sampling::Sampling) = Monad
constituentsType(monad::Monad) = Simulation

"""
`readConstituentIDs(T::AbstractTrial)`

Reads the constituent IDs for a given trial type `T`.

# Arguments
- `T::AbstractTrial`: An instance of a trial type.

# Returns
- A list of constituent IDs read from a CSV file.

# Details
The function constructs a file path based on the type and ID of the trial `T`. 
It then reads the constituent IDs from a CSV file located at the constructed path.
"""
function readConstituentIDs(T::AbstractTrial)
    type_str = typeof(T) |> string |> lowercase
    path_to_folder = joinpath(data_dir, "outputs", type_str * "s", string(T.id))
    filename = lowercase(string(constituentsType(T))) * "s"
    return readConstituentIDs(joinpath(path_to_folder, filename * ".csv"))
end

readMonadSimulationIDs(monad_id::Int) = readConstituentIDs(joinpath(data_dir, "outputs", "monads", string(monad_id), "simulations.csv"))
readMonadSimulationIDs(monad::Monad) = readMonadSimulationIDs(monad.id)
readSamplingMonadIDs(sampling_id::Int) = readConstituentIDs(joinpath(data_dir, "outputs", "samplings", string(sampling_id), "monads.csv"))
readSamplingMonadIDs(sampling::Sampling) = readSamplingMonadIDs(sampling.id)
readTrialSamplingIDs(trial_id::Int) = readConstituentIDs(joinpath(data_dir, "outputs", "trials", string(trial_id), "samplings.csv"))
readTrialSamplingIDs(trial::Trial) = readTrialSamplingIDs(trial.id)

function getSamplingSimulations(sampling_id::Int)
    monad_ids = readSamplingMonadIDs(sampling_id)
    return vcat([readMonadSimulationIDs(monad_id) for monad_id in monad_ids]...)
end

function getTrialSimulations(trial_id::Int)
    sampling_ids = readTrialSamplingIDs(trial_id)
    return vcat([getSamplingSimulations(sampling_id) for sampling_id in sampling_ids]...)
end

getSimulationIDs() = constructSelectQuery("simulations", "", selection="simulation_id") |> queryToDataFrame |> x -> x.simulation_id
getSimulationIDs(simulation::Simulation) = [simulation.id]
getSimulationIDs(monad::Monad) = readMonadSimulationIDs(monad.id)
getSimulationIDs(sampling::Sampling) = getSamplingSimulations(sampling.id)
getSimulationIDs(trial::Trial) = getTrialSimulations(trial.id)
getSimulationIDs(Ts::AbstractArray{<:AbstractTrial}) = vcat([getSimulationIDs(T) for T in Ts]...)

function getTrialMonads(trial_id::Int)
    sampling_ids = readTrialSamplingIDs(trial_id)
    return vcat([readSamplingMonadIDs(sampling_id) for sampling_id in sampling_ids]...)
end

getMonadIDs() = constructSelectQuery("monads", "", selection="monad_id") |> queryToDataFrame |> x -> x.monad_id
getMonadIDs(monad::Monad) = [monad.id]
getMonadIDs(sampling::Sampling) = readSamplingMonadIDs(sampling.id)
getMonadIDs(trial::Trial) = getTrialMonads(trial.id)

function getSimulationIDs(class_id::VCTClassID) 
    class_id_type = getVCTClassIDType(class_id)
    if class_id_type == Simulation
        return [class_id.id]
    elseif class_id_type == Monad
        return readMonadSimulationIDs(class_id.id)
    elseif class_id_type == Sampling
        return getSamplingSimulations(class_id.id)
    elseif class_id_type == Trial
        return getTrialSimulations(class_id.id)
    else
        error(error_string)
    end
end

################## Miscellaneous Functions ##################

function getOutputFolder(T::AbstractTrial)
    name = typeof(T) |> string |> lowercase
    name = split(name, ".")[end] # remove module name that comes with the type, e.g. main.vctmodule.sampling -> sampling
    return joinpath(data_dir, "outputs", name * "s", string(T.id))
end
