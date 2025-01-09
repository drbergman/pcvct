using Downloads, JSON3, CSV

export createProject

"""
    createProject(project_dir::String="."; clone_physicell::Bool=true, template_as_default::Bool=true, terse::Bool=false)

Create a new pcvct project structure.

Creates a new project directory at `project_dir` with the following structure:
```
project_dir
├── data
├── PhysiCell # The latest release from https://github.com/drbergman/PhysiCell
└── VCT
```
`data` is populated with the standard structure. `PhysiCell` is a copy of PhysiCell. `VCT` contains a generated `GenerateData.jl` file.

# Arguments
- `project_dir::String="."`: The directory in which to create the project. Relative paths are resolved from the current working directory where Julia was launched.
- `clone_physicell::Bool=true`: Whether to clone the PhysiCell repository. If `false`, the latest release will be downloaded. Recommended to set to `true` so pcvct will be able to track changes to the PhysiCell repository.
- `template_as_default::Bool=true`: Whether to set up the project with the template files as the default. If `false`, the project will be set up with an empty structure.
- `terse::Bool=false`: Whether to generate a terse `GenerateData.jl` file. If `true`, the file will be generated without comments and explanations.

# Note
The names of the `data` and `PhysiCell` directories are fixed and cannot be changed. Their relative locations should not be changed without updating the `GenerateData.jl` file.
The name of the `VCT` file and the `GenerateData.jl` are just by convention and can be changed.
"""
function createProject(project_dir::String="."; clone_physicell::Bool=true, template_as_default::Bool=true, terse::Bool=false)
    mkpath(project_dir)
    physicell_dir = setUpPhysiCell(project_dir, clone_physicell)
    data_dir = joinpath(project_dir, "data")

    setUpInputs(data_dir, physicell_dir, template_as_default)
    setUpVCT(project_dir, physicell_dir, data_dir, template_as_default, terse)
end

function getLatestReleaseTag(repo_url::String)
    api_url = replace(repo_url, "github.com" => "api.github.com/repos") * "/releases/latest"
    # include this header for CI testing to not exceed request limit (I think?): macos for some reason raised a `RequestError: HTTP/2 403`; users should not need to set this ENV variable
    headers = haskey(ENV, "PCVCT_PUBLIC_REPO_AUTH") ? Dict("Authorization" => "token $(ENV["PCVCT_PUBLIC_REPO_AUTH"])") : Pair{String,String}[] 
    response = Downloads.download(api_url; headers=headers)
    release_info = JSON3.read(response, Dict{String, Any})
    return release_info["tag_name"]
end

function setUpPhysiCell(project_dir::String, clone_physicell::Bool)
    physicell_dir = joinpath(project_dir, "PhysiCell")
    if isdir(physicell_dir)
        println("PhysiCell directory already exists ($(physicell_dir)). Hopefully it's the pcvct-compatible version!")
        return physicell_dir
    end
    is_git_repo = isdir(joinpath(project_dir, ".git"))
    if clone_physicell
        latest_tag = getLatestReleaseTag("https://github.com/drbergman/PhysiCell")
        if is_git_repo
            println("Cloning PhysiCell repository as submodule")
            run(`git submodule add https://github.com/drbergman/PhysiCell $(physicell_dir)`)
            run(`git submodule update --init --recursive --depth 1`)
            run(`git -C $physicell_dir checkout $latest_tag`)
        else
            println("Cloning PhysiCell repository")
            run(`git clone --branch $latest_tag --depth 1 https://github.com/drbergman/PhysiCell $(physicell_dir)`)
        end
    else
        # download drbergman/Pysicell main branch
        println("Downloading PhysiCell repository")
        url = "https://api.github.com/repos/drbergman/PhysiCell/releases/latest"
        headers = haskey(ENV, "PCVCT_PUBLIC_REPO_AUTH") ? Dict("Authorization" => "token $(ENV["PCVCT_PUBLIC_REPO_AUTH"])") : Pair{String,String}[]
        response = Downloads.download(url; headers=headers)
        release_data = JSON3.read(response)
        zipball_url = release_data["zipball_url"]
        zip_path = joinpath(project_dir, "PhysiCell.zip")
        Downloads.download(zipball_url, zip_path)
        extract_path = joinpath(project_dir, "PhysiCell_extract")
        run(pipeline(`unzip $zip_path -d $extract_path`; stdout=devnull))
        rm(zip_path)
        @assert (readdir(extract_path) |> length) == 1
        path_to_extracted_physicell = readdir(extract_path; join=true)[1]
        mv(path_to_extracted_physicell, physicell_dir)
        rm(extract_path; recursive=false)
    end
    return physicell_dir
end

function setUpInputs(data_dir::String, physicell_dir::String, template_as_default::Bool)
    if isdir(data_dir)
        println("Data directory already exists ($(data_dir)). Skipping setup of data directory.")
        return
    end
    inputs_dir = joinpath(data_dir, "inputs")
    mkpath(inputs_dir)

    mkpath(joinpath(inputs_dir, "configs"))
    mkpath(joinpath(inputs_dir, "custom_codes"))
    for ic in ["cells", "substrates", "ecms"]
        mkpath(joinpath(inputs_dir, "ics", ic))
    end
    mkpath(joinpath(inputs_dir, "rulesets_collections"))

    if template_as_default
        setUpTemplate(physicell_dir, inputs_dir)
    end
end

function setUpRequiredFolders(path_to_template::String, inputs_dir::String, folder::String)
    config_folder = joinpath(inputs_dir, "configs", folder)
    mkpath(config_folder)
    cp(joinpath(path_to_template, "config", "PhysiCell_settings.xml"), joinpath(config_folder, "PhysiCell_settings.xml"))

    custom_codes_folder = joinpath(inputs_dir, "custom_codes", folder)
    mkpath(custom_codes_folder)
    cp(joinpath(path_to_template, "custom_modules"), joinpath(custom_codes_folder, "custom_modules"))
    cp(joinpath(path_to_template, "main.cpp"), joinpath(custom_codes_folder, "main.cpp"))
    cp(joinpath(path_to_template, "Makefile"), joinpath(custom_codes_folder, "Makefile"))
end

function setUpICFolder(path_to_template::String, inputs_dir::String, ic_name::String, folder::String)
    ic_folder = joinpath(inputs_dir, "ics", ic_name, folder)
    mkpath(ic_folder)
    filename = icFilename(ic_name)
    cp(joinpath(path_to_template, "config", filename), joinpath(ic_folder, filename))
end

function setUpTemplate(physicell_dir::String, inputs_dir::String)
    path_to_template = joinpath(physicell_dir, "sample_projects", "template")

    setUpRequiredFolders(path_to_template, inputs_dir, "0_template")

    rulesets_collection_folder = joinpath(inputs_dir, "rulesets_collections", "0_template")
    mkpath(rulesets_collection_folder)
    open(joinpath(rulesets_collection_folder, "base_rulesets.csv"), "w") do f
        write(f, "default,pressure,decreases,cycle entry,0.0,0.5,4,0") # actually add a rule for example's sake
    end

    setUpICFolder(path_to_template, inputs_dir, "cells", "0_template")
    setUpICFolder(path_to_template, inputs_dir, "substrates", "0_template")

    # also set up a ic cell folder using the xml-based version
    createICCellXMLTemplate("1_xml")
end

function setUpVCT(project_dir::String, physicell_dir::String, data_dir::String, template_as_default::Bool, terse::Bool)
    path_to_vct = joinpath(project_dir, "VCT")
    mkpath(path_to_vct)

    path_to_generate_data = joinpath(path_to_vct, "GenerateData.jl")
    if isfile(path_to_generate_data)
        println("GenerateData.jl already exists ($(joinpath(path_to_vct,"GenerateData.jl"))). Skipping creation of this starter file.")
        return
    end
    path_to_configs = joinpath(data_dir, "inputs", "configs")
    config_folder = template_as_default ? "\"0_template\" # this folder is located at $(path_to_configs)" : "\"default\" # add this folder with config file to $(path_to_configs)"

    path_to_rulesets_collections = joinpath(data_dir, "inputs", "rulesets_collections")
    rulesets_collection_folder = template_as_default ? "\"0_template\" # this folder is located at $(path_to_rulesets_collections); a rule has been added for the sake of the example" : "\"\" # optionally add this folder with base_rulesets.csv to $(path_to_rulesets_collections)"

    path_to_custom_codes = joinpath(data_dir, "inputs", "custom_codes")
    custom_code_folder = template_as_default ? "\"0_template\" # this folder is located at $(path_to_custom_codes)" : "\"default\" # add this folder with main.cpp, Makefile, and custom_modules to $(path_to_custom_codes)"

    path_to_ics = joinpath(data_dir, "inputs", "ics")
    path_to_ic_cells = joinpath(path_to_ics, "cells")
    ic_cell_folder = template_as_default ? "\"0_template\" # this folder is located at $(path_to_ic_cells)" : "\"\" # optionally add this folder with cells.csv to $(path_to_ic_cells)"

    tersify(s::String) = (terse ? "" : s)
    generate_data_lines = """
        using pcvct
        initializeVCT(\"$(abspath(physicell_dir))\", \"$(abspath(data_dir))\")
        
        ############ set up ############

        config_folder = $(config_folder)
        rulesets_collection_folder = $(rulesets_collection_folder)
        custom_code_folder = $(custom_code_folder)
        
        ic_cell_folder = $(ic_cell_folder)
        ic_substrate_folder = \"\" # optionally add this folder with substrates.csv to $(joinpath(path_to_ics, "substrates"))
        ic_ecm_folder = \"\" # optionally add this folder with ecms.csv to $(joinpath(path_to_ics, "ecms"))

        $(tersify("""
        # package them all together into a single object
        """))\
        inputs = InputFolders(config_folder, custom_code_folder;
                              rulesets_collection=rulesets_collection_folder,
                              ic_cell=ic_cell_folder,
                              ic_substrate=ic_substrate_folder,
                              ic_ecm=ic_ecm_folder)

        ############ make the simulations short ############

        $(tersify("""
        # We will set the default simulations to have a lower max time.
        # This will serve as a reference for the following simulations.
        """))\
        xml_path = [\"overall\"; \"max_time\"]
        value = 60.0
        dv_max_time = DiscreteVariation(xml_path, value)
        reference = createTrial(inputs, dv_max_time; n_replicates=0) # since we don't want to run this, set the n_replicates to 0

        ############ set up variables to control running simulations ############

        $(tersify("""
        # you can force the recompilation, but it is usually only necesary if you change core code
        # if you change custom code, it is recommended you make a new custom codes folder in $(path_to_custom_codes)...
        # ...especially if the database already has simulations run with that custom code
        """))\
        force_recompile = false

        $(tersify("""
        # pcvct records which simulations all use the same parameter vector...
        # ...to reuse them (unless the user opts out)
        """))\
        use_previous = true # if true, will attempt to reuse simulations with the same parameters; otherwise run new simulations

        $(tersify("""
        # a monad refers to a single collection of identical simulations...
        # except for randomness (could be do to the initial seed or stochasticity introduced by omp threading)
        # n_replicates is the number of replicates to run for each parameter vector...
        # ...pcvct records which simulations all use the same parameter vector...
        # ...and will attempt to reuse these (unless the user opts out)...
        # ...so this parameter is the _min_ because there may already be many sims with the same parameters
        """))\
        n_replicates = 1

        ############ set up parameter variations ############

        $(tersify("""
        # assume you have the template project with \"default\" as a cell type...
        # ...let's vary their cycle durations and apoptosis rates
        
        # get the xml path to duration of phase 0 of the default cell type
        # this is a list of strings in which each string is either...
        # \t1) the name of a tag in the xml file OR
        # \t2) the name of a tag along with the value of one attribute (name:attribute_name:attribute_value)
        """))\
        xml_path = [pcvct.cyclePath(\"default\"); \"phase_durations\"; \"duration:index:0\"]
        vals = [200.0, 300.0, 400.0] # choose 3 discrete values to vary the duration of phase 0
        dv_phase_0_duration = DiscreteVariation(xml_path, vals)

        $(tersify("""
        # now do the same, but for the apoptosis rate
        """))\
        xml_path = [pcvct.apoptosisPath(\"default\"); \"death_rate\"]
        vals = [4.31667e-05, 5.31667e-05, 6.31667e-05] # choose 3 discrete values to vary the apoptosis rate
        dv_apoptosis_rate = DiscreteVariation(xml_path, vals)

        $(tersify("""
        # now combine them into a list:
        """))\
        discrete_variations = [dv_phase_0_duration, dv_apoptosis_rate]

        ############ run the sampling ############

        $(tersify("""
        # now create the sampling (varied parameter values) with these parameters
        # we will give it a reference to the monad with the short max time
        """))\
        sampling = createTrial(reference, discrete_variations; n_replicates=n_replicates)

        $(tersify("""
        # at this point, we have only added the sampling to the database...
        # ...along with the monads and simulations that make it up
        # now, we run the sampling
        """))\
        out = run(sampling; force_recompile=force_recompile)

        $(tersify("""
        # When running locally, pcvct using a shell environment variable to determine...
        # ...the number of concurrent siulations to run. This is set to 1 by default.
        # The variable is called PCVCT_NUM_PARALLEL_SIMS.
        # A simple way to set this when running the script is to run in your shell:
        # `PCVCT_NUM_PARALLEL_SIMS=4 julia $(path_to_generate_data)`
        """))\

        $(tersify("""
        # If you are running on an SLURM-based HPC, pcvct will detect this and calls to `sbatch`...
        # ...to parallelize the simulations, batching out each simulation to its own job.
        """))\
    """

    # Remove leading whitespace
    generate_data_lines = join(map(x -> lstrip(c->c==' ', x), split(generate_data_lines, '\n')), '\n')
    
    open(path_to_generate_data, "w") do f
        write(f, generate_data_lines)
    end
end