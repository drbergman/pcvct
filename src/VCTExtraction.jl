module VCTExtraction

export loadTimeTimeSeries, loadCellCountTimeSeries, loadCellDataTimeSeries, loadVCT

using MAT, LightXML, SQLite, DataFrames, CSV

home_dir = cd(pwd,homedir())
data_dir = "./data"

include("VCTModule.jl")
# include("VCTConfiguration.jl")
# include("VCTDatabase.jl")

using .VCTModule
# using .VCTConfiguration
# using .VCTDatabase

db, ~ = initializeDatabase()

function loadVCT(path_to_data)
    global data_dir = path_to_data
    global db, _ = initializeDatabase(path_to_data * "/vct.db")
end

############# Helper functions #############

function grabOutputFiles(path_to_output_folder::String, filename_suffix::String)
    return path_to_output_folder .* ["initial" * filename_suffix
        readdir(path_to_output_folder) |> x -> filter!(endswith(filename_suffix), x) |> x -> filter!(startswith("output"), x)
        "final" * filename_suffix]
end

function getLabelIndex(path_to_xml::String, label::String)
    xml_path = ["cellular_information", "cell_populations", "cell_population", "custom", "simplified_data", "labels"]
    openXML(path_to_xml)
    labels_element = retrieveElement(xml_path)
    for label_element in child_elements(labels_element)
        if content(label_element) == label
            label_ind_start = attribute(label_element, "index"; required=true) |> x -> parse(Int, x)
            label_ind_width = attribute(label_element, "size"; required=true) |> x -> parse(Int, x)
            closeXML()
            return label_ind_start .+ (1:label_ind_width)
        end
    end
    closeXML()
end

function getSubstrateID(path_to_xml::String, name::String)
    xml_path = ["microenvironment","domain","variables"]
    openXML(path_to_xml)
    variables_element = retrieveElement(xml_path)
    for variable_element in child_elements(variables_element)
        if attribute(variable_element, "name"; required=true)==name
            substrate_id = attribute(variable_element, "ID"; required=true) |> x->parse(Int,x)
            closeXML()
            return substrate_id
        end
    end
    closeXML()
end

function selectSimulations(; patient_id::Int, variation_id::Int, cohort_id::Int)
    return DBInterface.execute(db, "SELECT simulation_id FROM simulations WHERE (patient_id, variation_id, cohort_id)=($(patient_id),$(variation_id),$(cohort_id));") |> DataFrame |> x -> x.simulation_id
end

############# Atomic extraction functions #############

function extractTime(path_to_output_file::String)
    xml_path = ["metadata", "current_time"]
    openXML(path_to_output_file)
    t = getField(xml_path) |> x -> parse(Float64, x)
    closeXML()
    return t
end

function extractCellCount(path_to_output_file::String)
    return matread(path_to_output_file)["cell"] |> x -> size(x, 2)
end

function extractCellData(path_to_output_file::String, label_ind::UnitRange{Int})
    return matread(path_to_output_file)["cell"][label_ind, :]
end

function extractCellTypeCount(path_to_output_file::String, cell_type_id::Vector{Int}, label_ind::UnitRange{Int})
    return extractCellData(path_to_output_file, label_ind) |> vec |> (x -> x .== (cell_type_id')) |> x -> sum(x; dims=1)
end

function extractCellTypeCount(path_to_output_file::String, cell_type_id::Int, label_ind::UnitRange{Int})
    return extractCellTypeCount(path_to_output_file, [cell_type_id], label_ind)[1]
end

function extractSubstrateDensity(path_to_output_file::String, substrate_id::Vector{Int})
    return matread(path_to_output_file)["multiscale_microenvironmen"][5 .+ substrate_id, :]::Matrix{Float64} # (substrates,voxels)
end

function extractSubstrateDensity(path_to_output_file::String, substrate_id::Int)
    return extractSubstrateDensity(path_to_output_file, [substrate_id])
end

############# Whole simulation loading functions #############

function loadTimeTimeSeries(path_to_output_folder::String)
    files = grabOutputFiles(path_to_output_folder, ".xml")
    return [extractTime(file) for file in files]
end

function loadTimeTimeSeries(path_to_output_folders::Vector{String})
    return [loadTimeTimeSeries(path_to_output_folder) for path_to_output_folder in path_to_output_folders]
end

function loadTimeTimeSeries(simulation_id::Union{Int,Vector{Int}})
    return loadTimeTimeSeries([data_dir*"/simulations/$d/output/" for d in simulation_id])
end

function loadTimeTimeSeries(patient_id::Int, variation_id::Int, cohort_id::Int)
    return selectSimulations(; patient_id, variation_id, cohort_id) |> loadTimeTimeSeries
end

function loadCellCountTimeSeries(path_to_output_folder::String)
    files = grabOutputFiles(path_to_output_folder, "_cells.mat")
    return [extractCellCount(file) for file in files]
end

function loadCellCountTimeSeries(path_to_output_folders::Vector{String})
    return [loadCellCountTimeSeries(path_to_output_folder) for path_to_output_folder in path_to_output_folders]
end

function loadCellCountTimeSeries(simulation_id::Union{Int,Vector{Int}})
    return loadCellCountTimeSeries([data_dir*"/simulations/$d/output/" for d in simulation_id])
end

function loadCellCountTimeSeries(patient_id::Int, variation_id::Int, cohort_id::Int)
    return selectSimulations(; patient_id, variation_id, cohort_id) |> loadCellCountTimeSeries
end

function loadCellDataTimeSeries(path_to_output_folder::String, label::String)
    files = grabOutputFiles(path_to_output_folder, "_cells.mat")
    label_ind = getLabelIndex(path_to_output_folder * "initial.xml", label)
    return [extractCellData(file, label_ind) for file in files]
end

function loadCellDataTimeSeries(label::String)
    simulation_ids = DBInterface.execute(db, "SELECT simulation_id FROM simulations;") |> DataFrame |> x->x.simulation_id
    paths_to_output_folder = (data_dir * "/simulations/") .* (string.(simulation_ids) .* "/output/")
    all_cell_data = [loadCellDataTimeSeries(path_to_output_folder, label) for path_to_output_folder in paths_to_output_folder]
    return DataFrame("simulation_id" => simulation_ids, label => all_cell_data)
end

function loadCellDataTimeSeries(trial_id::Int, label::String)
    simulation_ids = selectTrialSimulations(trial_id)
    return DataFrame("simulation_id" => simulation_ids, label => [loadCellDataTimeSeries(data_dir * "/simulations/" * string(simulation_id) * "/output/", label) for simulation_id in simulation_ids])
end

function loadCellTypeCountTimeSeries(path_to_output_folder::String, cell_type_id::Union{Int,Vector{Int}})
    files = grabOutputFiles(path_to_output_folder, "_cells.mat")
    label_ind = getLabelIndex(path_to_output_folder * "initial.xml", "cell_type")
    return [extractCellTypeCount(file, cell_type_id, label_ind) for file in files] |> x -> cat(x...; dims=1)
end

function loadCellTypeCountTimeSeries(path_to_output_folders::Vector{String}, cell_type_id::Union{Int,Vector{Int}})
    return [loadCellTypeCountTimeSeries(path_to_output_folder, cell_type_id) for path_to_output_folder in path_to_output_folders]
end

function loadCellTypeCountTimeSeries(simulation_id::Union{Int,Vector{Int}}, cell_type_id::Union{Int,Vector{Int}})
    return loadCellTypeCountTimeSeries([data_dir*"/simulations/$d/output/" for d in simulation_id], cell_type_id)
end

function loadCellTypeCountTimeSeries(patient_id::Int, variation_id::Int, cohort_id::Int, cell_type_id::Union{Int,Vector{Int}})
    return selectSimulations(; patient_id, variation_id, cohort_id) |> x -> loadCellTypeCountTimeSeries(x, cell_type_id)
end

function loadSubstrateDensityTimeSeries(path_to_output_folder::String, substrate_id::Union{Int,Vector{Int}})
    files = grabOutputFiles(path_to_output_folder, "_microenvironment0.mat")
    return [extractSubstrateDensity(file, substrate_id) for file in files] |> x -> cat(x...; dims=3) |> x -> permutedims(x, (3, 2, 1))::Array{Float64,3} # (time,voxel,substrate)
end

function loadSubstrateDensityTimeSeries(path_to_output_folders::Vector{String}, substrate_id::Union{Int,Vector{Int}})
    return [loadSubstrateDensityTimeSeries(path_to_output_folder,substrate_id) for path_to_output_folder in path_to_output_folders]
end

function loadSubstrateDensityTimeSeries(path_to_output_folders::Union{String,Vector{String}}, substrate_names::Vector{String})
    path_to_xmls = path_to_output_folders .* "initial.xml"
    substrate_ids = [[getSubstrateID(path_to_xml, substrate_name) for substrate_name in substrate_names] for path_to_xml in path_to_xmls] # I no IT shud Bee paths_to_xml butt lettuce just ad esses & B kühl, yeah?
    return [loadSubstrateDensityTimeSeries(path_to_output_folder,substrate_id) for (path_to_output_folder,substrate_id) in zip(path_to_output_folders, substrate_ids)]
end

function loadSubstrateDensityTimeSeries(path_to_output_folders::Union{String,Vector{String}}, substrate_name::String)
    return loadSubstrateDensityTimeSeries(path_to_output_folders, [substrate_name])
end

end