module VCTModule
using SQLite, DataFrames, LightXML, LazyGrids, Dates, CSV, Tables
include("./VCTDatabase.jl")
include("./VCTConfiguration.jl")

physicell_dir = ""
data_dir = ""

current_folder_id = Ref{Int}(0)
db = SQLite.DB()
control_cohort_id = 0

function __init()__
    global physicell_dir = "./src"
    global data_dir = "./data"
    global current_folder_id = 0
    global db, control_cohort_id = VCTDatabase.initializeDatabase()
end

function initializeVCT(path_to_physicell::String, path_to_data::String)
    global physicell_dir = path_to_physicell
    global data_dir = path_to_data
    global db, control_cohort_id = VCTDatabase.initializeDatabase(path_to_data * "/vct.db")
end

struct Simulation
    id::Int # string uniquely identifying this simulation
    patient_id::Int # integer identifying the patient that this simulation corresponds to
    variation_id::Int # integer identifying the variation (varied parameters) that this simulation corresponds to
    cohort_id::Int # integer identifying the cohort (treatment arm) this simulation belongs to
    folder_id::Int # integer identifying the folder that contains the custom and config folders
end

function Simulation(patient_id::Int, cohort_id::Int)
    folder_id = VCTDatabase.getFolderID(patient_id, cohort_id)
    variation_id = 0 # base variation (no variation)
    Simulation(patient_id, variation_id, cohort_id, folder_id)
end

function Simulation(patient_id::Int, variation_id::Int, cohort_id::Int, folder_id::Int)
    simulation_id = DBInterface.execute(db, "INSERT INTO simulations (patient_id,variation_id,cohort_id,folder_id) VALUES($(patient_id),$(variation_id),$(cohort_id),$(folder_id)) RETURNING simulation_id;") |> DataFrame |> x->x.simulation_id[1]
    Simulation(simulation_id, patient_id, variation_id, cohort_id, folder_id)
end

function Simulation(patient_id::Int, cohort_id::Int, folder_id::Int)
    variation_id = 0 # base variation (no variation)
    Simulation(simulation_id, patient_id, variation_id, cohort_id, folder_id)
end

function copyMakeFolderFiles(folder_id::Int)
    path_to_folder = VCTDatabase.selectRow("path","folders","WHERE folder_id=$(folder_id)")
    path_to_config = path_to_folder * "config/"
    run(`cp -r $(path_to_config) ./config`)
    
    path_to_custom_modules = path_to_folder * "custom_modules/"
    run(`cp -r $(path_to_custom_modules) ./custom_modules`)
    
    run(`make CC=/opt/homebrew/bin/g++-13`)
    
    global current_folder_id = folder_id
end

function copyMakeFolderFiles(simulation::Simulation)
    copyMakeFolderFiles(simulation.folder_id)
end

function runSimulation!(simulation::Simulation)
    cd(physicell_dir)
    path_to_new_output = data_dir * "/simulations/" * string(simulation.id) * "/"
    if isfile(path_to_new_output * "initial_mesh0.mat")
        ran = false
        return ran
    end
    if simulation.folder_id != current_folder_id
        copyMakeFolderFiles(simulation)
    end
    run(`./project`)

    path_to_sim_output = physicell_dir * "/" * VCTConfiguration.getOutputFolder("./config/PhysiCell_settings.xml")

    run(`mkdir -p $(path_to_new_output)`)
    run(`mv $(path_to_sim_output) $(path_to_new_output)`)
    run(`mkdir $(path_to_sim_output)`)
    run(`touch $(path_to_sim_output)/empty.txt`)
    ran = true

    return ran
end

function deleteSimulation(simulation_id::Int)
    return deleteSimulation([simulation_id])
end

function deleteSimulation(simulation_ids::Vector{Int})
    DBInterface.execute(db,"DELETE FROM simulations WHERE simulation_id IN ($(join(simulation_ids,",")));")
    for simulation_id in simulation_ids
        run(`rm -rf $(data_dir)/simulations/$(simulation_id)`)
    end
    return nothing
end

function trialRowToIds(r::String)
    if !contains(r,":")
        return parse(Int,r)
    end
    # otherwise has a colon and need to expand
    s = split(r,":") .|> String .|> x->parse(Int,x)
    return collect(s[1]:s[2])
end

function deleteTrial(trial_ids::Vector{Int})
    DBInterface.execute(db,"DELETE FROM trials WHERE trial_id IN ($(join(trial_ids,",")));")
    for trial_id in trial_ids
        rows = CSV.read("$(data_dir)/trials/$(trial_id)/simulations.csv",DataFrame,header=false,delim=",",types=String) |>
            x->x.Column1 .|> trialRowToIds
        for row in rows
            deleteSimulation(row)
        end
        run(`rm -rf $(data_dir)/trials/$(trial_id)`)
    end
    return nothing
end

function resetDatabase()
    trial_ids = DBInterface.execute(db, "SELECT trial_id FROM trials;") |> DataFrame |> x->x.trial_id
    if !isempty(trial_ids)
        deleteTrial(trial_ids)
    end

    simulation_ids = DBInterface.execute(db, "SELECT simulation_id FROM simulations;") |> DataFrame |> x->x.simulation_id
    if !isempty(simulation_ids)
        deleteSimulation(simulation_ids)
    end
    if db.file == ":memory:"
        global db, control_cohort_id = VCTDatabase.initializeDatabase()
    else
        run(`rm -f $(data_dir)/vct.db`)
        global db, control_cohort_id = VCTDatabase.initializeDatabase(data_dir * "/vct.db")
    end
    return nothing
end

function runReplicates(patient_id::Int, variation_id::Int, cohort_id::Int, folder_id::Int, num_replicates::Int; use_previous_sims::Bool = false)
    if use_previous_sims
        simulation_ids = DBInterface.execute(db, "SELECT simulation_id FROM simulations WHERE (patient_id,variation_id,cohort_id,folder_id)=($(patient_id),$(variation_id),$(cohort_id),$(folder_id));") |> DataFrame |> x->x.simulation_id
        num_replicates -= length(simulation_ids)
    else
        simulation_ids = Int[]
    end
    for i in 1:num_replicates
        s = Simulation(patient_id, variation_id, cohort_id, folder_id)
        runSimulation!(s)
        push!(simulation_ids,s.id)
    end
    return simulation_ids
end

function runReplicates(patient_id::Int, variation_id::Int, cohort_id::Int, num_replicates::Int; use_previous_sims::Bool = false)
    folder_id = VCTDatabase.getFolderID(patient_id,cohort_id)
    return runReplicates(patient_id, variation_id, cohort_id, folder_id, num_replicates; use_previous_sims = use_previous_sims)
end

function runVirtualClinicalTrial(patient_ids::Union{Int,Vector{Int}}, variation_ids::Vector{Vector{Int}}, cohort_ids::Union{Int,Vector{Int}}, num_replicates::Int; use_previous_sims::Bool = false, description::String = String[])
    time_started  = now()
    num_patients = length(patient_ids)
    @assert num_patients == length(variation_ids) # make sure each patient has their own variation ids assigned
    simulation_ids = Int[]
    for i in 1:num_patients
        patient_id = patient_ids[i]
        variation_table_name = "patient_variations_$(patient_id)"
        for cohort_id in cohort_ids
            df = DBInterface.execute(db, "SELECT folder_id,path FROM folders WHERE patient_id=$(patient_id) AND cohort_id=$(cohort_id)") |> DataFrame
            path_to_xml = df.path[1]
            copyMakeFolderFiles(df.folder_id[1])
            path_to_xml = VCTDatabase.selectRow("path","folders","WHERE patient_id=$(patient_id) AND cohort_id=$(cohort_id)") * "config/PhysiCell_settings.xml"
            for variation_id in variation_ids[i]
                variation_row = VCTDatabase.selectRow(variation_table_name,"WHERE variation_id=$(variation_id);")
                VCTConfiguration.loadVariation(path_to_xml, variation_row, physicell_dir)
                append!(simulation_ids, runReplicates(patient_id, variation_id, cohort_id, num_replicates; use_previous_sims=use_previous_sims))
            end
        end
    end
    recordTrialInfo(simulation_ids, time_started, description)
    return nothing
end

function runVirtualClinicalTrial(patient_ids::Int, variation_ids::Vector{Int}, cohort_ids::Union{Int,Vector{Int}}, num_replicates::Int; use_previous_sims::Bool=false, description::String=String[])
    return runVirtualClinicalTrial(patient_ids, [variation_ids], cohort_ids, num_replicates; use_previous_sims=use_previous_sims, description=description)
end

function runVirtualClinicalTrial(patient_ids::Union{Int,Vector{Int}}, cohort_ids::Union{Int,Vector{Int}}, num_replicates::Int; use_previous_sims::Bool=false, description::String=String[])
    variation_ids = [(DBInterface.execute(db, "SELECT variation_id FROM patient_variations_$(patient_id);") |> DataFrame |> x -> Vector(x.variation_id)) for patient_id in patient_ids]
    return runVirtualClinicalTrial(patient_ids, variation_ids, cohort_ids, num_replicates; use_previous_sims=use_previous_sims, description=description)
end

function addPatient(patient_name::String,path_to_control_folder::String)
    df = DBInterface.execute(db, "SELECT patient_id FROM folders WHERE path='$(path_to_control_folder)';") |> DataFrame
    if !isempty(df)
        println("This folder location is already present. No patient added.")
        return df.patient_id[1]
    end
    patient_id = DBInterface.execute(db, "INSERT INTO patients (patient_name) VALUES('$(patient_name)') RETURNING patient_id;") |> DataFrame |> x->x.patient_id[1]
    table_name = "patient_variations_$(patient_id)"
    DBInterface.execute(db, "CREATE TABLE $(table_name) (
        variation_id INTEGER PRIMARY KEY
        )
    ")
    DBInterface.execute(db, "INSERT INTO $(table_name) (variation_id) VALUES(0);")
    DBInterface.execute(db, "INSERT INTO folders (patient_id, cohort_id, path) VALUES($(patient_id),$(control_cohort_id),'$(path_to_control_folder)');")
    
    path_to_xml = path_to_control_folder * "config/PhysiCell_settings.xml"
    path_to_default_xml = path_to_control_folder * "config/PhysiCell_settings_default.xml"
    run(`cp $(path_to_xml) $(path_to_default_xml)`)
    return patient_id
end

function addGVAX(patient_id::Int; cd4_multiplier::AbstractFloat=10., cd8_multiplier::AbstractFloat=2.)
    gvax_cohort_id = DBInterface.execute(db, "SELECT cohort_id FROM cohorts WHERE intervention='gvax';") |> DataFrame |> x->x.cohort_id
    if isempty(gvax_cohort_id)
        gvax_cohort_id = DBInterface.execute(db, "INSERT INTO cohorts (intervention) VALUES('gvax') RETURNING cohort_id;") |> DataFrame |> x->x.cohort_id[1]
    else
        gvax_cohort_id = gvax_cohort_id[1]
    end
    path_to_control_folder = DBInterface.execute(db, "SELECT path FROM folders WHERE patient_id=$(patient_id) AND cohort_id=$(control_cohort_id);") |> DataFrame |> x->x.path[1]
    path_to_folder = path_to_control_folder[1:end-1] * "_with_gvax/"
    folder_id = DBInterface.execute(db, "INSERT OR IGNORE INTO folders (patient_id,cohort_id,path) 
        VALUES
            ($(patient_id),$(gvax_cohort_id),'$(path_to_folder)')
        RETURNING folder_id;
    ")
    if isempty(folder_id)
        println("A GVAX folder for this patient has already been created.")
        return gvax_cohort_id
    end
    run(`cp -r $(path_to_control_folder) $(path_to_folder)`)
    path_to_xml = path_to_folder * "config/PhysiCell_settings.xml"
    VCTConfiguration.openXML(path_to_xml)
    VCTConfiguration.multiplyField(["user_parameters","number_of_PD-1hi_CD4_Tcell"],cd4_multiplier)
    VCTConfiguration.multiplyField(["user_parameters","number_of_PD-1lo_CD4_Tcell"],cd4_multiplier)
    VCTConfiguration.multiplyField(["user_parameters","number_of_PD-1hi_CD137hi_CD8_Tcell"],cd8_multiplier)
    VCTConfiguration.multiplyField(["user_parameters","number_of_PD-1lo_CD137hi_CD8_Tcell"],cd8_multiplier)
    VCTConfiguration.multiplyField(["user_parameters","number_of_PD-1hi_CD137lo_CD8_Tcell"],cd8_multiplier)
    VCTConfiguration.multiplyField(["user_parameters","number_of_PD-1lo_CD137lo_CD8_Tcell"],cd8_multiplier)
    save_file(VCTConfiguration.xml_doc, path_to_xml)
    VCTConfiguration.closeXML()
    return gvax_cohort_id
end

function addVariationColumns(patient_id::Int, xml_paths::Vector{Vector{String}}, variable_types::Vector{DataType})
    table_name = "patient_variations_$(patient_id)"
    column_names = DBInterface.execute(db, "PRAGMA table_info($(table_name));") |> DataFrame |> x->x[!,:name]
    filter!(x->x!="variation_id",column_names)
    varied_column_names = [join(xml_path,"/") for xml_path in xml_paths]

    is_new_column = [!(varied_column_name in column_names) for varied_column_name in varied_column_names]
    if any(is_new_column)
        new_column_names = varied_column_names[is_new_column]

        path_to_xml = VCTDatabase.selectRow("path", "folders", "WHERE patient_id=$(patient_id) AND cohort_id=$(control_cohort_id)")
        path_to_xml *= "config/PhysiCell_settings.xml"
        VCTConfiguration.openXML(path_to_xml)
        default_values_for_new = [VCTConfiguration.getField(xml_path) for xml_path in xml_paths[is_new_column]]
        VCTConfiguration.closeXML()
        for (i, new_column_name) in enumerate(new_column_names)
            if variable_types[i] == Bool
                sqlite_data_type = "TEXT"
            elseif variable_types[i] <: Int
                sqlite_data_type = "INT"
            elseif variable_types[i] <: Real
                sqlite_data_type = "REAL"
            else
                sqlite_data_type = "TEXT"
            end
            DBInterface.execute(db, "ALTER TABLE $(table_name) ADD COLUMN '$(new_column_name)' $(sqlite_data_type);")
        end
        DBInterface.execute(db, "UPDATE $(table_name) SET ($(join("\"".*new_column_names.*"\"",",")))=($(join("\"".*default_values_for_new.*"\"",",")));")

        index_name = table_name * "_index"
        SQLite.dropindex!(db, index_name; ifexists=true) # remove previous index
        index_columns = deepcopy(column_names)
        append!(index_columns, new_column_names)
        SQLite.createindex!(db, table_name, index_name, index_columns; unique=true, ifnotexists=false) # add new index to make sure no variations are repeated
    end

    static_column_names = deepcopy(column_names)
    old_varied_names = varied_column_names[.!is_new_column]
    filter!( x->!(x in old_varied_names) , static_column_names)

    return table_name, static_column_names, varied_column_names
end

function addVariationRow(table_name::String, table_features::String, values::String)
    new_variation_id = DBInterface.execute(db, "INSERT OR IGNORE INTO $(table_name) ($(table_features)) VALUES($(values)) RETURNING variation_id;") |> DataFrame |> x->x.variation_id
    new_variation_added = length(new_variation_id)==1
    if  !new_variation_added
        new_variation_id = VCTDatabase.selectRow("variation_id", table_name, "WHERE ($(table_features))=($(values))")
    end
    return new_variation_id[1], new_variation_added
end

function addVariationRow(table_name::String, table_features::String, static_values::String, varied_values::String)
    return addVariationRow(table_name, table_features, "$(static_values)$(varied_values)")
end

"""
function addGridVariationToTable(patient_id::Int, D::Vector{Vector{Vector}}; reference_variation::Int=0)
Creates a grid of parameter values defined by D to the variations tables for a specified patient.
A reference variation id can be suppplied so that any currently unvaried values are pulled from that variation.
D is a vector of parameter info.
Each entry in D has two elements: D[i][1] is the xml_path based on the config file; D[i][2] is the vector of values to use for the ith parameter.
"""

function addGridVariationToTable(patient_id::Int, D::Vector{Vector{Vector}}; reference_variation::Int=0)
    xml_paths = [d[1] for d in D]
    new_values = [d[2] for d in D]
    table_name, static_column_names, varied_column_names = addVariationColumns(patient_id, xml_paths, [typeof(d[2][1]) for d in D])
    static_values, table_features = prepareAddNewVariations(table_name, static_column_names, varied_column_names; reference_variation = reference_variation)

    NDG = ndgrid(new_values...)
    sz_variations = size(NDG[1])
    variation_ids = zeros(Int, sz_variations)
    is_new_variation_id = falses(sz_variations)
    for i in eachindex(NDG[1])
        varied_values = [A[i] for A in NDG] .|> string |> x -> join("\"" .* x .* "\"", ",")
        variation_ids[i], is_new_variation_id[i] = addVariationRow(table_name, table_features, static_values, varied_values)
    end
    return variation_ids, is_new_variation_id
end

"""
function addGridVariationToTable(patient_id::Int, xml_paths::Vector{Vector{String}}, new_values::Vector{Vector{T}} where {T<:Real}; reference_variation::Int=0)
Does the same as addGridVariationToTable(patient_id::Int, D::Vector{Vector{Vector}}; reference_variation::Int=0) but first assembles D from xml_paths and new_values.
"""

function addGridVariationToTable(patient_id::Int, xml_paths::Vector{Vector{String}}, new_values::Vector{Vector{T}} where {T<:Real}; reference_variation::Int=0)
    D = [[xml_paths[i], new_values[i]] for i in eachindex(xml_paths)]
    return addGridVariationToTable(patient_id, D; reference_variation=reference_variation)
end

function addSampleVariationToTable(patient_id::Int, xml_paths::Vector{Vector{String}}, parameter_matrix::Matrix{T} where T; reference_variation=0)
    table_name, static_column_names, varied_column_names = addVariationColumns(patient_id, xml_paths, [typeof(parameter_matrix[1,i]) for i in axes(parameter_matrix,2)])
    static_values, table_features = prepareAddNewVariations(table_name, static_column_names, varied_column_names; reference_variation = reference_variation)
    
    sz_variations = size(parameter_matrix,1)
    variation_ids = zeros(Int, sz_variations)
    is_new_variation_id = falses(sz_variations)
    for i in axes(parameter_matrix,1)
        varied_values = [parameter_matrix[i,j] for j in axes(parameter_matrix,2)] .|> string |> x -> join("\"" .* x .* "\"", ",")
        variation_ids[i], is_new_variation_id[i] = addVariationRow(table_name, table_features, static_values, varied_values)
    end
    return variation_ids, is_new_variation_id
end

function prepareAddNewVariations(table_name::String, static_column_names::Vector{String}, varied_column_names::Vector{String}; reference_variation::Int=0)
    static_values = VCTDatabase.selectRow(static_column_names, table_name, "WHERE variation_id=$(reference_variation)") |> x -> join("\"" .* string.(x) .* "\"", ",")
    table_features = join("\"" .* static_column_names .* "\"", ",")
    if !isempty(static_column_names)
        static_values *= ","
        table_features *= ","
    end
    table_features *= join("\"" .* varied_column_names .* "\"", ",")
    return static_values, table_features
end

function recordTrialInfo(simulation_ids::Vector{Int}, time_started::DateTime, description::String)
    if isempty(description)
        println("No description submitted for this trial. Do you think you can remember everything? No. Enter a description now:")
        description = readline()
    end
    s =  "INSERT INTO trials (datetime,description) VALUES('$(Dates.format(time_started,"yymmddHHMM"))','$(description)') RETURNING trial_id;"
    trial_id = DBInterface.execute(db, s) |> DataFrame |> x -> x.trial_id[1]
    path_to_trial_folder = data_dir * "/trials/" * string(trial_id) * "/"
    run(`mkdir -p $(path_to_trial_folder)`)
    path_to_csv = path_to_trial_folder * "simulations.csv"
    lines_table = compressSimulationIDs(simulation_ids)
    CSV.write(path_to_csv, lines_table; writeheader=false)
end

function compressSimulationIDs(simulation_ids::Vector{Int})
    sort!(simulation_ids)
    lines = String[]
    while !isempty(simulation_ids)
        if length(simulation_ids) == 1
            next_line = string(simulation_ids[1])
            popfirst!(simulation_ids)
        else
            I = findfirst(diff(simulation_ids) .> 1)
            I = isnothing(I) ? length(simulation_ids) : I # if none found, then all the diffs are 1 so we want to take the entire list
            if I > 1
                next_line = "$(simulation_ids[1]):$(simulation_ids[I])"
                simulation_ids = simulation_ids[I+1:end]
            else
                next_line = string(simulation_ids[1])
                popfirst!(simulation_ids)
            end
        end
        push!(lines, next_line)
    end
    return Tables.table(lines)
end

end