var documenterSearchIndex = {"docs":
[{"location":"lib/VCTClasses/","page":"VCTClasses","title":"VCTClasses","text":"CollapsedDocStrings = true","category":"page"},{"location":"lib/VCTClasses/#VCTClasses","page":"VCTClasses","title":"VCTClasses","text":"","category":"section"},{"location":"lib/VCTClasses/","page":"VCTClasses","title":"VCTClasses","text":"This file contains the class definitions for the hierarchical structure connecting simulations to trials.","category":"page"},{"location":"lib/VCTClasses/","page":"VCTClasses","title":"VCTClasses","text":"Modules = [pcvct]\nPages = [\"VCTClasses.jl\"]","category":"page"},{"location":"lib/VCTClasses/#pcvct.AbstractSamplingFolders","page":"VCTClasses","title":"pcvct.AbstractSamplingFolders","text":"AbstractSamplingFolders\n\nA structure representing the folders used for sampling in a VCT (Virtual Cell Technology) environment.\n\nFields\n\nconfig_folder::String: Name of the configuration folder.\nrulesets_collection_folder::String: Name of the rulesets collection folder.\nic_cell_folder::String: Name of the initial condition (IC) cells folder.\nic_substrate_folder::String: Name of the initial condition (IC) substrate folder.\nic_ecm_folder::String: Name of the initial condition (IC) extracellular matrix (ECM) folder.\ncustom_code_folder::String: Name of the custom code folder.\n\n\n\n\n\n","category":"type"},{"location":"lib/VCTClasses/#pcvct.AbstractSamplingIDs","page":"VCTClasses","title":"pcvct.AbstractSamplingIDs","text":"struct AbstractSamplingIDs\n\nA struct representing various IDs used for sampling in the VCT environment.\n\nFields\n\nconfig_id::Int: Integer identifying the base configuration folder ID for lookup in the database.\nrulesets_collection_id::Int: Integer identifying which rulesets collection to use as a framework.\nic_cell_id::Int: Integer identifying the initial condition cells folder for lookup in the database.\nic_substrate_id::Int: Integer identifying the initial condition substrate folder for lookup in the database.\nic_ecm_id::Int: Integer identifying the initial condition extracellular matrix folder for lookup in the database.\ncustom_code_id::Int: Integer identifying the custom code folder (with {main.cpp, Makefile, custom_modules/{custom.cpp, custom.h}} as folder structure) for lookup in the database.\n\n\n\n\n\n","category":"type"},{"location":"lib/VCTCompilation/","page":"VCTCompilation","title":"VCTCompilation","text":"CollapsedDocStrings = true","category":"page"},{"location":"lib/VCTCompilation/#VCTCompilation","page":"VCTCompilation","title":"VCTCompilation","text":"","category":"section"},{"location":"lib/VCTCompilation/","page":"VCTCompilation","title":"VCTCompilation","text":"This file contains the functions used to compile a PhysiCell project, including using the necessary compiler macros.","category":"page"},{"location":"lib/VCTCompilation/","page":"VCTCompilation","title":"VCTCompilation","text":"Modules = [pcvct]\nPages = [\"VCTCompilation.jl\"]","category":"page"},{"location":"lib/VCTCompilation/#pcvct.getCompilerFlags-Tuple{pcvct.AbstractSampling}","page":"VCTCompilation","title":"pcvct.getCompilerFlags","text":"getCompilerFlags(S::AbstractSampling) -> Tuple{String, Bool, Bool}\n\nGenerate the compiler flags for the given sampling object S.\n\nArguments\n\nS::AbstractSampling: The sampling object for which to generate compiler flags.\n\nReturns\n\ncflags::String: The compiler flags as a string.\nrecompile::Bool: A boolean indicating whether recompilation is needed.\nclean::Bool: A boolean indicating whether cleaning is needed.\n\nDescription\n\nThis function generates the necessary compiler flags based on the system and the macros defined in the sampling object S. It checks if the system is macOS and adjusts the flags accordingly. It also compares the current macros with the updated macros to determine if recompilation and cleaning are needed.\n\nNotes\n\nOn macOS, it checks if the system architecture is arm64 and adjusts the -mfpmath flag accordingly.\nIt reads the current macros from a file and compares them with the updated macros to decide if recompilation and cleaning are necessary.\nIf the project file does not exist in the specified directory, it sets recompile to true.\n\n\n\n\n\n","category":"method"},{"location":"lib/VCTCompilation/#pcvct.loadCustomCode-Tuple{pcvct.AbstractSampling}","page":"VCTCompilation","title":"pcvct.loadCustomCode","text":"loadCustomCode(S::AbstractSampling; force_recompile::Bool=false)\n\nLoad and compile custom code for a given sampling instance.\n\nArguments\n\nS::AbstractSampling: An instance of AbstractSampling containing the necessary folder names and IDs for custom code compilation.\nforce_recompile::Bool=false: A boolean flag to force recompilation of the custom code regardless of the current state.\n\nDescription\n\nThis function performs the following steps:\n\nRetrieves compiler flags and determines if recompilation is necessary.\nIf recompilation is not required and force_recompile is false, the function returns immediately.\nIf recompilation is required, it optionally cleans the build directory.\nCopies custom module files, main.cpp, and Makefile from the source directory to the target directory.\nCompiles the custom code using the make command with appropriate flags.\nLogs the compilation output and errors to specified files.\nDeletes the error log file if it is empty.\nCleans up by removing copied files and restoring the default Makefile.\nMoves the compiled project to the designated folder.\n\nNotes\n\nThe function assumes the presence of specific directory structures and file names.\nOn macOS, the -j flag is used to parallelize the compilation process.\nThe function logs compilation output and errors to files in the source directory.\n\n\n\n\n\n","category":"method"},{"location":"man/guide/#Setting-up-your-project-repository","page":"Guide","title":"Setting up your project repository","text":"","category":"section"},{"location":"man/guide/","page":"Guide","title":"Guide","text":"To set up your pcvct-enabled repository within project-dir (the name of your project directory), create the following directory structure:","category":"page"},{"location":"man/guide/","page":"Guide","title":"Guide","text":"project-dir/\n├── data/\n│   └── inputs/\n│       ├── configs/\n│       ├── custom_codes/\n│       ├── ics/\n│       │   ├── cells/\n│       │   ├── ecms/\n│       │   └── substrates/\n│       ├── rulesets_collections/\n└── VCT/","category":"page"},{"location":"man/guide/#Setting-up-the-inputs-directory","page":"Guide","title":"Setting up the inputs directory","text":"","category":"section"},{"location":"man/guide/","page":"Guide","title":"Guide","text":"Within each of the terminal subdirectories above within data/inputs/, add a subdirectory with a user-defined name with content described below. We will use the name \"default\" for all as an example.","category":"page"},{"location":"man/guide/#Configs","page":"Guide","title":"Configs","text":"","category":"section"},{"location":"man/guide/","page":"Guide","title":"Guide","text":"Add a single file within data/inputs/configs/default/ called PhysiCell_settings.xml with the base configuration file for your PhysiCell project.","category":"page"},{"location":"man/guide/#Custom-codes","page":"Guide","title":"Custom codes","text":"","category":"section"},{"location":"man/guide/","page":"Guide","title":"Guide","text":"Add within data/inputs/custom_codes/default/ the following, each exactly as is used in a PhysiCell project:","category":"page"},{"location":"man/guide/","page":"Guide","title":"Guide","text":"main.cpp\nMakefile\ncustom_modules/","category":"page"},{"location":"man/guide/#ICs","page":"Guide","title":"ICs","text":"","category":"section"},{"location":"man/guide/","page":"Guide","title":"Guide","text":"These folders are optional as not every model includes initial conditions as separate files. If your model does, for each initial condition add a subfolder. For example, if you have two initial cell position conditions, random_cells.csv and structured_cells.csv, the data/inputs/ics/cells/ directory would look like this:","category":"page"},{"location":"man/guide/","page":"Guide","title":"Guide","text":"cells/\n├── random_cells/\n│   └── cells.csv\n└── structured_cells/\n    └── cells.csv","category":"page"},{"location":"man/guide/","page":"Guide","title":"Guide","text":"Note: Place the files in their corresponding folders and rename to cells.csv.","category":"page"},{"location":"man/guide/","page":"Guide","title":"Guide","text":"Proceed similarly for ecms/ and substrates/, renaming those files to ecm.csv and substrates.csv respectively.","category":"page"},{"location":"man/guide/#Rulesets-collections","page":"Guide","title":"Rulesets collections","text":"","category":"section"},{"location":"man/guide/","page":"Guide","title":"Guide","text":"Add a single file within data/inputs/rulesets_collections/default/ called base_rulesets.csv with the base ruleset collection for your PhysiCell project. If your project does not use rules, you can skip this step.","category":"page"},{"location":"","page":"Home","title":"Home","text":"CurrentModule = pcvct","category":"page"},{"location":"#pcvct","page":"Home","title":"pcvct","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"Documentation for pcvct.","category":"page"},{"location":"","page":"Home","title":"Home","text":"","category":"page"},{"location":"lib/VCTModule/","page":"VCTModule","title":"VCTModule","text":"CollapsedDocStrings = true","category":"page"},{"location":"lib/VCTModule/#VCTModule","page":"VCTModule","title":"VCTModule","text":"","category":"section"},{"location":"lib/VCTModule/","page":"VCTModule","title":"VCTModule","text":"This file holds some core functionality for pcvct.","category":"page"},{"location":"lib/VCTModule/","page":"VCTModule","title":"VCTModule","text":"Modules = [pcvct]\nPages = [\"VCTModule.jl\"]","category":"page"},{"location":"lib/VCTModule/#pcvct.constituentsType-Tuple{Trial}","page":"VCTModule","title":"pcvct.constituentsType","text":"constituentsType(T::AbstractTrial) -> Type\n\nReturns the type of constituents for a given AbstractTrial.\n\nArguments\n\nT::AbstractTrial: An AbstractTrial object.\n\nReturns\n\nType: The type of constituents.\n\n\n\n\n\n","category":"method"},{"location":"lib/VCTModule/#pcvct.initializeVCT-Tuple{String, String}","page":"VCTModule","title":"pcvct.initializeVCT","text":"initializeVCT(path_to_physicell::String, path_to_data::String)\n\nInitializes the VCT environment by setting the paths to PhysiCell and data directories, and initializing the database.\n\nArguments\n\npath_to_physicell::String: Path to the PhysiCell directory.\npath_to_data::String: Path to the data directory.\n\n\n\n\n\n","category":"method"},{"location":"lib/VCTModule/#pcvct.pcvctLogo-Tuple{}","page":"VCTModule","title":"pcvct.pcvctLogo","text":"pcvctLogo() -> String\n\nReturns a string representation of the PCVCT logo.\n\n\n\n\n\n","category":"method"},{"location":"lib/VCTModule/#pcvct.readConstituentIDs-Tuple{String}","page":"VCTModule","title":"pcvct.readConstituentIDs","text":"readConstituentIDs(path_to_csv::String) -> Vector{Int}\n\nReads constituent IDs from a CSV file.\n\nArguments\n\npath_to_csv::String: Path to the CSV file.\n\nReturns\n\nVector{Int}: A vector of constituent IDs.\n\n\n\n\n\n","category":"method"},{"location":"lib/VCTModule/#pcvct.readConstituentIDs-Tuple{pcvct.AbstractTrial}","page":"VCTModule","title":"pcvct.readConstituentIDs","text":"readConstituentIDs(T::AbstractTrial)\n\nReads the constituent IDs for a given trial type T.\n\nArguments\n\nT::AbstractTrial: An instance of a trial type.\n\nReturns\n\nA list of constituent IDs read from a CSV file.\n\nDetails\n\nThe function constructs a file path based on the type and ID of the trial T.  It then reads the constituent IDs from a CSV file located at the constructed path.\n\n\n\n\n\n","category":"method"}]
}
