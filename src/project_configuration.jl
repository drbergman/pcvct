using TOML

project_locations = NamedTuple()

struct ProjectLocations{L,M,N}
    all::NTuple{L,Symbol}
    required::NTuple{M,Symbol}
    varied::NTuple{N,Symbol}

    function ProjectLocations(inputs_dict::Dict{Symbol,Any})
        all_locations = (location for location in keys(inputs_dict)) |> collect |> sort |> Tuple
        required = (location for (location, location_dict) in pairs(inputs_dict) if location_dict["required"]) |> collect |> sort |> Tuple
        varied_locations = (location for (location,location_dict) in pairs(inputs_dict) if any(location_dict["varied"])) |> collect |> sort |> Tuple
        return new{length(all_locations),length(required),length(varied_locations)}(all_locations, required, varied_locations)
    end
end

function sanitizePathElements(path_elements::Vector{String})
    for element in path_elements
        #! Disallow `..` to prevent directory traversal
        if element == ".."
            throw(ArgumentError("Path element '..' is not allowed"))
        end

        #! Disallow absolute paths
        if isabspath(element)
            throw(ArgumentError("Absolute paths are not allowed"))
        end

        #! Disallow special characters or sequences (e.g., `~`, `*`, etc.)
        if contains(element, r"[~*?<>|:]")
            throw(ArgumentError("Path element contains invalid characters"))
        end
    end
    return path_elements
end

sanitizePathElements(path_element::String) = sanitizePathElements([path_element])

function parseProjectInputsConfigurationFile()
    inputs_dict_temp = Dict{String, Any}()
    try
        inputs_dict_temp = TOML.parsefile(joinpath(data_dir, "inputs.toml"))
    catch e
        println("Error parsing project configuration file: ", e)
        return false
    end
    for (location, location_dict) in pairs(inputs_dict_temp)
        if !("path_from_inputs" in keys(location_dict))
            location_dict["path_from_inputs"] = tableName(location)
        else
            location_dict["path_from_inputs"] = location_dict["path_from_inputs"] |> sanitizePathElements |> joinpath
        end
        if !("basename" in keys(location_dict))
            location_dict["basename"] = missing
        else
            @assert haskey(location_dict, "varied") "inputs.toml: $(location): basename must be accompanied by varied."
            if location_dict["varied"] isa Vector
                @assert location_dict["basename"] isa Vector && length(location_dict["varied"]) == length(location_dict["basename"]) "inputs.toml: $(location): varied must be a Bool or a Vector of the same length as basename."
            end
        end
    end
    global inputs_dict = [Symbol(location) => location_dict for (location, location_dict) in pairs(inputs_dict_temp)] |> Dict{Symbol, Any}
    global project_locations = ProjectLocations(inputs_dict)
    createSimpleInputFolders()
    println(rpad("Path to inputs.toml:", 25, ' ') * joinpath(data_dir, "inputs.toml"))
    return true
end

locationIDName(location::Union{String,Symbol}) = "$(location)_id"
locationVarIDName(location::Union{String,Symbol}) = "$(location)_variation_id"
locationIDNames() = (locationIDName(loc) for loc in project_locations.all)
locationVariationIDNames() = (locationVarIDName(loc) for loc in project_locations.varied)
tableName(location::Union{String,Symbol}) = "$(location)s"
variationsTableName(location::Union{String,Symbol}) = "$(location)_variations"

function locationPath(location::Symbol, folder=missing)
    location_dict = inputs_dict[Symbol(location)]
    path_to_locations = joinpath(data_dir, "inputs", location_dict["path_from_inputs"])
    return ismissing(folder) ? path_to_locations : joinpath(path_to_locations, folder)
end

function locationPath(input_folder::InputFolder)
    return locationPath(input_folder.location, input_folder.folder)
end

function locationPath(location::Symbol, S::AbstractSampling)
    return locationPath(location, S.inputs[location].folder)
end

function folderIsVaried(location::Symbol, folder::String)
    location_dict = inputs_dict[location]
    varieds = location_dict["varied"]
    if !any(varieds)
        return false #! if none of the basenames are declared to be varied, then the folder is not varied
    end
    basenames = location_dict["basename"]
    basenames = basenames isa Vector ? basenames : [basenames]
    @assert varieds isa Bool || length(varieds) == length(basenames) "varied must be a Bool or a Vector of the same length as basename"
    varieds = varieds isa Vector ? varieds : fill(varieds, length(basenames))

    #! look for the first basename in the folder. if that one is varied, then this is a potential target for varying
    path_to_folder = locationPath(location, folder)
    for (basename, varied) in zip(basenames, varieds)
        path_to_file = joinpath(path_to_folder, basename)
        if isfile(path_to_file)
            return varied
        end
    end
    throw(ErrorException("No basename files found in folder $(path_to_folder). Must be one of $(basenames)"))
end

function createInputsTOMLTemplate(path_to_toml::String)
    s = """
    [config]
    required = true
    varied = true
    basename = "PhysiCell_settings.xml"

    [custom_code]
    required = true
    varied = false

    [rulesets_collection]
    required = false
    varied = true
    basename = ["base_rulesets.csv", "base_rulesets.xml"]

    [intracellular]
    required = false
    varied = true
    basename = "intracellular.xml"

    [ic_cell]
    path_from_inputs = ["ics", "cells"]
    required = false
    varied = [false, true]
    basename = ["cells.csv", "cells.xml"]

    [ic_substrate]
    path_from_inputs = ["ics", "substrates"]
    required = false
    varied = false
    basename = "substrates.csv"

    [ic_ecm]
    path_from_inputs = ["ics", "ecms"]
    required = false
    varied = [false, true]
    basename = ["ecm.csv", "ecm.xml"]

    [ic_dc]
    path_from_inputs = ["ics", "dcs"]
    required = false
    varied = false
    basename = "dcs.csv"
    """
    open(path_to_toml, "w") do f
        write(f, s)
    end
    return
end
