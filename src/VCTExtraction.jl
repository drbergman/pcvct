using MAT

# function loadVCT(path_to_data)
#     global db, _ = initializeDatabase(path_to_data * "/vct.db")
# end

############# Helper functions #############

function getOutputFiles(path_to_output_folder::String, filename_suffix::String)
    return path_to_output_folder .* ["initial" * filename_suffix
        readdir(path_to_output_folder) |> x -> filter!(endswith(filename_suffix), x) |> x -> filter!(startswith("output"), x)
        "final" * filename_suffix]
end

function getLabelIndex(path_to_xml::String, labels::Vector{String})
    xml_path = ["cellular_information", "cell_populations", "cell_population", "custom", "simplified_data", "labels"]
    xml_doc = openXML(path_to_xml)
    labels_element = retrieveElement(xml_doc, xml_path; required=true)
    index = UnitRange{Int64}[]
    for label in labels # obviously, would be more efficient to flip these loops to only read the indices in the file once
        for label_element in child_elements(labels_element)
            if content(label_element) == label
                label_ind_start = attribute(label_element, "index"; required=true) |> x -> parse(Int, x)
                label_ind_width = attribute(label_element, "size"; required=true) |> x -> parse(Int, x)
                push!(index, label_ind_start .+ (1:label_ind_width))
                break
            end
        end
    end
    closeXML(xml_doc)
    return index
end

function getLabelIndex(path_to_xml::String, label::String)
    return getLabelIndex(path_to_xml, [label])[1]
end

# function getSubstrateID(path_to_xml::String, name::String)
#     xml_path = ["microenvironment","domain","variables"]
#     xml_doc = openXML(path_to_xml)
#     variables_element = retrieveElement(xml_doc, xml_path; required=true)
#     for variable_element in child_elements(variables_element)
#         if attribute(variable_element, "name"; required=true)==name
#             substrate_id = attribute(variable_element, "ID"; required=true) |> x->parse(Int,x)
#             closeXML(xml_doc)
#             return substrate_id
#         end
#     end
#     closeXML(xml_doc)
# end

# function selectSimulations(; patient_id::Int, variation_id::Int, cohort_id::Int)
#     return DBInterface.execute(db, "SELECT simulation_id FROM simulations WHERE (patient_id, variation_id, cohort_id)=($(patient_id),$(variation_id),$(cohort_id));") |> DataFrame |> x -> x.simulation_id
# end

# ############# Atomic extraction functions #############

function extractTime(path_to_output_file::String)
    xml_path = ["metadata", "current_time"]
    xml_doc = openXML(path_to_output_file)
    t = getField(xml_doc, xml_path) |> x -> parse(Float64, x)
    closeXML(xml_doc)
    return t
end

# function extractCellCount(path_to_output_file::String)
#     return matread(path_to_output_file)["cell"] |> x -> size(x, 2)
# end

function extractCellData(path_to_output_file::String, label_inds::Vector{UnitRange{Int}})
    M = matread(path_to_output_file)["cell"]
    return [M[label_ind, :] for label_ind in label_inds]
end

function extractCellData(path_to_output_file::String, label_ind::UnitRange{Int})
    return extractCellData(path_to_output_file, [label_ind])[1]
end

# function extractCellTypeCount(path_to_output_file::String, cell_type_id::Vector{Int}, label_ind::UnitRange{Int})
#     return extractCellData(path_to_output_file, label_ind) |> vec |> (x -> x .== (cell_type_id')) |> x -> sum(x; dims=1)
# end

# function extractCellTypeCount(path_to_output_file::String, cell_type_id::Int, label_ind::UnitRange{Int})
#     return extractCellTypeCount(path_to_output_file, [cell_type_id], label_ind)[1]
# end

# function extractSubstrateDensity(path_to_output_file::String, substrate_id::Vector{Int})
#     return matread(path_to_output_file)["multiscale_microenvironmen"][5 .+ substrate_id, :]::Matrix{Float64} # (substrates,voxels)
# end

# function extractSubstrateDensity(path_to_output_file::String, substrate_id::Int)
#     return extractSubstrateDensity(path_to_output_file, [substrate_id])
# end

# ############# Whole simulation loading functions #############

# function loadTimeTimeSeries(path_to_output_folder::String)
#     files = getOutputFiles(path_to_output_folder, ".xml")
#     return [extractTime(file) for file in files]
# end

# function loadTimeTimeSeries(path_to_output_folders::Vector{String})
#     return [loadTimeTimeSeries(path_to_output_folder) for path_to_output_folder in path_to_output_folders]
# end

# function loadTimeTimeSeries(simulation_id::Union{Int,Vector{Int}})
#     return loadTimeTimeSeries([data_dir*"/outputs/simulations/$d/output/" for d in simulation_id])
# end

# function loadTimeTimeSeries(patient_id::Int, variation_id::Int, cohort_id::Int)
#     return selectSimulations(; patient_id, variation_id, cohort_id) |> loadTimeTimeSeries
# end

# function loadCellCountTimeSeries(path_to_output_folder::String)
#     files = getOutputFiles(path_to_output_folder, "_cells.mat")
#     return [extractCellCount(file) for file in files]
# end

# function loadCellCountTimeSeries(path_to_output_folders::Vector{String})
#     return [loadCellCountTimeSeries(path_to_output_folder) for path_to_output_folder in path_to_output_folders]
# end

# function loadCellCountTimeSeries(simulation_id::Union{Int,Vector{Int}})
#     return loadCellCountTimeSeries([data_dir*"/outputs/simulations/$d/output/" for d in simulation_id])
# end

# function loadCellCountTimeSeries(patient_id::Int, variation_id::Int, cohort_id::Int)
#     return selectSimulations(; patient_id, variation_id, cohort_id) |> loadCellCountTimeSeries
# end

function loadCellDataTimeSeries(path_to_output_folder::String, label::String)
    # load each file output as df
    # for each file in sim, add a named tuple (t = time, data = df)
    xml_files = getOutputFiles(path_to_output_folder, ".xml")
    cell_files = getOutputFiles(path_to_output_folder, "_cells.mat")
    id_ind, label_ind = getLabelIndex(path_to_output_folder * "initial.xml", ["ID"; label])
    if label=="position"
        label_col_names = ["x", "y", "z"]
    else
        label_col_names = length(label_ind) == 1 ? [label] : [label * "_$i" for i in 1:length(label_ind)]
    end
    col_names = ["ID", label_col_names...]
    f(cell_file) = begin
        data = extractCellData(cell_file, [id_ind, label_ind]) # list of arrays, one for id and one for label
        data = vcat(data...) # concatenate into single array (so that any labels with multiple columns are in the same array)
        data = [name => col for (name, col) in zip(col_names, eachrow(data))] |> DataFrame # convert to named dataframe
    end
    return [(t = extractTime(xml_file), data = f(cell_file)) for (xml_file, cell_file) in zip(xml_files, cell_files)]
end

# function loadCellDataTimeSeries(label::String)
#     simulation_ids = DBInterface.execute(db, "SELECT simulation_id FROM simulations;") |> DataFrame |> x->x.simulation_id
#     paths_to_output_folder = (data_dir * "/outputs/simulations/") .* (string.(simulation_ids) .* "/output/")
#     all_cell_data = [loadCellDataTimeSeries(path_to_output_folder, label) for path_to_output_folder in paths_to_output_folder]
#     return DataFrame("simulation_id" => simulation_ids, label => all_cell_data)
# end

function loadCellDataTimeSeries(trial_id::Int, label::String)
    # for each sim, have a named tuple (id = sim_id, data = [tuples] from above)
    simulation_ids = getSimulationIDs((Trial,trial_id))
    return [(simulation_id = simulation_id, data = loadCellDataTimeSeries(data_dir * "/outputs/simulations/" * string(simulation_id) * "/output/", label)) for simulation_id in simulation_ids]
end

# function loadCellTypeCountTimeSeries(path_to_output_folder::String, cell_type_id::Union{Int,Vector{Int}})
#     files = getOutputFiles(path_to_output_folder, "_cells.mat")
#     label_ind = getLabelIndex(path_to_output_folder * "initial.xml", "cell_type")
#     return [extractCellTypeCount(file, cell_type_id, label_ind) for file in files] |> x -> cat(x...; dims=1)
# end

# function loadCellTypeCountTimeSeries(path_to_output_folders::Vector{String}, cell_type_id::Union{Int,Vector{Int}})
#     return [loadCellTypeCountTimeSeries(path_to_output_folder, cell_type_id) for path_to_output_folder in path_to_output_folders]
# end

# function loadCellTypeCountTimeSeries(simulation_id::Union{Int,Vector{Int}}, cell_type_id::Union{Int,Vector{Int}})
#     return loadCellTypeCountTimeSeries([data_dir*"/outputs/simulations/$d/output/" for d in simulation_id], cell_type_id)
# end

# function loadCellTypeCountTimeSeries(patient_id::Int, variation_id::Int, cohort_id::Int, cell_type_id::Union{Int,Vector{Int}})
#     return selectSimulations(; patient_id, variation_id, cohort_id) |> x -> loadCellTypeCountTimeSeries(x, cell_type_id)
# end

# function loadSubstrateDensityTimeSeries(path_to_output_folder::String, substrate_id::Union{Int,Vector{Int}})
#     files = getOutputFiles(path_to_output_folder, "_microenvironment0.mat")
#     return [extractSubstrateDensity(file, substrate_id) for file in files] |> x -> cat(x...; dims=3) |> x -> permutedims(x, (3, 2, 1))::Array{Float64,3} # (time,voxel,substrate)
# end

# function loadSubstrateDensityTimeSeries(path_to_output_folders::Vector{String}, substrate_id::Union{Int,Vector{Int}})
#     return [loadSubstrateDensityTimeSeries(path_to_output_folder,substrate_id) for path_to_output_folder in path_to_output_folders]
# end

# function loadSubstrateDensityTimeSeries(path_to_output_folders::Union{String,Vector{String}}, substrate_names::Vector{String})
#     path_to_xmls = path_to_output_folders .* "initial.xml"
#     substrate_ids = [[getSubstrateID(path_to_xml, substrate_name) for substrate_name in substrate_names] for path_to_xml in path_to_xmls] # I no IT shud Bee paths_to_xml butt lettuce just ad esses & B kühl, yeah?
#     return [loadSubstrateDensityTimeSeries(path_to_output_folder,substrate_id) for (path_to_output_folder,substrate_id) in zip(path_to_output_folders, substrate_ids)]
# end

# function loadSubstrateDensityTimeSeries(path_to_output_folders::Union{String,Vector{String}}, substrate_name::String)
#     return loadSubstrateDensityTimeSeries(path_to_output_folders, [substrate_name])
# end