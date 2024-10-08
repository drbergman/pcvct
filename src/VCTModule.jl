# each file (includes below) has their own export statements
export initializeVCT, resetDatabase, addGridVariation, addGridRulesetsVariation, runAbstractTrial, readTrialSamplings, getSimulations, deleteSimulation
export addLHSVariation, addLHSRulesetsVariation
export GridVariation, LHSVariation, addVariations

using SQLite, DataFrames, LightXML, LazyGrids, Dates, CSV, Tables, Distributions, Statistics, Random, QuasiMonteCarlo, Sobol
using MAT # files for VCTLoader.jl

include("VCTClasses.jl")
include("VCTVariations.jl")
include("VCTDatabase.jl") 
include("VCTConfiguration.jl")
include("VCTExtraction.jl")
include("VCTLoader.jl")
include("VCTSensitivity.jl")
include("VCTCompilation.jl")
include("VCTDeletion.jl")
include("VCTRunner.jl")
include("VCTRecorder.jl")

include("../PhysiCell-XMLRules/src/PhysiCell_XMLRules.jl")
using .PhysiCell_XMLRules

physicell_dir::String = abspath("PhysiCell")
data_dir::String = abspath("data")
PHYSICELL_CPP::String = haskey(ENV, "PHYSICELL_CPP") ? ENV["PHYSICELL_CPP"] : "/opt/homebrew/bin/g++-14"

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
function initializeVCT(path_to_physicell::String, path_to_data::String)
    # print big logo of PCVCT here
    println(pcvctLogo())
    println("----------INITIALIZING----------")
    global physicell_dir = abspath(path_to_physicell)
    global data_dir = abspath(path_to_data)
    println(rpad("Path to PhysiCell:", 20, ' ') * physicell_dir)
    println(rpad("Path to data:", 20, ' ') * data_dir)
    initializeDatabase("$(data_dir)/vct.db")
    println(rpad("Compiler:", 20, ' ') * PHYSICELL_CPP)
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
    path_to_folder = "$(data_dir)/outputs/$(type_str)s/$(T.id)"
    filename = lowercase(string(constituentsType(T))) * "s"
    return readConstituentIDs("$(path_to_folder)/$(filename).csv")
end

readMonadSimulations(monad_id::Int) = readConstituentIDs("$(data_dir)/outputs/monads/$(monad_id)/simulations.csv")
readMonadSimulations(monad::Monad) = readMonadSimulations(monad.id)
readSamplingMonads(sampling_id::Int) = readConstituentIDs("$(data_dir)/outputs/samplings/$(sampling_id)/monads.csv")
readSamplingMonads(sampling::Sampling) = readSamplingMonads(sampling.id)
readTrialSamplings(trial_id::Int) = readConstituentIDs("$(data_dir)/outputs/trials/$(trial_id)/samplings.csv")
readTrialSamplings(trial::Trial) = readTrialSamplings(trial.id)

function getSamplingSimulations(sampling_id::Int)
    monad_ids = readSamplingMonads(sampling_id)
    return vcat([readMonadSimulations(monad_id) for monad_id in monad_ids]...)
end

function getTrialSimulations(trial_id::Int)
    sampling_ids = readTrialSamplings(trial_id)
    return vcat([getSamplingSimulations(sampling_id) for sampling_id in sampling_ids]...)
end

getSimulations() = constructSelectQuery("simulations", "", selection="simulation_id") |> queryToDataFrame |> x -> x.simulation_id
getSimulations(simulation::Simulation) = [simulation.id]
getSimulations(monad::Monad) = readMonadSimulations(monad.id)
getSimulations(sampling::Sampling) = getSamplingSimulations(sampling.id)
getSimulations(trial::Trial) = getTrialSimulations(trial.id)

function getSimulations(class_id::VCTClassID) 
    class_id_type = getVCTClassIDType(class_id)
    if class_id_type == Simulation
        return [class_id.id]
    elseif class_id_type == Monad
        return readMonadSimulations(class_id.id)
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
    return "$(data_dir)/outputs/$(name)s/$(T.id)"
end