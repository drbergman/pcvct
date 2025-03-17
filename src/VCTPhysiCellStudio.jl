using CSV, DataFrames

export runStudio

path_to_python = haskey(ENV, "PCVCT_PYTHON_PATH") ? ENV["PCVCT_PYTHON_PATH"] : missing 
path_to_studio = haskey(ENV, "PCVCT_STUDIO_PATH") ? ENV["PCVCT_STUDIO_PATH"] : missing

"""
    runStudio(simulation_id::Int; python_path::Union{Missing,String}=path_to_python, studio_path::Union{Missing,String}=path_to_studio)

Launch PhysiCell Studio for a given simulation.

Creates temporary config and rules files to avoid overwriting the original files in the output folder.
The intent of this function is to allow users to visualize the results of a simulation with Studio, rather than to modify the simulation itself.

The path to the python executable and the Studio folder must be set.
pcvct will look for these in the environment variables `PCVCT_PYTHON_PATH` and `PCVCT_STUDIO_PATH`, respectively.
"""
function runStudio(simulation_id::Int; python_path::Union{Missing,String}=path_to_python, studio_path::Union{Missing,String}=path_to_studio)
    resolveStudioGlobals(python_path, studio_path)
    path_to_temp_xml, path_to_input_rules = setUpStudioInputs(simulation_id)
    out = executeStudio(path_to_python, path_to_studio, path_to_temp_xml, path_to_input_rules)
    cleanUpStudioInputs(path_to_temp_xml, path_to_input_rules)
    if out isa Exception
        throw(out)
    end
end

function resolveStudioGlobals(python_path::Union{Missing,String}, studio_path::Union{Missing,String})
    if ismissing(python_path)
        throw(ArgumentError("Path to python not set. Please set the PCVCT_PYTHON_PATH environment variable or pass the path as an argument."))
    end
    if ismissing(studio_path)
        throw(ArgumentError("Path to studio not set. Please set the PCVCT_STUDIO_PATH environment variable or pass the path as an argument."))
    end
    if ismissing(path_to_python)
        global path_to_python = python_path
        println("Setting path to python to $path_to_python")
    end
    if ismissing(path_to_studio)
        global path_to_studio = studio_path
        println("Setting path to studio to $path_to_studio")
    end
end

function setUpStudioInputs(simulation_id::Int)
    path_to_output = joinpath(trialFolder("simulation", simulation_id), "output")

    physicell_version = physicellVersion(Simulation(simulation_id))
    upstream_version = split(physicell_version, "-")[1] |> VersionNumber

    rules_header = ["cell_type", "signal", "response", "behavior", "base_response", "max_response", "half_max", "hill_power", "applies_to_dead"]
    if upstream_version < v"1.14.0"
        output_rules_file = "cell_rules.csv"
    else #! starting in PhysiCell v1.14.1, export the v3 rules to cell_rules_parsed.csv
        output_rules_file = "cell_rules_parsed.csv"
        filter!(h -> h != "base_response", rules_header)
    end

    path_to_xml = joinpath(path_to_output, "PhysiCell_settings.xml")
    xml_doc = openXML(path_to_xml)
    makeXMLPath(xml_doc, ["save", "folder"])
    updateField(xml_doc, ["save", "folder"], path_to_output)
    if isfile(joinpath(path_to_output, output_rules_file))
        rules_df = CSV.read(joinpath(path_to_output, output_rules_file), DataFrame; header=rules_header)
        if "base_response" in rules_header
            select!(rules_df, Not(:base_response))
        end

        input_rules_file = "cell_rules_temp.csv"
        path_to_input_rules = joinpath(path_to_output, input_rules_file)
        CSV.write(path_to_input_rules, rules_df, writeheader=false)

        makeXMLPath(xml_doc, ["cell_rules", "rulesets", "ruleset:enabled:true", "folder"])
        makeXMLPath(xml_doc, ["cell_rules", "rulesets", "ruleset", "filename"])

        updateField(xml_doc, ["cell_rules", "rulesets", "ruleset", "folder"], path_to_output)
        updateField(xml_doc, ["cell_rules", "rulesets", "ruleset", "filename"], input_rules_file)
    end

    path_to_temp_xml = joinpath(path_to_output, "PhysiCell_settings_temp.xml")
    save_file(xml_doc, path_to_temp_xml)
    closeXML(xml_doc)

    return path_to_temp_xml, path_to_input_rules
end

function executeStudio(python_path::String, studio_path::String, path_to_temp_xml::String, path_to_input_rules::String)
    cmd = `$python_path $(joinpath(studio_path, "bin", "studio.py")) -c $(path_to_temp_xml)`
    try
        run(pipeline(cmd; stdout=devnull, stderr=devnull))
    catch e
        msg = """
        Error running PhysiCell Studio. Please check the paths and ensure that PhysiCell Studio is installed correctly.
        The command that was run was:
        \t$(cmd)

        The error message was:
        \t$(e.msg)
        """

        return Base.IOError(msg, e.code)
    end
end

function cleanUpStudioInputs(path_to_temp_xml::String, path_to_input_rules::String)
    rm(path_to_temp_xml, force=true)
    rm(path_to_input_rules, force=true)
end