
"""
    loadCustomCode(S::AbstractSampling[; force_recompile::Bool=false])

Load and compile custom code for a simulation, monad, or sampling.

Determines if recompilation is necessary based on the previously used macros.
If compilation is required, copy the PhysiCell directory to a temporary directory to avoid conflicts.
Then, compile the project, recording the output and error in the `custom_codes` folder used.
Move the compiled executable into the `custom_codes` folder and the temporary PhysiCell folder deleted.
"""
function loadCustomCode(S::AbstractSampling; force_recompile::Bool=false)
    cflags, recompile, clean = compilerFlags(S)
    recompile = writePhysiCellCommitHash(S) || recompile # no matter what, write the PhysiCell version; if it is different, make sure to set recompile to true

    recompile |= force_recompile # if force_recompile is true, then recompile no matter what

    if !recompile
        return true
    end

    if clean
        cd(()->run(pipeline(`make clean`; stdout=devnull)), physicell_dir)
    end
    
    rand_suffix = randstring(10) # just to ensure that no two nodes try to compile at the same place at the same time
    temp_physicell_dir = joinpath(outputFolder(S), "temp_physicell_$(rand_suffix)")
    # copy the entire PhysiCell directory to a temporary directory to avoid conflicts with concurrent compilation
    cp(physicell_dir, temp_physicell_dir; force=true)

    temp_custom_modules_dir = joinpath(temp_physicell_dir, "custom_modules")
    if isdir(temp_custom_modules_dir)
        rm(temp_custom_modules_dir; force=true, recursive=true)
    end
    path_to_input_custom_codes = joinpath(data_dir, "inputs", "custom_codes", S.inputs.custom_code.folder)
    cp(joinpath(path_to_input_custom_codes, "custom_modules"), temp_custom_modules_dir; force=true)

    cp(joinpath(path_to_input_custom_codes, "main.cpp"), joinpath(temp_physicell_dir, "main.cpp"), force=true)
    cp(joinpath(path_to_input_custom_codes, "Makefile"), joinpath(temp_physicell_dir, "Makefile"), force=true)

    executable_name = baseToExecutable("project_ccid_$(S.inputs.custom_code.id)")
    cmd = `make -j 8 CC=$(PHYSICELL_CPP) PROGRAM_NAME=$(executable_name) CFLAGS=$(cflags)`
    # if Sys.isapple() # hacky way to say the -j flag works on my machine but not on the HPC
    #     cmd = `$cmd -j 20`
    # end

    println("Compiling custom code for $(S.inputs.custom_code.folder) with flags: $cflags")

    try
        cd(() -> run(pipeline(cmd; stdout=joinpath(path_to_input_custom_codes, "compilation.log"), stderr=joinpath(path_to_input_custom_codes, "compilation.err"))), temp_physicell_dir) # compile the custom code in the PhysiCell directory and return to the original directory
    catch e
        println("""
        Compilation failed. 
        Error: $e
        Check $(joinpath(path_to_input_custom_codes, "compilation.err")) for more information.
        """
        )
        rm(temp_physicell_dir; force=true, recursive=true)
        return false
    end
    
    # check if the error file is empty, if it is, delete it
    if filesize(joinpath(path_to_input_custom_codes, "compilation.err")) == 0
        rm(joinpath(path_to_input_custom_codes, "compilation.err"); force=true)
    else
        println("Compilation exited without error, but check $(joinpath(path_to_input_custom_codes, "compilation.err")) for warnings.")
    end

    mv(joinpath(temp_physicell_dir, executable_name), joinpath(path_to_input_custom_codes, baseToExecutable("project")), force=true)

    rm(temp_physicell_dir; force=true, recursive=true)
    return true
end

"""
    compilerFlags(S::AbstractSampling)

Generate the compiler flags for the given sampling object `S`.

Generate the necessary compiler flags based on the system and the macros defined in the sampling object `S`.
If the required macros differ from a previous compilation (as stored in macros.txt), then recompile.

# Returns
- `cflags::String`: The compiler flags as a string.
- `recompile::Bool`: A boolean indicating whether recompilation is needed.
- `clean::Bool`: A boolean indicating whether cleaning is needed.
"""
function compilerFlags(S::AbstractSampling)
    recompile = false # only recompile if need is found
    clean = false # only clean if need is found
    cflags = "-march=$(march_flag) -O3 -fomit-frame-pointer -fopenmp -m64 -std=c++11"
    if Sys.isapple()
        if strip(read(`uname -s`, String)) == "Darwin"
            cc_path = strip(read(`which $(PHYSICELL_CPP)`, String))
            var = strip(read(`file $cc_path`, String))
            add_mfpmath = split(var)[end] != "arm64"
        end
    else
        add_mfpmath = true
    end
    if add_mfpmath
        cflags *= " -mfpmath=both"
    end

    current_macros = readMacrosFile(S) # this will get all macros already in the macros file
    addMacrosIfNeeded(S)
    updated_macros = readMacrosFile(S) # this will get all macros already in the macros file

    if length(updated_macros) != length(current_macros)
        recompile = true
        clean = true
    end

    for macro_flag in updated_macros
        cflags *= " -D $(macro_flag)"
    end

    recompile = recompile || !executableExists(S.inputs.custom_code.folder) # last chance to recompile: do so if the executable does not exist

    return cflags, recompile, clean
end

function writePhysiCellCommitHash(S::AbstractSampling)
    path_to_commit_hash = joinpath(data_dir, "inputs", "custom_codes", S.inputs.custom_code.folder, "physicell_commit_hash.txt")
    physicell_commit_hash = physiCellCommitHash()
    current_commit_hash = ""
    if isfile(path_to_commit_hash)
        current_commit_hash = readchomp(path_to_commit_hash)
    end
    recompile = true
    if current_commit_hash != physicell_commit_hash
        open(path_to_commit_hash, "w") do f
            println(f, physicell_commit_hash)
        end
    elseif endswith(physicell_commit_hash, "-dirty")
        println("PhysiCell repo is dirty. Recompiling to be safe...")
    elseif endswith(physicell_commit_hash, "-download")
        println("PhysiCell repo is downloaded. Recompiling to be safe...")
    else
        recompile = false
    end
    return recompile
end

executableExists(custom_code_folder::String) = isfile(joinpath(data_dir, "inputs", "custom_codes", custom_code_folder, baseToExecutable("project")))

function addMacrosIfNeeded(S::AbstractSampling)
    # else get the macros neeeded
    addPhysiECMIfNeeded(S)

    # check others...
end

function addMacro(S::AbstractSampling, macro_name::String)
    path_to_macros = joinpath(data_dir, "inputs", "custom_codes", S.inputs.custom_code.folder, "macros.txt")
    open(path_to_macros, "a") do f
        println(f, macro_name)
    end
end

function addPhysiECMIfNeeded(S::AbstractSampling)
    if "ADDON_PHYSIECM" in readMacrosFile(S)
        # if the custom codes folder for the sampling already has the macro, then we don't need to do anything
        return
    end
    if S.inputs.ic_ecm.id != -1
        # if this sampling is providing an ic file for ecm, then we need to add the macro
        addMacro(S, "ADDON_PHYSIECM")
        return
    end
    # check if ecm_setup element has enabled="true" in config files
    loadConfiguration(S)
    if isPhysiECMInConfig(S)
        # if the base config file says that the ecm is enabled, then we need to add the macro
        addMacro(M, "ADDON_PHYSIECM")
    end
end

function isPhysiECMInConfig(M::AbstractMonad)
    path_to_xml = joinpath(data_dir, "inputs", "configs", M.inputs.config.folder, "config_variations", "config_variation_$(M.variation_ids.config).xml")
    xml_doc = openXML(path_to_xml)
    xml_path = ["microenvironment_setup", "ecm_setup"]
    ecm_setup_element = retrieveElement(xml_doc, xml_path; required=false)
    physi_ecm_in_config = !isnothing(ecm_setup_element) && attribute(ecm_setup_element, "enabled") == "true" # note: attribute returns nothing if the attribute does not exist
    closeXML(xml_doc)
    return physi_ecm_in_config
end

function isPhysiECMInConfig(sampling::Sampling)
    # otherwise, no previous sampling saying to use the macro, no ic file for ecm, and the base config file does not have ecm enabled,
    # now just check that the variation is not enabling the ecm
    for index in eachindex(sampling.variation_ids)
        monad = Monad(sampling, index) # instantiate a monad with the variation_id and the simulation ids already found
        if isPhysiECMInConfig(monad)
            return true
        end
    end
    return false
end

function readMacrosFile(S::AbstractSampling)
    path_to_macros = joinpath(data_dir, "inputs", "custom_codes", S.inputs.custom_code.folder, "macros.txt")
    if !isfile(path_to_macros)
        return []
    end
    return readlines(path_to_macros)
end