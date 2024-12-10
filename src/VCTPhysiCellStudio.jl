using CSV, DataFrames

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
    path_to_xml = joinpath(path_to_output, "PhysiCell_settings.xml")
    xml_doc = openXML(path_to_xml)
    updateField(xml_doc, ["save", "folder"], path_to_output)
    updateField(xml_doc, ["cell_rules", "rulesets", "ruleset", "folder"], path_to_output)
    updateField(xml_doc, ["cell_rules", "rulesets", "ruleset", "filename"], "cell_rules_temp.csv")

    rules_header = ["cell_type", "signal", "response", "behavior", "base_response", "max_response", "half_max", "hill_power", "applies_to_dead"]
    rules_df = CSV.read(joinpath(path_to_output, "cell_rules.csv"), DataFrame; header=rules_header)
    select!(rules_df, Not(:base_response))
    path_to_temp_rules = joinpath(path_to_output, "cell_rules_temp.csv")
    CSV.write(path_to_temp_rules, rules_df, writeheader=false)

    path_to_temp_xml = joinpath(path_to_output, "PhysiCell_settings_temp.xml")
    save_file(xml_doc, path_to_temp_xml)
    closeXML(xml_doc)

    cmd = `$path_to_python $(joinpath(path_to_studio, "bin", "studio.py")) -c $(path_to_temp_xml)`
    cd(() -> run(pipeline(cmd; stdout=devnull, stderr=devnull)), physicell_dir) # compile the custom code in the PhysiCell directory and return to the original directory; make sure the macro ADDON_PHYSIECM is defined (should work even if multiply defined, e.g., by Makefile)
    rm(path_to_temp_xml, force=true)
    rm(path_to_temp_rules, force=true)
end