using LightXML

export importProject

mutable struct ImportSource
    src_key::Symbol
    input_folder_key::Symbol
    path_from_project::AbstractString
    pcvct_name::AbstractString
    type::AbstractString
    required::Bool
    found::Bool
end

function ImportSource(src::Dict, key::AbstractString, path_from_project_base::AbstractString, default::String, type::AbstractString, required::Bool; input_folder_key::Symbol=Symbol(key), pcvct_name::String=default)
    is_key = haskey(src, key)
    path_from_project = joinpath(path_from_project_base, is_key ? src[key] : default)
    required |= is_key
    found = false
    return ImportSource(Symbol(key), input_folder_key, path_from_project, pcvct_name, type, required, found)
end

struct ImportSources
    config::ImportSource
    main::ImportSource
    makefile::ImportSource
    custom_modules::ImportSource
    rulesets_collection::ImportSource
    intracellular::ImportSource
    ic_cell::ImportSource
    ic_substrate::ImportSource
    ic_ecm::ImportSource
    ic_dc::ImportSource
end

function ImportSources(src::Dict, path_to_project::AbstractString)
    required = true
    config = ImportSource(src, "config", "config", "PhysiCell_settings.xml", "file", required)
    main = ImportSource(src, "main", "", "main.cpp", "file", required; input_folder_key = :custom_code)
    makefile = ImportSource(src, "makefile", "", "Makefile", "file", required; input_folder_key = :custom_code)
    custom_modules = ImportSource(src, "custom_modules", "", "custom_modules", "folder", required; input_folder_key = :custom_code)

    required = false
    rules = ImportSource(src, "rules", "config", "cell_rules.csv", "file", required; pcvct_name="base_rulesets.csv")
    intracellular = prepareIntracellularImport(src, config, path_to_project)
    ic_cell = ImportSource(src, "ic_cell", "config", "cells.csv", "file", required)
    ic_substrate = ImportSource(src, "ic_substrate", "config", "substrates.csv", "file", required)
    ic_ecm = ImportSource(src, "ic_ecm", "config", "ecm.csv", "file", required)
    ic_dc = ImportSource(src, "ic_dc", "config", "dcs.csv", "file", required)
    return ImportSources(config, main, makefile, custom_modules, rules, intracellular, ic_cell, ic_substrate, ic_ecm, ic_dc)
end

function prepareIntracellularImport(src::Dict, config::ImportSource, path_to_project::AbstractString)
    if haskey(src, "intracellular") || isfile(joinpath(path_to_project, "config", "intracellular.xml"))
        return ImportSource(src, "intracellular", "config", "intracellular.xml", "file", true)
    end
    #! now attempt to read the config file and assemble the intracellular file
    path_to_xml = joinpath(path_to_project, config.path_from_project)
    if !isfile(path_to_xml) #! if the config file is not found, then we cannot proceed with grabbing the intracellular data, just return the default
        return ImportSource(src, "intracellular", "config", "intracellular.xml", "file", false)
    end
    xml_doc = openXML(path_to_xml)
    cell_definitions_element = retrieveElement(xml_doc, ["cell_definitions"])
    cell_type_to_components_dict = Dict{String,PhysiCellComponent}()
    for cell_definition_element in child_elements(cell_definitions_element)
        if name(cell_definition_element) != "cell_definition"
            continue
        end
        cell_type = attribute(cell_definition_element, "name")
        phenotype_element = find_element(cell_definition_element, "phenotype")
        intracellular_element = find_element(phenotype_element, "intracellular")
        if isnothing(intracellular_element)
            continue
        end
        type = attribute(intracellular_element, "type")
        if type ∉ ["roadrunner", "dfba"]
            throw(ErrorException("pcvct does not yet support intracellular type $type."))
        end
        path_to_file = find_element(intracellular_element, "sbml_filename") |> content
        temp_component = PhysiCellComponent(type, basename(path_to_file))
        #! now we have to rely on the path to the file is correct relative to the parent directory of the config file (that should usually be the case)
        path_to_src = joinpath(path_to_project, path_to_file)
        path_to_dest = _create_component_dest_file_name(readlines(path_to_src), temp_component)
        component = PhysiCellComponent(type, basename(path_to_dest))
        if !isfile(path_to_dest)
            cp(path_to_src, path_to_dest)
        end

        cell_type_to_components_dict[cell_type] = component
    end

    if isempty(cell_type_to_components_dict)
        return ImportSource(src, "intracellular", "config", "intracellular.xml", "file", false)
    end

    intracellular_folder = assembleIntracellular!(cell_type_to_components_dict; name="temp_assembled_from_$(splitpath(path_to_project)[end])", skip_db_insert=true)
    mv(joinpath(locationPath(:intracellular, intracellular_folder), "intracellular.xml"), joinpath(path_to_project, "config", "assembled_intracellular_for_import.xml"); force=true)
    rm(locationPath(:intracellular, intracellular_folder); force=true, recursive=true)
    
    closeXML(xml_doc)
    return ImportSource(src, "intracellular", "config", "assembled_intracellular_for_import.xml", "file", true; pcvct_name="intracellular.xml")
end

function _create_component_dest_file_name(src_lines::Vector{String}, component::PhysiCellComponent)
    base_path = joinpath(data_dir, "components", component.path_from_components)
    folder = dirname(base_path)
    mkpath(folder)
    base_filename, file_ext = basename(base_path) |> splitext
    n = 0
    path_to_dest = joinpath(folder, base_filename * file_ext)
    while isfile(path_to_dest)
        if src_lines == readlines(path_to_dest)
            return path_to_dest
        end
        n += 1
        path_to_dest = joinpath(folder, base_filename * "_$(n)" * file_ext)
    end
    return path_to_dest
end

mutable struct ImportDestFolder
    path_from_inputs::AbstractString
    created::Bool
    description::AbstractString
end

struct ImportDestFolders
    config::ImportDestFolder
    custom_code::ImportDestFolder
    rules::ImportDestFolder
    intracellular::ImportDestFolder
    ic_cell::ImportDestFolder
    ic_substrate::ImportDestFolder
    ic_ecm::ImportDestFolder
    ic_dc::ImportDestFolder
end

function ImportDestFolders(path_to_project::AbstractString, dest::Dict)
    default_name = splitpath(path_to_project)[end]
    path_fn(k::String, p::String) = joinpath(p, haskey(dest, k) ? dest[k] : default_name)
    created = false
    description = "Imported from project at $(path_to_project)."

    #! required folders
    config = ImportDestFolder(path_fn("config", "configs"), created, description)
    custom_code = ImportDestFolder(path_fn("custom_code", "custom_codes"), created, description)

    #! optional folders
    rules = ImportDestFolder(path_fn("rules", "rulesets_collections"), created, description)
    intracellular = ImportDestFolder(path_fn("intracellular", "intracellulars"), created, description)
    ic_cell = ImportDestFolder(path_fn("ic_cell", joinpath("ics", "cells")), created, description)
    ic_substrate = ImportDestFolder(path_fn("ic_substrate", joinpath("ics", "substrates")), created, description)
    ic_ecm = ImportDestFolder(path_fn("ic_ecm", joinpath("ics", "ecms")), created, description)
    ic_dc = ImportDestFolder(path_fn("ic_dc", joinpath("ics", "dcs")), created, description)
    return ImportDestFolders(config, custom_code, rules, intracellular, ic_cell, ic_substrate, ic_ecm, ic_dc)
end

"""
    importProject(path_to_project::AbstractString[, src=Dict(), dest=Dict(); extreme_caution::Bool=false])

Import a project from the structured in the format of PhysiCell sample projects and user projects into the pcvct structure.

# Arguments
- `path_to_project::AbstractString`: Path to the project to import. Relative paths are resolved from the current working directory where Julia was launched.
- `src::Dict`: Dictionary of the project sources to import. If absent, tries to use the default names.
The following keys are recognized: $(join(["`$fn`" for fn in fieldnames(ImportSources)], ", ", ", and ")).
- `dest::Dict`: Dictionary of the inputs folders to create in the pcvct structure. If absent, taken from the project name.
The following keys are recognized: $(join(["`$fn`" for fn in fieldnames(ImportDestFolders)], ", ", ", and ")).
- `extreme_caution::Bool`: If true, will ask for confirmation before deleting any folders created during the import process. Care has been taken to ensure this is unnecessary. Provided for users who want to be extra cautious.
"""
function importProject(path_to_project::AbstractString, src=Dict(), dest=Dict(); extreme_caution::Bool=false)
    project_sources = ImportSources(src, path_to_project)
    import_dest_folders = ImportDestFolders(path_to_project, dest)
    success = resolveProjectSources!(project_sources, path_to_project)
    if success
        success = createInputFolders!(import_dest_folders, project_sources)
        success = success && copyFilesToFolders(path_to_project, project_sources, import_dest_folders) #! only copy if successful so far
        success = success && adaptProject(import_dest_folders)
    end
    if success
        msg = """
        Imported project from $(path_to_project) into $(joinpath(data_dir, "inputs")):
            - $(import_dest_folders.config.path_from_inputs)
            - $(import_dest_folders.custom_code.path_from_inputs)
        """
        if import_dest_folders.rules.created
            msg *= "    - $(import_dest_folders.rules.path_from_inputs)"
        end
        if import_dest_folders.intracellular.created
            msg *= "    - $(import_dest_folders.intracellular.path_from_inputs)"
        end
        ics_started = false
        for ic in ["cell", "substrate", "ecm", "dc"]
            import_dest_folder = getfield(import_dest_folders, Symbol("ic_$(ic)"))::ImportDestFolder
            if import_dest_folder.created
                if !ics_started
                    msg *= "\n    - ICs:"
                    ics_started = true
                end
                msg *= "\n      - $(splitpath(import_dest_folder.path_from_inputs)[2:end] |> joinpath)"
            end
        end
        println(msg)
        println("Re-initializing the database to include these new entries...")
        reinitializeDatabase()
    else
        msg = """
        Failed to import user_project from $(path_to_project) into $(joinpath(data_dir, "inputs")).
        See the error messages above for more information.
        Cleaning up what was created in $(joinpath(data_dir, "inputs")).
        """
        println(msg)
        if extreme_caution
            println("You wanted to show extreme caution, so we will ask about each folder before deleting.")
        else
            println(
            """
            Only folders created in this process are being deleted (you can set the optional keyword argument `extreme_caution` to check each folder)
                importProject(...; extreme_caution=true)
            """
            )
        end
        path_to_inputs = joinpath(data_dir, "inputs")
        for fieldname in fieldnames(ImportDestFolders)
            import_dest_folder = getfield(import_dest_folders, fieldname)
            if import_dest_folder.created
                path_to_folder = joinpath(path_to_inputs, import_dest_folder.path_from_inputs)
                if extreme_caution
                    println("Deleting the newly created $(fieldname) folder at $(path_to_folder). Proceed with deletion? (y/n)")
                    response = readline()
                    if response != "y"
                        println("\tYou entered '$response'. Not deleting.")
                        continue
                    end
                end
                rm(path_to_folder; force=true, recursive=true)
            end
        end
    end
    return success
end

function resolveProjectSources!(project_sources::ImportSources, path_to_project::AbstractString)
    success = true
    for fieldname in fieldnames(ImportSources)
        project_source = getfield(project_sources, fieldname)::ImportSource
        success &= resolveProjectSource!(project_source, path_to_project)
    end
    return success
end

function resolveProjectSource!(project_source::ImportSource, path_to_project::AbstractString)
    exist_fn = project_source.type == "file" ? isfile : isdir
    project_source.found = exist_fn(joinpath(path_to_project, project_source.path_from_project))
    if project_source.found || !project_source.required
        return true
    end

    msg = """
    Source $(project_source.type) $(project_source.path_from_project) does not exist in $(path_to_project).
    Update the src dictionary to include the correct $(project_source.type) name.
    For example: `src=Dict("$(project_source.src_key)"=>"$(splitpath(project_source.path_from_project)[end])")`.
    Aborting import.
    """
    println(msg)
    return false
end

function createInputFolders!(import_dest_folders::ImportDestFolders, project_sources::ImportSources)
    #! required folders
    success = createInputFolder!(import_dest_folders.config)
    success &= createInputFolder!(import_dest_folders.custom_code)

    #! optional folders
    for fieldname in fieldnames(ImportSources)
        if fieldname in [:config, :main, :makefile, :custom_modules]
            continue
        end
        project_source = getfield(project_sources, fieldname)
        if project_source.found
            success &= createInputFolder!(getfield(import_dest_folders, project_source.src_key)::ImportDestFolder)
        end
    end
    return success
end

function createInputFolder!(import_dest_folder::ImportDestFolder)
    path_to_inputs = joinpath(data_dir, "inputs")
    path_from_inputs_vec = splitpath(import_dest_folder.path_from_inputs)
    path_from_inputs_to_collection = joinpath(path_from_inputs_vec[1:end-1]...)
    folder_base = path_from_inputs_vec[end]
    collection_contents = joinpath(path_to_inputs, path_from_inputs_to_collection) |> readdir
    filter!(x->startswith(x, folder_base), collection_contents)
    folder_name = folder_base
    n = 0
    while folder_name in collection_contents
        n += 1
        folder_name = "$(folder_base)_$(n)"
    end
    import_dest_folder.path_from_inputs = joinpath(path_from_inputs_to_collection, folder_name)
    path_to_folder = joinpath(path_to_inputs, import_dest_folder.path_from_inputs)
    mkpath(path_to_folder)
    path_to_metadata = joinpath(path_to_folder, "metadata.xml")
    writeDescriptionToMetadata(path_to_metadata, import_dest_folder.description)
    import_dest_folder.created = true
    return true
end

function writeDescriptionToMetadata(path_to_metadata::AbstractString, description::AbstractString)
    xml_doc = XMLDocument()
    xml_root = create_root(xml_doc, "metadata")
    description_element = new_child(xml_root, "description")
    set_content(description_element, description)
    save_file(xml_doc, path_to_metadata)
    free(xml_doc)
    return
end

function copyFilesToFolders(path_to_project::AbstractString, project_sources::ImportSources, import_dest_folders::ImportDestFolders)
    success = true
    for fieldname in fieldnames(ImportSources)
        project_source = getfield(project_sources, fieldname)::ImportSource
        if !project_source.found
            continue
        end
        src = joinpath(path_to_project, project_source.path_from_project)
        import_dest_folder = getfield(import_dest_folders, project_source.input_folder_key)
        dest = joinpath(data_dir, "inputs", import_dest_folder.path_from_inputs, project_source.pcvct_name)
        if dest |> (project_source.type == "file" ? isfile : isdir)
            msg = """
            In copying $(src) to $(dest), found a $(project_source.type) with the same name.
            This should be avoided by pcvct.
            Please open an Issue on GitHub and document your setup and steps.
            """
            println(msg)
            success = false
            continue
        end
        cp(src, dest)
    end
    return success
end

function adaptProject(import_dest_folders::ImportDestFolders)
    success = adaptConfig(import_dest_folders.config)
    success &= adaptCustomCode(import_dest_folders.custom_code)
    return success
end

function adaptConfig(config::ImportDestFolder)
    return true #! nothing to do for now
end

function adaptCustomCode(custom_code::ImportDestFolder)
    success = adaptMain(custom_code.path_from_inputs)
    success &= adaptMakefile(custom_code.path_from_inputs)
    success &= adaptCustomModules(joinpath(custom_code.path_from_inputs, "custom_modules"))
    return success
end

function adaptMain(path_from_inputs::AbstractString)
    path_to_main = joinpath(data_dir, "inputs", path_from_inputs, "main.cpp")
    lines = readlines(path_to_main)

    if any(x->contains(x, "argument_parser.parse"), lines)
        #! already adapted the main.cpp
        return true
    end

    idx1 = findfirst(x->contains(x, "// load and parse settings file(s)"), lines)
    if isnothing(idx1)
        idx1 = findfirst(x->contains(x, "bool XML_status = false;"), lines)
        if isnothing(idx1)
            msg = """
            Could not find the line to insert the settings file parsing code.
            Aborting the import process.
            """
            println(msg)
            return false
        end
    end
    idx_not_xml_status = findfirst(x->contains(x, "!XML_status"), lines)
    idx2 = idx_not_xml_status + findfirst(x -> contains(x, "}"), lines[idx_not_xml_status:end]) - 1
    # idx2 = findfirst(x -> contains(x, "// copy config file to"), lines)
    # if isnothing(idx2)
    #     idx2 = findfirst(x -> contains(x, "system(") && contains(x, "copy_command"), lines)
    #     if isnothing(idx2)
    #         idx2 = findfirst(x -> contains(x, "// OpenMP setup"), lines)
    #         if isnothing(idx2)
    #             idx2 = findfirst(x -> contains(x, "omp_set_num_threads("), lines)
    #             if isnothing(idx2)
    #                 msg = """
    #                 Could not identify where the copy command is in the main.cpp file.
    #                 Aborting the export process.
    #                 """
    #                 println(msg)
    #                 return false
    #             end
    #         end
    #     end
    # end
    deleteat!(lines, idx1:idx2)

    parsing_block = """
        // read arguments
        argument_parser.parse(argc, argv);

        // load and parse settings file(s)
        load_PhysiCell_config_file();

        char copy_command [1024]; 

        sprintf( copy_command , "cp %s %s/PhysiCell_settings.xml" , argument_parser.path_to_config_file.c_str(), PhysiCell_settings.folder.c_str() ); //, PhysiCell_settings.folder.c_str() ); 
    """
    insert!(lines, idx1, parsing_block)

    open(path_to_main, "w") do f
        for line in lines
            println(f, line)
        end
    end
    return true
end

function adaptMakefile(path_from_inputs::AbstractString)
    return true #! nothing to do for now
end

function adaptCustomModules(path_from_inputs::AbstractString)
    success = adaptCustomHeader(path_from_inputs)
    success &= adaptCustomCPP(path_from_inputs)
    return success
end

function adaptCustomHeader(path_from_inputs::AbstractString)
    return true #! nothing to do for now
end

function adaptCustomCPP(path_from_inputs::AbstractString)
    path_to_custom_cpp = joinpath(data_dir, "inputs", path_from_inputs, "custom.cpp")
    lines = readlines(path_to_custom_cpp)
    idx = findfirst(x->contains(x, "load_cells_from_pugixml"), lines)

    if isnothing(idx)
        if !any(x->contains(x, "load_initial_cells"), lines)
            msg = """
            Could not find the line to insert the initial cells loading code.
            Aborting the import process.
            """
            println(msg)
            return false
        end
        return true
    end

    lines[idx] = "\tload_initial_cells();"

    open(path_to_custom_cpp, "w") do f
        for line in lines
            println(f, line)
        end
    end
    return true
end