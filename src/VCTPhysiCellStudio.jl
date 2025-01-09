using CSV, DataFrames

export runStudio

path_to_python = haskey(ENV, "PCVCT_PYTHON_PATH") ? ENV["PCVCT_PYTHON_PATH"] : missing 
path_to_studio = haskey(ENV, "PCVCT_STUDIO_PATH") ? ENV["PCVCT_STUDIO_PATH"] : missing

function runStudio(simulation_id::Int; python_path::Union{Missing,String}=path_to_python, studio_path::Union{Missing,String}=path_to_studio)
    if ismissing(python_path)
        println("Path to python not set. Please set the PCVCT_PYTHON_PATH environment variable or pass the path as an argument.")
        return
    end
    if ismissing(studio_path)
        println("Path to studio not set. Please set the PCVCT_STUDIO_PATH environment variable or pass the path as an argument.")
        return
    end
    if ismissing(path_to_python)
        global path_to_python = python_path
        println("Setting path to python to $path_to_python")
    end
    if ismissing(path_to_studio)
        global path_to_studio = studio_path
        println("Setting path to studio to $path_to_studio")
    end

    path_to_output = joinpath(outputFolder("simulation", simulation_id), "output")
    
    physicell_version = physicellVersion(Simulation(simulation_id))
    upstream_version = split(physicell_version, "-")[1] |> VersionNumber
    rules_header = ["cell_type", "signal", "response", "behavior", "base_response", "max_response", "half_max", "hill_power", "applies_to_dead"]
    if upstream_version < v"1.14.0"
        output_rules_file = "cell_rules.csv"
    else # starting in 1.14.1, export the v3 rules to cell_rules_parsed.csv
        output_rules_file = "cell_rules_parsed.csv"
        filter!(h -> h != "base_response", rules_header)
    end
    
    rules_df = CSV.read(joinpath(path_to_output, output_rules_file), DataFrame; header=rules_header)
    if "base_response" in rules_header
        select!(rules_df, Not(:base_response))
    end
    
    input_rules_file = "cell_rules_temp.csv"
    path_to_input_rules = joinpath(path_to_output, input_rules_file)
    CSV.write(path_to_input_rules, rules_df, writeheader=false)
    
    path_to_xml = joinpath(path_to_output, "PhysiCell_settings.xml")
    xml_doc = openXML(path_to_xml)
    updateField(xml_doc, ["save", "folder"], path_to_output)
    updateField(xml_doc, ["cell_rules", "rulesets", "ruleset", "folder"], path_to_output)
    updateField(xml_doc, ["cell_rules", "rulesets", "ruleset", "filename"], input_rules_file)

    path_to_temp_xml = joinpath(path_to_output, "PhysiCell_settings_temp.xml")
    save_file(xml_doc, path_to_temp_xml)
    closeXML(xml_doc)

    cmd = `$python_path $(joinpath(studio_path, "bin", "studio.py")) -c $(path_to_temp_xml)`
    cd(() -> run(pipeline(cmd; stdout=devnull, stderr=devnull)), physicell_dir) # compile the custom code in the PhysiCell directory and return to the original directory; make sure the macro ADDON_PHYSIECM is defined (should work even if multiply defined, e.g., by Makefile)
    rm(path_to_temp_xml, force=true)
    rm(path_to_input_rules, force=true)
end