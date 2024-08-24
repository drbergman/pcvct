module VCTModule

# each file (includes below) has their own export statements
export initializeVCT, resetDatabase, addGridVariation, addGridRulesetsVariation, runAbstractTrial, getTrialSamplings, getSimulations, deleteSimulation
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
include("VCTRunning.jl")
include("VCTRecorder.jl")

include("../PhysiCell-XMLRules/src/PhysiCell_XMLRules.jl")
using .PhysiCell_XMLRules

physicell_dir::String = abspath("PhysiCell")
data_dir::String = abspath("data")
PHYSICELL_CPP::String = haskey(ENV, "PHYSICELL_CPP") ? ENV["PHYSICELL_CPP"] : "/opt/homebrew/bin/g++-14"

################## Initialization Functions ##################

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

function initializeVCT(path_to_physicell::String, path_to_data::String)
    # print big logo of PCVCT here
    println(pcvctLogo())
    println("----------INITIALIZING----------")
    global physicell_dir = abspath(path_to_physicell)
    global data_dir = abspath(path_to_data)
    println(rpad("Path to PhysiCell:", 20, ' ') * physicell_dir)
    println(rpad("Path to data:", 20, ' ') * data_dir)
    initializeDatabase("$(data_dir)/vct.db")
end

################## Selection Functions ##################

function selectConstituents(path_to_csv::String)
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

getMonadSimulations(monad_id::Int) = selectConstituents("$(data_dir)/outputs/monads/$(monad_id)/simulations.csv")
getMonadSimulations(monad::Monad) = getMonadSimulations(monad.id)
getSamplingMonads(sampling_id::Int) = selectConstituents("$(data_dir)/outputs/samplings/$(sampling_id)/monads.csv")
getSamplingMonads(sampling::Sampling) = getSamplingMonads(sampling.id)
getTrialSamplings(trial_id::Int) = selectConstituents("$(data_dir)/outputs/trials/$(trial_id)/samplings.csv")
getTrialSamplings(trial::Trial) = getTrialSamplings(trial.id)

function getSamplingSimulations(sampling_id::Int)
    monad_ids = getSamplingMonads(sampling_id)
    return vcat([getMonadSimulations(monad_id) for monad_id in monad_ids]...)
end

function getTrialSimulations(trial_id::Int)
    sampling_ids = getTrialSamplings(trial_id)
    return vcat([getSamplingSimulations(sampling_id) for sampling_id in sampling_ids]...)
end

getSimulations() = constructSelectQuery("simulations", "", selection="simulation_id") |> queryToDataFrame |> x -> x.simulation_id
getSimulations(simulation::Simulation) = [simulation.id]
getSimulations(monad::Monad) = getMonadSimulations(monad.id)
getSimulations(sampling::Sampling) = getSamplingSimulations(sampling.id)
getSimulations(trial::Trial) = getTrialSimulations(trial.id)

function getSimulations(class_id::VCTClassID) 
    class_id_type = getVCTClassIDType(class_id)
    if class_id_type == Simulation
        return [class_id.id]
    elseif class_id_type == Monad
        return getMonadSimulations(class_id.id)
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
    return "$(data_dir)/outputs/$(name)s/$(T.id)"
end

end