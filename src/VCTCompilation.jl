
"""
`loadCustomCode(S::AbstractSampling; force_recompile::Bool=false)`

Load and compile custom code for a given sampling instance.

# Arguments
- `S::AbstractSampling`: An instance of `AbstractSampling` containing the necessary folder names and IDs for custom code compilation.
- `force_recompile::Bool=false`: A boolean flag to force recompilation of the custom code regardless of the current state.

# Description
This function performs the following steps:
1. Retrieves compiler flags and determines if recompilation is necessary.
2. If recompilation is not required and `force_recompile` is false, the function returns immediately.
3. If recompilation is required, it optionally cleans the build directory.
4. Copies custom module files, `main.cpp`, and `Makefile` from the source directory to the target directory.
5. Compiles the custom code using the `make` command with appropriate flags.
6. Logs the compilation output and errors to specified files.
7. Deletes the error log file if it is empty.
8. Cleans up by removing copied files and restoring the default `Makefile`.
9. Moves the compiled project to the designated folder.

# Notes
- The function assumes the presence of specific directory structures and file names.
- On macOS, the `-j` flag is used to parallelize the compilation process.
- The function logs compilation output and errors to files in the source directory.
"""
function loadCustomCode(S::AbstractSampling; force_recompile::Bool=false)
    cflags, recompile, clean = getCompilerFlags(S)

    recompile |= force_recompile # if force_recompile is true, then recompile no matter what

    if !recompile
        return
    end

    if clean
        cd(()->run(pipeline(`make clean`; stdout=devnull)), physicell_dir)
    end

    path_to_folder = "$(data_dir)/inputs/custom_codes/$(S.folder_names.custom_code_folder)" # source dir needs to end in / or else the dir is copied into target, not the source files
    for file in readdir("$(path_to_folder)/custom_modules", sort=false)
        if !isfile("$(path_to_folder)/custom_modules/$(file)")
            continue
        end
        src = "$(path_to_folder)/custom_modules/$(file)"
        dst = "$(physicell_dir)/custom_modules/$(file)"
        cp(src, dst, force=true)
    end
    cp("$(path_to_folder)/main.cpp", "$(physicell_dir)/main.cpp", force=true)
    cp("$(path_to_folder)/Makefile", "$(physicell_dir)/Makefile", force=true)

    cmd = `make CC=$(PHYSICELL_CPP) PROGRAM_NAME=project_ccid_$(S.folder_ids.custom_code_id) CFLAGS=$(cflags)`
    if Sys.isapple() # hacky way to say the -j flag works on my machine but not on the HPC
        cmd = `$cmd -j 20`
    end

    println("Compiling custom code for $(S.folder_names.custom_code_folder) with flags: $cflags")

    cd(() -> run(pipeline(cmd; stdout="$(path_to_folder)/compilation.log", stderr="$(path_to_folder)/compilation.err")), physicell_dir) # compile the custom code in the PhysiCell directory and return to the original directory; make sure the macro ADDON_PHYSIECM is defined (should work even if multiply defined, e.g., by Makefile)
    
    # check if the error file is empty, if it is, delete it
    if filesize("$(path_to_folder)/compilation.err") == 0
        rm("$(path_to_folder)/compilation.err"; force=true)
    end

    rm("$(physicell_dir)/custom_modules/custom.cpp"; force=true)
    rm("$(physicell_dir)/custom_modules/custom.h"; force=true)
    rm("$(physicell_dir)/main.cpp"; force=true)
    run(`cp $(physicell_dir)/sample_projects/Makefile-default $(physicell_dir)/Makefile`)

    mv("$(physicell_dir)/project_ccid_$(S.folder_ids.custom_code_id)", "$(data_dir)/inputs/custom_codes/$(S.folder_names.custom_code_folder)/project", force=true)
    return 
end

"""
`getCompilerFlags(S::AbstractSampling) -> Tuple{String, Bool, Bool}`

Generate the compiler flags for the given sampling object `S`.

# Arguments
- `S::AbstractSampling`: The sampling object for which to generate compiler flags.

# Returns
- `cflags::String`: The compiler flags as a string.
- `recompile::Bool`: A boolean indicating whether recompilation is needed.
- `clean::Bool`: A boolean indicating whether cleaning is needed.

# Description
This function generates the necessary compiler flags based on the system and the macros defined in the sampling object `S`. It checks if the system is macOS and adjusts the flags accordingly. It also compares the current macros with the updated macros to determine if recompilation and cleaning are needed.

# Notes
- On macOS, it checks if the system architecture is `arm64` and adjusts the `-mfpmath` flag accordingly.
- It reads the current macros from a file and compares them with the updated macros to decide if recompilation and cleaning are necessary.
- If the project file does not exist in the specified directory, it sets `recompile` to `true`.
"""
function getCompilerFlags(S::AbstractSampling)
    recompile = false # only recompile if need is found
    clean = false # only clean if need is found
    cflags = "-march=native -O3 -fomit-frame-pointer -fopenmp -m64 -std=c++11"
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

    if !recompile && !isfile("$(data_dir)/inputs/custom_codes/$(S.folder_names.custom_code_folder)/project")
        recompile = true
    end

    return cflags, recompile, clean
end

function addMacrosIfNeeded(S::AbstractSampling)
    # else get the macros neeeded
    addPhysiECMIfNeeded(S)

    # check others...
end

function addMacro(S::AbstractSampling, macro_name::String)
    path_to_macros = "$(data_dir)/inputs/custom_codes/$(S.folder_names.custom_code_folder)/macros.txt"
    open(path_to_macros, "a") do f
        println(f, macro_name)
    end
end

function addPhysiECMIfNeeded(S::AbstractSampling)
    if "ADDON_PHYSIECM" in readMacrosFile(S)
        # if the custom codes folder for the sampling already has the macro, then we don't need to do anything
        return
    end
    if S.folder_ids.ic_ecm_id != -1
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
    path_to_xml = "$(data_dir)/inputs/configs/$(M.folder_names.config_folder)/variations/variation_$(M.variation_id).xml"
    xml_path = ["microenvironment_setup", "ecm_setup"]
    ecm_setup_element = retrieveElement(path_to_xml, xml_path; required=false)
    if !isnothing(ecm_setup_element) && attribute(ecm_setup_element, "enabled") == "true" # note: attribute returns nothing if the attribute does not exist
        return true
    end
    return false
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
    path_to_macros = "$(data_dir)/inputs/custom_codes/$(S.folder_names.custom_code_folder)/macros.txt"
    if !isfile(path_to_macros)
        return []
    end
    return readlines(path_to_macros)
end