module VCTModule
using SQLite, DataFrames, LightXML, LazyGrids
include("./VCTDatabase.jl")
include("./VCTConfiguration.jl")

home_dir = cd(pwd, homedir())

physicell_dir = "./src"
data_dir = "./data"

current_folder_id = 0
db, VCTModule.control_cohort_id = VCTDatabase.initializeDatabase()
control_cohort_id = 0
function initializeVCT(path_to_physicell, path_to_data)
    VCTModule.physicell_dir = path_to_physicell
    VCTModule.data_dir = path_to_data

    VCTModule.db, VCTModule.control_cohort_id = VCTDatabase.initializeDatabase(path_to_data * "/vct.db")
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

function runSimulation!(simulation::Simulation)
    cd(VCTModule.physicell_dir)
    path_to_new_output = VCTModule.data_dir*"/simulations/"*string(simulation.id)*"/"
    if isfile(path_to_new_output * "initial_mesh0.mat")
        ran = false
        return ran
    end
    if simulation.folder_id!=VCTModule.current_folder_id
        path_to_folder = VCTDatabase.selectRow("path","folders","WHERE folder_id=$(simulation.folder_id)")
        path_to_config = path_to_folder * "config/"
        run(`cp -r $(path_to_config) ./config`)
        
        path_to_custom_modules = path_to_folder * "custom_modules/"
        run(`cp -r $(path_to_custom_modules) ./custom_modules`)
        
        run(`make CC=/opt/homebrew/bin/g++-13`)
        
        VCTModule.current_folder_id = simulation.folder_id
    end
    run(`./project`)

    path_to_sim_output = VCTModule.physicell_dir * "/" * VCTConfiguration.getOutputFolder("./config/PhysiCell_settings.xml")

    run(`mkdir -p $(path_to_new_output)`)
    run(`mv $(path_to_sim_output) $(path_to_new_output)`)
    run(`mkdir $(path_to_sim_output)`)
    run(`touch $(path_to_sim_output)/empty.txt`)
    ran = true

    return ran
end

function deleteSimulation(simulation_id::Int)
    DBInterface.execute(db,"DELETE FROM simulations WHERE simulation_id=$(simulation_id);")
    run(`rm -rf $(data_dir)/simulations/$(simulation_id)`)
    return nothing
end

function deleteSimulation(simulation_ids::Vector{Int})
    DBInterface.execute(db,"DELETE FROM simulations WHERE simulation_id IN ($(join(simulation_ids,",")));")
    for simulation_id in simulation_ids
        run(`rm -rf $(data_dir)/simulations/$(simulation_id)`)
    end
    return nothing
end

function resetDatabase()
    simulation_ids = DBInterface.execute(db, "SELECT simulation_id FROM simulations;") |> DataFrame |> x->x.simulation_id
    if !isempty(simulation_ids)
        deleteSimulation(simulation_ids)
    end
    if db.file == ":memory:"
        VCTModule.db, VCTModule.control_cohort_id = VCTDatabase.initializeDatabase()
    else
        run(`rm -f $(data_dir)/vct.db`)
        VCTModule.db, VCTModule.control_cohort_id = VCTDatabase.initializeDatabase(VCTModule.data_dir * "/vct.db")
    end
    return nothing
end

function runReplicates(patient_id::Int, variation_id::Int, cohort_id::Int, folder_id::Int, num_replicates::Int)
    for i in 1:num_replicates
        s = Simulation(patient_id, variation_id, cohort_id, folder_id)
        runSimulation!(s)
    end
    return nothing
end

function runReplicates(patient_id::Int, variation_id::Int, cohort_id::Int, num_replicates::Int)
    folder_id = VCTDatabase.getFolderID(patient_id,cohort_id)
    runReplicates(patient_id, variation_id, cohort_id, folder_id, num_replicates)
end

function runVirtualClinicalTrial(patient_ids::Union{Int,Vector{Int}}, variation_ids::Vector{Vector{Int}}, cohort_ids::Union{Int,Vector{Int}}, num_replicates::Int)
    num_patients = length(patient_ids)
    @assert num_patients == length(variation_ids) # make sure each patient has their own variation ids assigned
    for i in 1:num_patients
        patient_id = patient_ids[i]
        variation_table_name = "patient_variations_$(patient_id)"
        for cohort_id in cohort_ids
            path_to_xml = VCTDatabase.selectRow("path","folders","WHERE patient_id=$(patient_id) AND cohort_id=$(cohort_id)") * "config/PhysiCell_settings.xml"
            for variation_id in variation_ids[i]
                variation_row = VCTDatabase.selectRow(variation_table_name,"WHERE variation_id=$(variation_id);")
                VCTConfiguration.loadVariation(path_to_xml,variation_row)
                runReplicates(patient_id, variation_id, cohort_id, num_replicates)
            end
        end
    end
    return nothing
end

function runVirtualClinicalTrial(patient_ids::Int, variation_ids::Vector{Int}, cohort_ids::Union{Int,Vector{Int}}, num_replicates::Int)
    return runVirtualClinicalTrial(patient_ids, [variation_ids], cohort_ids, num_replicates)
end

function runVirtualClinicalTrial(patient_id::Int, cohort_ids::Union{Int,Vector{Int}}, num_replicates::Int)
    variation_ids = DBInterface.execute(db, "SELECT variation_id FROM patient_variations_$(patient_id);") |> DataFrame |> x -> x.variation_id
    runVirtualClinicalTrial(patient_id, variation_ids, cohort_ids, num_replicates)
    return nothing
end

function runVirtualClinicalTrial(patient_ids::Vector{Int}, cohort_ids::Union{Int,Vector{Int}}, num_replicates::Int)
    variation_ids = [(DBInterface.execute(db, "SELECT variation_id FROM patient_variations_$(patient_id);") |> DataFrame |> x -> Vector(x.variation_id)) for patient_id in patient_ids]
    runVirtualClinicalTrial(patient_ids, variation_ids, cohort_ids, num_replicates)
    return nothing
end

function addPatient(patient_name::String,path_to_control_folder::String)
    if path_to_control_folder in (DBInterface.execute(db, "SELECT path FROM folders;") |> DataFrame |> x->x.path)
        println("This folder location is already present. No patient added.")
        return nothing
    end
    patient_id = DBInterface.execute(db, "INSERT INTO patients (patient_name) VALUES('$(patient_name)') RETURNING patient_id;") |> DataFrame |> x->x.patient_id[1]
    table_name = "patient_variations_$(patient_id)"
    DBInterface.execute(db, "CREATE TABLE $(table_name) (
        variation_id INTEGER PRIMARY KEY
        )
    ")
    DBInterface.execute(db, "INSERT INTO $(table_name) (variation_id) VALUES(0);")
    DBInterface.execute(db, "INSERT INTO folders (patient_id, cohort_id, path) VALUES($(patient_id),$(VCTModule.control_cohort_id),'$(path_to_control_folder)');")
    
    path_to_xml = path_to_control_folder * "config/PhysiCell_settings.xml"
    path_to_default_xml = path_to_control_folder * "config/PhysiCell_settings_default.xml"
    run(`cp $(path_to_xml) $(path_to_default_xml)`)
    return nothing
end

function addGVAX(patient_id::Int; cd4_multiplier::AbstractFloat=10., cd8_multiplier::AbstractFloat=2.)
    gvax_cohort_id = DBInterface.execute(db, "SELECT cohort_id FROM cohorts WHERE intervention='gvax';") |> DataFrame |> x->x.cohort_id
    if isempty(gvax_cohort_id)
        gvax_cohort_id = DBInterface.execute(db, "INSERT INTO cohorts (intervention) VALUES('gvax') RETURNING cohort_id;") |> DataFrame |> x->x.cohort_id[1]
    else
        gvax_cohort_id = gvax_cohort_id[1]
    end
    path_to_control_folder = DBInterface.execute(db, "SELECT path FROM folders WHERE patient_id=$(patient_id) AND cohort_id=$(VCTModule.control_cohort_id);") |> DataFrame |> x->x.path[1]
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

function addVariationColumns(patient_id::Int, xml_paths::Vector{Vector{String}})
    table_name = "patient_variations_$(patient_id)"
    column_names = DBInterface.execute(db, "PRAGMA table_info($(table_name));") |> DataFrame |> x->x[!,:name]
    filter!(x->x!="variation_id",column_names)
    varied_column_names = [join(xml_path,"/") for xml_path in xml_paths]

    is_new_column = [!(varied_column_name in column_names) for varied_column_name in varied_column_names]
    if any(is_new_column)
        new_column_names = varied_column_names[is_new_column]

        for new_column_name in new_column_names
            DBInterface.execute(db, "ALTER TABLE $(table_name) ADD COLUMN '$(new_column_name)' TEXT;")
        end
        path_to_xml = VCTDatabase.selectRow("path", "folders", "WHERE patient_id=$(patient_id) AND cohort_id=$(VCTModule.control_cohort_id)")
        path_to_xml *= "config/PhysiCell_settings.xml"
        VCTConfiguration.openXML(path_to_xml)
        default_values_for_new = [VCTConfiguration.getField(xml_path) for xml_path in xml_paths[is_new_column]]
        VCTConfiguration.closeXML()
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

function addVariationToTable(patient_id::Int, D::Vector{Vector{Vector}}; reference_variation::Int=0)
    xml_paths = [d[1] for d in D]
    new_values = [d[2] for d in D]
    table_name, static_column_names, varied_column_names = addVariationColumns(patient_id, xml_paths)
    static_values = VCTDatabase.selectRow(static_column_names, table_name, "WHERE variation_id=$(reference_variation)") |> x -> join("\"" .* x .* "\"", ",")
    table_features = join("\"" .* static_column_names .* "\"", ",")
    if !isempty(static_column_names)
        static_values *= ","
        table_features *= ","
    end
    table_features *= join("\"" .* varied_column_names .* "\"", ",")
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

function addVariationToTable(patient_id::Int, xml_paths::Vector{Vector{String}}, new_values::Vector{Vector{T}} where {T<:Real}; reference_variation::Int=0)
    D = [[xml_paths[i], new_values[i]] for i in eachindex(xml_paths)]
    return addVariationToTable(patient_id, D; reference_variation=reference_variation)
end

end