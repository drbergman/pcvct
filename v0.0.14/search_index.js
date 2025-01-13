var documenterSearchIndex = {"docs":
[{"location":"lib/VCTHPC/","page":"VCTHPC","title":"VCTHPC","text":"CollapsedDocStrings = true","category":"page"},{"location":"lib/VCTHPC/#VCTHPC","page":"VCTHPC","title":"VCTHPC","text":"","category":"section"},{"location":"lib/VCTHPC/","page":"VCTHPC","title":"VCTHPC","text":"Run pcvct on an HPC.","category":"page"},{"location":"lib/VCTHPC/","page":"VCTHPC","title":"VCTHPC","text":"Modules = [pcvct]\nPages = [\"VCTHPC.jl\"]","category":"page"},{"location":"lib/VCTHPC/#pcvct.defaultJobOptions-Tuple{}","page":"VCTHPC","title":"pcvct.defaultJobOptions","text":"defaultJobOptions()\n\nReturn a dictionary with default options for a job script for use with SLURM.\n\n\n\n\n\n","category":"method"},{"location":"lib/VCTHPC/#pcvct.isRunningOnHPC-Tuple{}","page":"VCTHPC","title":"pcvct.isRunningOnHPC","text":"isRunningOnHPC()\n\nReturn true if the current environment is an HPC environment, false otherwise.\n\nCurrently, this function checks if the sbatch command is available, indicating a SLURM environment.\n\n\n\n\n\n","category":"method"},{"location":"lib/VCTHPC/#pcvct.setJobOptions-Tuple{Dict}","page":"VCTHPC","title":"pcvct.setJobOptions","text":"setJobOptions(options::Dict)\n\nSet the default job options for use with SLURM.\n\nFor any key-value pair in options, the corresponding key in the global sbatch_options dictionary is set to the value. A flag is then added to the sbatch command for each key-value pair in options: --key=value.\n\n\n\n\n\n","category":"method"},{"location":"lib/VCTHPC/#pcvct.useHPC","page":"VCTHPC","title":"pcvct.useHPC","text":"useHPC([use::Bool=true])\n\nSet the global variable run_on_hpc to use.\n\n\n\n\n\n","category":"function"},{"location":"lib/VCTExport/","page":"VCTExport","title":"VCTExport","text":"CollapsedDocStrings = true","category":"page"},{"location":"lib/VCTExport/#VCTExport","page":"VCTExport","title":"VCTExport","text":"","category":"section"},{"location":"lib/VCTExport/","page":"VCTExport","title":"VCTExport","text":"This file holds the functions for exporting a simulation to a user_project format.","category":"page"},{"location":"lib/VCTExport/","page":"VCTExport","title":"VCTExport","text":"Modules = [pcvct]\nPages = [\"VCTExport.jl\"]","category":"page"},{"location":"lib/VCTExport/#pcvct.exportSimulation","page":"VCTExport","title":"pcvct.exportSimulation","text":"exportSimulation(simulation_id::Integer[, export_folder::AbstractString])\nexportSimulation(simulation::Simulation[, export_folder::AbstractString])\n\nCreate a user_project folder from a simulation that can be loaded into PhysiCell.\n\nWarning: not all features in drbergman/PhysiCell/latest/release are not supported in MathCancer/PhysiCell.\n\nArguments\n\nsimulation_id::Integer: the id of the simulation to export\nsimulation::Simulation: the simulation to export\nexport_folder::AbstractString: the folder to export the simulation to. Default is the simulation output folder.\n\n\n\n\n\n","category":"function"},{"location":"lib/VCTRunner/","page":"VCTRunner","title":"VCTRunner","text":"CollapsedDocStrings = true","category":"page"},{"location":"lib/VCTRunner/#VCTRunner","page":"VCTRunner","title":"VCTRunner","text":"","category":"section"},{"location":"lib/VCTRunner/","page":"VCTRunner","title":"VCTRunner","text":"Run simulations, monads, samplings, and trials in the pcvct framework.","category":"page"},{"location":"lib/VCTRunner/","page":"VCTRunner","title":"VCTRunner","text":"Modules = [pcvct]\nPages = [\"VCTRunner.jl\"]","category":"page"},{"location":"lib/VCTRunner/#Base.run-Tuple{pcvct.AbstractTrial}","page":"VCTRunner","title":"Base.run","text":"run(T::AbstractTrial[; force_recompile::Bool=false, prune_options::PruneOptions=PruneOptions()])`\n\nRun the given simulation, monad, sampling, or trial.\n\nCall the appropriate functions to run the simulations and return the number of successful simulations. Also print out messages to the console to inform the user about the progress and results of the simulations.\n\nArguments\n\nT::AbstractTrial: The trial, sampling, monad, or simulation to run.\nforce_recompile::Bool=false: If true, forces a recompilation of all files by removing all .o files in the PhysiCell directory.\nprune_options::PruneOptions=PruneOptions(): Options for pruning simulations.\n\n\n\n\n\n","category":"method"},{"location":"lib/VCTRunner/#pcvct.collectSimulationTasks-Tuple{pcvct.AbstractTrial}","page":"VCTRunner","title":"pcvct.collectSimulationTasks","text":"collectSimulationTasks(T::AbstractTrial[; force_recompile::Bool=false, prune_options::PruneOptions=PruneOptions()])\n\nCollect the simulation tasks for the given trial, sampling, monad, or simulation.\n\nUsed by run to collect the tasks to run.\n\nSee also run.\n\n\n\n\n\n","category":"method"},{"location":"lib/VCTRunner/#pcvct.runAbstractTrial-Tuple{pcvct.AbstractTrial}","page":"VCTRunner","title":"pcvct.runAbstractTrial","text":"runAbstractTrial(T::AbstractTrial; force_recompile::Bool=false, prune_options::PruneOptions=PruneOptions())\n\nAlias for run.\n\n\n\n\n\n","category":"method"},{"location":"man/guide/#Setting-up-your-project-repository","page":"Guide","title":"Setting up your project repository","text":"","category":"section"},{"location":"man/guide/","page":"Guide","title":"Guide","text":"To set up your pcvct-enabled repository within project-dir (the name of your project directory), create the following directory structure:","category":"page"},{"location":"man/guide/","page":"Guide","title":"Guide","text":"project-dir/\n├── data/\n│   └── inputs/\n│       ├── configs/\n│       ├── custom_codes/\n│       ├── ics/\n│       │   ├── cells/\n│       │   ├── ecms/\n│       │   └── substrates/\n│       ├── rulesets_collections/\n└── VCT/","category":"page"},{"location":"man/guide/#Setting-up-the-inputs-directory","page":"Guide","title":"Setting up the inputs directory","text":"","category":"section"},{"location":"man/guide/","page":"Guide","title":"Guide","text":"Within each of the terminal subdirectories above within data/inputs/, add a subdirectory with a user-defined name with content described below. We will use the name \"default\" for all as an example.","category":"page"},{"location":"man/guide/#Configs","page":"Guide","title":"Configs","text":"","category":"section"},{"location":"man/guide/","page":"Guide","title":"Guide","text":"Add a single file within data/inputs/configs/default/ called PhysiCell_settings.xml with the base configuration file for your PhysiCell project.","category":"page"},{"location":"man/guide/#Custom-codes","page":"Guide","title":"Custom codes","text":"","category":"section"},{"location":"man/guide/","page":"Guide","title":"Guide","text":"Add within data/inputs/custom_codes/default/ the following, each exactly as is used in a PhysiCell project:","category":"page"},{"location":"man/guide/","page":"Guide","title":"Guide","text":"main.cpp\nMakefile\ncustom_modules/","category":"page"},{"location":"man/guide/#ICs","page":"Guide","title":"ICs","text":"","category":"section"},{"location":"man/guide/","page":"Guide","title":"Guide","text":"These folders are optional as not every model includes initial conditions as separate files. If your model does, for each initial condition add a subfolder. For example, if you have two initial cell position conditions, random_cells.csv and structured_cells.csv, the data/inputs/ics/cells/ directory would look like this:","category":"page"},{"location":"man/guide/","page":"Guide","title":"Guide","text":"cells/\n├── random_cells/\n│   └── cells.csv\n└── structured_cells/\n    └── cells.csv","category":"page"},{"location":"man/guide/","page":"Guide","title":"Guide","text":"Note: Place the files in their corresponding folders and rename to cells.csv.","category":"page"},{"location":"man/guide/","page":"Guide","title":"Guide","text":"Proceed similarly for ecms/ and substrates/, renaming those files to ecm.csv and substrates.csv respectively.","category":"page"},{"location":"man/guide/#Rulesets-collections","page":"Guide","title":"Rulesets collections","text":"","category":"section"},{"location":"man/guide/","page":"Guide","title":"Guide","text":"Add a single file within data/inputs/rulesets_collections/default/ called base_rulesets.csv with the base ruleset collection for your PhysiCell project. If your project does not use rules, you can skip this step.","category":"page"},{"location":"lib/VCTImport/","page":"VCTImport","title":"VCTImport","text":"CollapsedDocStrings = true","category":"page"},{"location":"lib/VCTImport/#VCTImport","page":"VCTImport","title":"VCTImport","text":"","category":"section"},{"location":"lib/VCTImport/","page":"VCTImport","title":"VCTImport","text":"Import a project from the standard PhysiCell format into the pcvct format.","category":"page"},{"location":"lib/VCTImport/","page":"VCTImport","title":"VCTImport","text":"Modules = [pcvct]\nPages = [\"VCTImport.jl\"]","category":"page"},{"location":"lib/VCTImport/#pcvct.importProject","page":"VCTImport","title":"pcvct.importProject","text":"importProject(path_to_project::AbstractString[, src=Dict(), dest=Dict(); extreme_caution::Bool=false])\n\nImport a project from the structured in the format of PhysiCell sample projects and user projects into the pcvct structure.\n\nArguments\n\npath_to_project::AbstractString: Path to the project to import. Relative paths are resolved from the current working directory where Julia was launched.\nsrc::Dict: Dictionary of the project sources to import. If absent, tries to use the default names.\n\nThe following keys are recognized: config, main, makefile, custom_modules, rulesets_collection, ic_cell, ic_substrate, and ic_ecm.\n\ndest::Dict: Dictionary of the inputs folders to create in the pcvct structure. If absent, taken from the project name.\n\nThe following keys are recognized: config, custom_code, rules, ic_cell, ic_substrate, and ic_ecm.\n\nextreme_caution::Bool: If true, will ask for confirmation before deleting any folders created during the import process. Care has been taken to ensure this is unnecessary.\n\nThis option is provided for users who want to be extra cautious.\n\n\n\n\n\n","category":"function"},{"location":"lib/VCTCreation/","page":"VCTCreation","title":"VCTCreation","text":"CollapsedDocStrings = true","category":"page"},{"location":"lib/VCTCreation/#VCTCreation","page":"VCTCreation","title":"VCTCreation","text":"","category":"section"},{"location":"lib/VCTCreation/","page":"VCTCreation","title":"VCTCreation","text":"Create a new pcvct project.","category":"page"},{"location":"lib/VCTCreation/","page":"VCTCreation","title":"VCTCreation","text":"Modules = [pcvct]\nPages = [\"VCTCreation.jl\"]","category":"page"},{"location":"lib/VCTCreation/#pcvct.createProject","page":"VCTCreation","title":"pcvct.createProject","text":"createProject(project_dir::String=\".\"; clone_physicell::Bool=true, template_as_default::Bool=true, terse::Bool=false)\n\nCreate a new pcvct project structure.\n\nCreates a new project directory at project_dir with the following structure:\n\nproject_dir\n├── data\n├── PhysiCell # The latest release from https://github.com/drbergman/PhysiCell\n└── VCT\n\ndata is populated with the standard structure. PhysiCell is a copy of PhysiCell. VCT contains a generated GenerateData.jl file.\n\nArguments\n\nproject_dir::String=\".\": The directory in which to create the project. Relative paths are resolved from the current working directory where Julia was launched.\nclone_physicell::Bool=true: Whether to clone the PhysiCell repository. If false, the latest release will be downloaded. Recommended to set to true so pcvct will be able to track changes to the PhysiCell repository.\ntemplate_as_default::Bool=true: Whether to set up the project with the template files as the default. If false, the project will be set up with an empty structure.\nterse::Bool=false: Whether to generate a terse GenerateData.jl file. If true, the file will be generated without comments and explanations.\n\nNote\n\nThe names of the data and PhysiCell directories are fixed and cannot be changed. Their relative locations should not be changed without updating the GenerateData.jl file. The name of the VCT file and the GenerateData.jl are just by convention and can be changed.\n\n\n\n\n\n","category":"function"},{"location":"lib/VCTVariations/","page":"VCTVariations","title":"VCTVariations","text":"CollapsedDocStrings = true","category":"page"},{"location":"lib/VCTVariations/#VCTVariations","page":"VCTVariations","title":"VCTVariations","text":"","category":"section"},{"location":"lib/VCTVariations/","page":"VCTVariations","title":"VCTVariations","text":"Vary parameters of the project.","category":"page"},{"location":"lib/VCTVariations/","page":"VCTVariations","title":"VCTVariations","text":"Modules = [pcvct]\nPages = [\"VCTVariations.jl\"]","category":"page"},{"location":"lib/VCTVariations/#pcvct.DiscreteVariation","page":"VCTVariations","title":"pcvct.DiscreteVariation","text":"DiscreteVariation{T}(xml_path::Vector{<:AbstractString}, values::Vector{T}) where T\n\nCreate a DiscreteVariation object with the given xml_path and values.\n\nThe type T is inferred from the type of the values argument. A singleton value can be passed in place of values for convenience.\n\nExamples\n\njulia> dv = DiscreteVariation([\"overall\",\"max_time\"], [1440.0, 2880.0])\nDiscreteVariation{Float64}(:config, [\"overall\", \"max_time\"], [1440.0, 2880.0])\n\njulia> dv = DiscreteVariation([\"overall\",\"max_time\"], 1440)\nDiscreteVariation{Int64}(:config, [\"overall\", \"max_time\"], [1440])\n\n\n\n\n\n","category":"type"},{"location":"lib/VCTDeletion/","page":"VCTDeletion","title":"VCTDeletion","text":"CollapsedDocStrings = true","category":"page"},{"location":"lib/VCTDeletion/#VCTDeletion","page":"VCTDeletion","title":"VCTDeletion","text":"","category":"section"},{"location":"lib/VCTDeletion/","page":"VCTDeletion","title":"VCTDeletion","text":"Safely delete output from a pcvct project.","category":"page"},{"location":"lib/VCTDeletion/","page":"VCTDeletion","title":"VCTDeletion","text":"Modules = [pcvct]\nPages = [\"VCTDeletion.jl\"]","category":"page"},{"location":"lib/VCTDeletion/#pcvct.deleteSimulationsByStatus","page":"VCTDeletion","title":"pcvct.deleteSimulationsByStatus","text":"deleteSimulationsByStatus(status_codes_to_delete::Vector{String}=[\"Failed\"]; user_check::Bool=true)\n\nDelete simulations from the database based on their status codes.\n\nThe list of possible status codes is: \"Not Started\", \"Queued\", \"Running\", \"Completed\", \"Failed\".\n\nArguments\n\nstatus_codes_to_delete::Vector{String}: A vector of status codes for which simulations should be deleted. Default is [\"Failed\"].\nuser_check::Bool: If true, prompts the user for confirmation before deleting simulations. Default is true.\n\n\n\n\n\n","category":"function"},{"location":"lib/VCTDeletion/#pcvct.eraseSimulationID-Tuple{Int64}","page":"VCTDeletion","title":"pcvct.eraseSimulationID","text":"eraseSimulationID(simulation_id::Int[; monad_id::Union{Missing,Int}=missing])\n\nErase a simulation ID from the monad it belongs to simulations.csv.\n\nIf monad_id is not provided, the function will infer it from the simulation ID. If the monad contains only the given simulation ID, the monad will be deleted.\n\n\n\n\n\n","category":"method"},{"location":"lib/VCTAnalysis/","page":"VCTAnalysis","title":"VCTAnalysis","text":"CollapsedDocStrings = true","category":"page"},{"location":"lib/VCTAnalysis/#VCTAnalysis","page":"VCTAnalysis","title":"VCTAnalysis","text":"","category":"section"},{"location":"lib/VCTAnalysis/","page":"VCTAnalysis","title":"VCTAnalysis","text":"Analyze output from a pcvct project.","category":"page"},{"location":"lib/VCTAnalysis/","page":"VCTAnalysis","title":"VCTAnalysis","text":"Modules = [pcvct]\nPages = [\"population.jl\", \"substrate.jl\"]","category":"page"},{"location":"lib/VCTAnalysis/#pcvct.plotbycelltype","page":"VCTAnalysis","title":"pcvct.plotbycelltype","text":"plotbycelltype(T::AbstractTrial, cell_types::Union{String, Vector{String}}=:all)\n\nPlot the population time series of a trial by cell type.\n\nEach cell type gets its own subplot. Each monad gets its own series within each subplot.\n\n\n\n\n\n","category":"function"},{"location":"lib/VCTDatabase/","page":"VCTDatabase","title":"VCTDatabase","text":"CollapsedDocStrings = true","category":"page"},{"location":"lib/VCTDatabase/#VCTDatabase","page":"VCTDatabase","title":"VCTDatabase","text":"","category":"section"},{"location":"lib/VCTDatabase/","page":"VCTDatabase","title":"VCTDatabase","text":"Create and manage the pcvct database.","category":"page"},{"location":"lib/VCTDatabase/","page":"VCTDatabase","title":"VCTDatabase","text":"Modules = [pcvct]\nPages = [\"VCTDatabase.jl\"]","category":"page"},{"location":"lib/VCTDatabase/#pcvct.isStarted-Tuple{Int64}","page":"VCTDatabase","title":"pcvct.isStarted","text":"isStarted(simulation_id::Int[; new_status_code::Union{Missing,String}=missing])\n\nCheck if a simulation has been started.\n\nIf new_status_code is provided, update the status of the simulation to this value. The check and status update are done in a transaction to ensure that the status is not changed by another process.\n\n\n\n\n\n","category":"method"},{"location":"lib/VCTClasses/","page":"VCTClasses","title":"VCTClasses","text":"CollapsedDocStrings = true","category":"page"},{"location":"lib/VCTClasses/#VCTClasses","page":"VCTClasses","title":"VCTClasses","text":"","category":"section"},{"location":"lib/VCTClasses/","page":"VCTClasses","title":"VCTClasses","text":"Class definitions for the hierarchical structure connecting simulations to trials.","category":"page"},{"location":"lib/VCTClasses/","page":"VCTClasses","title":"VCTClasses","text":"Modules = [pcvct]\nPages = [\"VCTClasses.jl\"]","category":"page"},{"location":"lib/VCTClasses/#pcvct.InputFolders","page":"VCTClasses","title":"pcvct.InputFolders","text":"struct InputFolders\n\nConsolidate the folder information for a simulation/monad/sampling.\n\nPass the folder names within the inputs/<input_type> directory to create an InputFolders object. Pass them in the order of config, custom_code, rulesets_collection, ic_cell, ic_substrate, and ic_ecm. Or use the keyword-based constructors:\n\nInputFolders(config, custom_code; rulesets_collection=\"\", ic_cell=\"\", ic_substrate=\"\", ic_ecm=\"\") InputFolders(; config=\"\", custom_code=\"\", rulesets_collection=\"\", ic_cell=\"\", ic_substrate=\"\", ic_ecm=\"\")\n\nFields\n\nconfig::InputFolder: id and folder name for the base configuration folder.\ncustom_code::InputFolder: id and folder name for the custom code folder.\nrulesets_collection::InputFolder: id and folder name for the rulesets collection folder.\nic_cell::InputFolder: id and folder name for the initial condition (IC) cells folder.\nic_substrate::InputFolder: id and folder name for the initial condition (IC) substrate folder.\nic_ecm::InputFolder: id and folder name for the initial condition (IC) extracellular matrix (ECM) folder.\n\n\n\n\n\n","category":"type"},{"location":"lib/VCTCompilation/","page":"VCTCompilation","title":"VCTCompilation","text":"CollapsedDocStrings = true","category":"page"},{"location":"lib/VCTCompilation/#VCTCompilation","page":"VCTCompilation","title":"VCTCompilation","text":"","category":"section"},{"location":"lib/VCTCompilation/","page":"VCTCompilation","title":"VCTCompilation","text":"Compile a PhysiCell project in pcvct. Includes the necessary compiler macros and checks PhysiCell version by the commit hash of the PhysiCell repository.","category":"page"},{"location":"lib/VCTCompilation/","page":"VCTCompilation","title":"VCTCompilation","text":"Modules = [pcvct]\nPages = [\"VCTCompilation.jl\"]","category":"page"},{"location":"lib/VCTCompilation/#pcvct.compilerFlags-Tuple{pcvct.AbstractSampling}","page":"VCTCompilation","title":"pcvct.compilerFlags","text":"compilerFlags(S::AbstractSampling)\n\nGenerate the compiler flags for the given sampling object S.\n\nGenerate the necessary compiler flags based on the system and the macros defined in the sampling object S. If the required macros differ from a previous compilation (as stored in macros.txt), then recompile.\n\nReturns\n\ncflags::String: The compiler flags as a string.\nrecompile::Bool: A boolean indicating whether recompilation is needed.\nclean::Bool: A boolean indicating whether cleaning is needed.\n\n\n\n\n\n","category":"method"},{"location":"lib/VCTCompilation/#pcvct.loadCustomCode-Tuple{pcvct.AbstractSampling}","page":"VCTCompilation","title":"pcvct.loadCustomCode","text":"loadCustomCode(S::AbstractSampling[; force_recompile::Bool=false])\n\nLoad and compile custom code for a given Sampling instance.\n\nDetermines if recompilation is necessary based on the previously used macros. If compilation is required, copy the PhysiCell directory to a temporary directory to avoid conflicts. Then, compile the project, recording the output and error in the custom_codes folder used. Move the compiled executable into the custom_codes folder and the temporary PhysiCell folder deleted.\n\n\n\n\n\n","category":"method"},{"location":"","page":"Home","title":"Home","text":"CurrentModule = pcvct","category":"page"},{"location":"#pcvct","page":"Home","title":"pcvct","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"Documentation for pcvct.","category":"page"},{"location":"","page":"Home","title":"Home","text":"","category":"page"},{"location":"lib/VCTModule/","page":"VCTModule","title":"VCTModule","text":"CollapsedDocStrings = true","category":"page"},{"location":"lib/VCTModule/#VCTModule","page":"VCTModule","title":"VCTModule","text":"","category":"section"},{"location":"lib/VCTModule/","page":"VCTModule","title":"VCTModule","text":"Core functionality for pcvct.","category":"page"},{"location":"lib/VCTModule/","page":"VCTModule","title":"VCTModule","text":"Modules = [pcvct]\nPages = [\"VCTModule.jl\"]","category":"page"},{"location":"lib/VCTModule/#pcvct.initializeVCT-Tuple{String, String}","page":"VCTModule","title":"pcvct.initializeVCT","text":"initializeVCT(path_to_physicell::String, path_to_data::String)\n\nInitialize the VCT environment by setting the paths to PhysiCell and data directories, and initializing the database.\n\nArguments\n\npath_to_physicell::String: Path to the PhysiCell directory as either an absolute or relative path.\npath_to_data::String: Path to the data directory as either an absolute or relative path.\n\n\n\n\n\n","category":"method"},{"location":"lib/VCTModule/#pcvct.pcvctLogo-Tuple{}","page":"VCTModule","title":"pcvct.pcvctLogo","text":"pcvctLogo()\n\nReturn a string representation of the awesome pcvct logo.\n\n\n\n\n\n","category":"method"}]
}