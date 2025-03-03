using LightXML, PhysiCellXMLRules

export exportSimulation

"""
    exportSimulation(simulation_id::Integer[, export_folder::AbstractString])
    exportSimulation(simulation::Simulation[, export_folder::AbstractString])

Create a `user_project` folder from a simulation that can be loaded into PhysiCell.

Warning: not all features in drbergman/PhysiCell/latest/release are not supported in MathCancer/PhysiCell.

# Arguments
- `simulation_id::Integer`: the id of the simulation to export
- `simulation::Simulation`: the simulation to export
- `export_folder::AbstractString`: the folder to export the simulation to. Default is the simulation output folder.
"""
function exportSimulation(simulation_id::Integer, export_folder::AbstractString="$(joinpath(outputFolder("simulation", simulation_id), "UserProjectExport"))")
    simulation = Simulation(simulation_id)
    return exportSimulation(simulation, export_folder)
end

function exportSimulation(simulation::Simulation, export_folder::AbstractString="$(joinpath(outputFolder(simulation), "UserProjectExport"))")
    success, physicell_version = prepareFolder(simulation, export_folder)
    if success
        msg = """
        Exported simulation $(simulation.id) successfully to $(export_folder).
        Copy this folder into `PhysiCell/user_projects` for a PhysiCell folder with version $(physicell_version).
        Load it with
            make load PROJ=UserProjectExport # or however you renamed the folder
        Then run it with
            make && $(baseToExecutable("project")) # or however you renamed the executable
        """
        println(msg)
    else
        msg = """
        Exporting simulation $(simulation.id) failed.
        See the error messages above for more information.
        Cleaning up what was created in $(export_folder).
        """
        println(msg)
        rm(export_folder; force=true, recursive=true)
    end
    return export_folder
end

function prepareFolder(simulation::Simulation, export_folder::AbstractString)
    export_config_folder = joinpath(export_folder, "config")
    mkpath(export_config_folder)

    query = constructSelectQuery("simulations", "WHERE simulation_id = $(simulation.id)")
    row = queryToDataFrame(query; is_row=true)

    #! config file
    path_to_xml = joinpath(locationPath(:config, simulation), "config_variations", "config_variation_$(row.config_variation_id[1]).xml")
    cp(path_to_xml, joinpath(export_config_folder, "PhysiCell_settings.xml"))

    #! custom code
    path_to_custom_codes_folder = locationPath(:custom_code, simulation)
    for filename in ["main.cpp", "Makefile"]
        cp(joinpath(path_to_custom_codes_folder, filename), joinpath(export_folder, filename))
    end
    cp(joinpath(path_to_custom_codes_folder, "custom_modules"), joinpath(export_folder, "custom_modules"))

    #! rulesets
    if row.rulesets_collection_id[1] != -1
        path_to_xml = joinpath(locationPath(:rulesets_collection, simulation), "rulesets_collection_variations", "rulesets_collection_variation_$(row.rulesets_collection_variation_id[1]).xml")
        path_to_csv = joinpath(export_folder, "config", "cell_rules.csv")
        exportRulesToCSV(path_to_csv, path_to_xml)
    end

    #! intracellulars
    if row.intracellular_id[1] != -1
        path_to_intracellular = joinpath(locationPath(:intracellular, simulation), "intracellular.xml")
        cp(path_to_intracellular, joinpath(export_folder, "config", "intracellular.xml"))
    end

    #! ic cells
    if row.ic_cell_id[1] != -1
        path_to_ic_cells_folder = locationPath(:ic_cell, simulation)
        ic_cell_file_name = readdir(path_to_ic_cells_folder)
        filter!(x -> x in ["cells.csv", "cells.xml"], ic_cell_file_name)
        ic_cell_file_name = ic_cell_file_name[1]
        if endswith(ic_cell_file_name, ".xml")
            #! rel path from ic_cells_folder
            ic_cell_file_name = joinpath("ic_cell_variations", "ic_cell_variation_$(row.ic_cell_variation_id[1])_s$(simulation.id).csv")
        end
        cp(joinpath(path_to_ic_cells_folder, ic_cell_file_name), joinpath(export_folder, "config", "cells.csv"))
    end

    #! ic substrates
    if row.ic_substrate_id[1] != -1
        path_to_file = joinpath(locationPath(:ic_substrate, simulation), "substrates.csv")
        cp(path_to_file, joinpath(export_folder, "config", "substrates.csv"))
    end

    #! ic ecm
    if row.ic_ecm_id[1] != -1
        path_to_ic_ecm_folder = locationPath(:ic_ecm, simulation)
        ic_ecm_file_name = readdir(path_to_ic_ecm_folder)
        filter!(x -> x in ["ecm.csv", "ecm.xml"], ic_ecm_file_name)
        ic_ecm_file_name = ic_ecm_file_name[1]
        if endswith(ic_ecm_file_name, ".xml")
            #! rel path from ic_ecm_folder
            ic_ecm_file_name = joinpath("ic_ecm_variations", "ic_ecm_variation_$(row.ic_ecm_variation_id[1])_s$(simulation.id).csv")
        end
        cp(joinpath(path_to_ic_ecm_folder, ic_ecm_file_name), joinpath(export_folder, "config", "ecm.csv"))
    end

    #! ic dcs
    if row.ic_dc_id[1] != -1
        path_to_file = joinpath(locationPath(:ic_dc, simulation), "dcs.csv")
        cp(path_to_file, joinpath(export_folder, "config", "dcs.csv"))
    end

    #! get physicell version
    physicell_version_id = row.physicell_version_id[1]
    query = constructSelectQuery("physicell_versions", "WHERE physicell_version_id = $physicell_version_id")
    row = queryToDataFrame(query; is_row=true)
    physicell_version = row.tag[1]
    if ismissing(physicell_version)
        physicell_version = row.commit_hash[1]
    end
    physicell_version = split(physicell_version, "-")[1]
    return revertSimulationFolderToCurrentPhysiCell(export_folder, physicell_version), physicell_version
end

function revertSimulationFolderToCurrentPhysiCell(export_folder::AbstractString, physicell_version::AbstractString)
    success = revertMain(export_folder, physicell_version)
    success &= revertMakefile(export_folder, physicell_version)
    success &= revertConfig(export_folder, physicell_version)
    success &= revertCustomModules(export_folder, physicell_version)
    return success
end

function revertMain(export_folder::AbstractString, physicell_version::AbstractString)
    path_to_main = joinpath(export_folder, "main.cpp")
    lines = readlines(path_to_main)
    idx = findfirst(x -> contains(x, "<getopt.h>"), lines)
    popat!(lines, idx)

    idx1 = findfirst(x -> contains(x, "// read arguments"), lines)
    if isnothing(idx1)
        idx1 = findfirst(x -> contains(x, "argument_parser"), lines)
        if isnothing(idx1)
            msg = """
            Could not identify where the argument_parser ends in the main.cpp file.
            Aborting the export process.
            """
            println(msg)
            return false
        end
    end
    idx2 = findfirst(x -> contains(x, "// copy config file to"), lines)
    if isnothing(idx2)
        idx2 = findfirst(x -> contains(x, "system(") && contains(x, "copy_command"), lines)
        if isnothing(idx2)
            msg = """
            Could not identify where the copy command is in the main.cpp file.
            Aborting the export process.
            """
            println(msg)
            return false
        end
    end
    deleteat!(lines, idx1:(idx2-1))

    parsing_block = """
        // load and parse settings file(s)

        bool XML_status = false; 
        char copy_command [1024]; 
        if( argc > 1 )
        {
            XML_status = load_PhysiCell_config_file( argv[1] ); 
            sprintf( copy_command , "cp %s %s" , argv[1] , PhysiCell_settings.folder.c_str() ); 
        }
        else
        {
            XML_status = load_PhysiCell_config_file( "./config/PhysiCell_settings.xml" );
            sprintf( copy_command , "cp ./config/PhysiCell_settings.xml %s" , PhysiCell_settings.folder.c_str() ); 
        }
        if( !XML_status )
        { exit(-1); }
    """
    lines = [lines[1:(idx1-1)]; parsing_block; lines[idx1:end]]

    open(path_to_main, "w") do io
        for line in lines
            println(io, line)
        end
    end
    return true
end

function revertMakefile(export_folder::AbstractString, physicell_version::AbstractString)
    return true #! nothing to do as of yet for the Makefile
end

function revertConfig(export_folder::AbstractString, physicell_version::AbstractString)
    path_to_config_folder = joinpath(export_folder, "config")
    path_to_config = joinpath(path_to_config_folder, "PhysiCell_settings.xml")
    xml_doc = openXML(path_to_config)

    #! output folder
    folder_element = retrieveElement(xml_doc, ["save", "folder"])
    set_content(folder_element, "output")

    #! ic substrate
    substrate_ic_element = retrieveElement(xml_doc, ["microenvironment_setup", "options", "initial_condition"])
    using_substrate_ics = isfile(joinpath(path_to_config_folder, "substrates.csv"))
    set_attributes(substrate_ic_element; type="csv", enabled=string(using_substrate_ics))
    filename_element = find_element(substrate_ic_element, "filename")
    set_content(filename_element, joinpath(".", "config", "substrates.csv"))

    #! ic cells
    cell_ic_element = retrieveElement(xml_doc, ["initial_conditions", "cell_positions"])
    using_cell_ics = isfile(joinpath(path_to_config_folder, "cells.csv"))
    set_attributes(cell_ic_element; type="csv", enabled=string(using_substrate_ics))
    folder_element = find_element(cell_ic_element, "folder")
    set_content(filename_element, joinpath(".", "config"))
    filename_element = find_element(cell_ic_element, "filename")
    set_content(filename_element, "cells.csv")

    #! ic ecm
    using_ecm_ics = isfile(joinpath(path_to_config_folder, "ecm.csv"))
    if using_ecm_ics
        setECMSetupElement(xml_doc)
    end

    #! ic dcs
    dc_ic_element = retrieveElement(xml_doc, ["microenvironment_setup", "options", "dirichlet_nodes"])
    using_dc_ics = isfile(joinpath(path_to_config_folder, "dcs.csv"))
    set_attributes(dc_ic_element; type="csv", enabled=string(using_dc_ics))
    filename_element = find_element(dc_ic_element, "filename")
    set_content(filename_element, joinpath("config", "dcs.csv"))

    #! rulesets
    rules_element = retrieveElement(xml_doc, ["cell_rules", "rulesets", "ruleset"])
    using_rules = isfile(joinpath(path_to_config_folder, "cell_rules.csv"))
    set_attributes(rules_element; type="csv", enabled=string(using_rules))
    folder_element = find_element(rules_element, "folder")
    set_content(filename_element, joinpath(".", "config"))
    filename_element = find_element(rules_element, "filename")
    set_content(filename_element, "cell_rules.csv")

    #! intracellulars
    #! lol, not supported for export yet

    closeXML(xml_doc)
    return true
end

function setECMSetupElement(xml_doc::XMLDocument)
    ecm_setup_element = retrieveElement(xml_doc, ["microenvironment_setup", "ecm_setup"])
    if isnothing(ecm_setup_element)
        xml_root = root(xml_doc)
        microenvironment_setup_element = find_element(xml_root, "microenvironment_setup")
        ecm_setup_element = new_child(microenvironment_setup_element, "ecm_setup")
    end
    set_attributes(ecm_setup_element; enabled="true", format="csv")
    folder_element = find_element(ecm_setup_element, "folder")
    if isnothing(folder_element)
        folder_element = new_child(ecm_setup_element, "folder")
    end
    set_content(folder_element, joinpath(".", "config"))
    filename_element = find_element(ecm_setup_element, "filename")
    if isnothing(filename_element)
        filename_element = new_child(ecm_setup_element, "filename")
    end
    set_content(filename_element, "ecm.csv")
    return
end

function revertCustomModules(export_folder::AbstractString, physicell_version::AbstractString)
    path_to_custom_modules = joinpath(export_folder, "custom_modules")
    success = revertCustomHeader(path_to_custom_modules, physicell_version)
    success &= revertCustomCPP(path_to_custom_modules, physicell_version)
    return success
end

function revertCustomHeader(path_to_custom_modules::AbstractString, physicell_version::AbstractString)
    return true #! nothing to do as of yet for the custom header
end

function revertCustomCPP(path_to_custom_modules::AbstractString, physicell_version::AbstractString)
    path_to_custom_cpp = joinpath(path_to_custom_modules, "custom.cpp")
    lines = readlines(path_to_custom_cpp)
    idx = findfirst(x -> contains(x, "load_initial_cells();"), lines)

    lines[idx] = "\tload_cells_from_pugixml();"

    open(path_to_custom_cpp, "w") do io
        for line in lines
            println(io, line)
        end
    end
    return true
end