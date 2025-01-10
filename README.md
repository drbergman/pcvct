# pcvct

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://drbergman.github.io/pcvct/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://drbergman.github.io/pcvct/dev/)
[![Build Status](https://github.com/drbergman/pcvct/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/drbergman/pcvct/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/drbergman/pcvct/branch/main/graph/badge.svg)](https://codecov.io/gh/drbergman/pcvct)

Check out [Getting started](#getting-started) for a quick guide to using pcvct.
Make sure you are familiar with the [Best practices](#best-practices) section before using pcvct.

# Getting started
1. Download julia (see [here](https://julialang.org/downloads/) for more options):
```
curl -fsSL https://install.julialang.org | sh
```
Note: this command also installs the [JuliaUp](https://github.com/JuliaLang/juliaup) installation manager, which will automatically install julia and help keep it up to date.

2. Add the PCVCTRegistry:
Launch julia by running `julia` in a shell.
Then, enter the Pkg REPL by pressing `]`.
Finally, add the PCVCTRegistry by running:
```
registry add https://github.com/drbergman/PCVCTRegistry
```

3. Install pcvct:
Still in the Pkg REPL, run:
```
add pcvct
```

4. Create a pcvct-enabled project:
Leave the Pkg REPL by pressing `backspace`.
Load the pcvct module by running:
```
using pcvct
```
Then, create a new project by running:
```
createProject(path_to_project_folder) # createProject() will use the current directory as the project folder
```
This creates three folders inside the `path_to_project_folder` folder: `data/`, `PhysiCell/`, and `VCT/`.
<!-- The `data/` folder will currently contain the PhysiCell template project split across multiple folders within `data/inputs/`.
After initializing the project, a `data/vct.db` database will be created to store metadata about the project and its simulations. -->

## Importing from `user_projects`
If you have a project in the `PhysiCell/user_projects/` folder that you would like to import, you can do so by running:
```
importProject(path_to_project_folder)
```
Note: This function assumes your project files are in the standard `PhysiCell/user_projects/` format. In particular, it assumes that...
- The config file is `PhysiCell/user_projects/[project_name]/config/PhysiCell_settings.xml`
- The `main.cpp` file is `PhysiCell/user_projects/[project_name]/main.cpp`
- The `Makefile` is `PhysiCell/user_projects/[project_name]/Makefile`
- The custom modules are in `PhysiCell/user_projects/[project_name]/custom_modules/`
- (if used) The rules file is `PhysiCell/user_projects/[project_name]/config/cell_rules.csv`
- (if used) The cell initial conditions are in `PhysiCell/user_projects/[project_name]/config/cells.csv` 
- (if used) the substrate initial conditions are in `PhysiCell/user_projects/[project_name]/config/substrates.csv`
If any of these files are not located in the standard location, you can define a dictionary with keys from {`config`, ` main`, `makefile`, `custom_modules`, `rules`, `ic_cell`, `ic_substrate`} to specify the location of each file.
Put the path relative to the project folder. For example, if the config file is instead located at `PhysiCell/user_projects/[project_name]/config/config.xml`, you would run:
```
src = Dict("config" => "config/config.xml")
```
Additional entries can be added in a comma-separated list into `Dict` or added later with `src[key] = rel_path`.

## Running first trial
The `createProject()` command creates three folder, including a `VCT` folder with a single file: `VCT/GenerateData.jl`.
The name of this folder and this file are purely convention, change them as you like.
To run your first pcvct trial, you can run the GenerateData.jl script from the shell:
```
julia VCT/GenerateData.jl
```
Note: if you want to parallelize these 9 runs, you can set the shell environment variable `PCVCT_NUM_PARALLEL_SIMS` to the number of parallel simulations you want to run. For example, to run 9 parallel simulations, you would run:
```
export PCVCT_NUM_PARALLEL_SIMS=9
julia VCT/GenerateData.jl
```
Or for a one-off solution:
```
PCVCT_NUM_PARALLEL_SIMS=9 julia VCT/GenerateData.jl
```
Alternatively, you can run the script via the REPL.

Run the script a second time and observe that no new simulations are run.
This is because pcvct looks for matching simulations first before running new ones.
The `use_previous` optional keyword argument can control this behavior if new simulations are desired.

## Using PhysiCell Studio
If you want to use PhysiCell Studio to visualize the output of your simulations, first launch julia.
Then, make sure the project is initialized by running:
```
# if you used createProject(), these are the first two lines of GenerateData.jl
using pcvct
initializeVCT(path_to_physicell, path_to_data)
```
Finally, run the following command to launch PhysiCell Studio for a simulation with id `sim_id`:
```
runStudio(sim_id; python_path=path_to_python, studio_path=path_to_studio)
```
where `path_to_python` is the path to the python executable and `path_to_studio` is the path to the PhysiCell Studio __folder__.
For example,
```
runStudio(1; python_path="/usr/bin/python3", studio_path="/home/user/PhysiCell-Studio")
```
Note: if using a python executable that is on your PATH, you can supply just the name of it, e.g. `path_to_python="python3"`.

The shell environment variables `PCVCT_PYTHON_PATH` and `PCVCT_STUDIO_PATH` can be set to avoid needing to pass these arguments each time.

Running the studio this way generates temporary config and rules files.
Any edits to the parameters in studio will be lost when the studio is closed.

# Best practices

1. Do NOT manually edit files inside `inputs`.
If parameter values need to be changed, use variations as shown in `VCT/GenerateData.jl`.
Let pcvct manage the databases that track simulation parameters.

2. Anytime a group of simulation replicates (a `Monad` in pcvct internals) is requested, all simulations in that group are used, regardless of the value of `n_replicates`.
If the number of simulations in the group is less than `n_replicates`, then additional simulations are run to reach `n_replicates`.
Note: if `use_previous=false`, then `n_replicates` will be run regardless.
If you do need an upper bound on the number of simulations in such a grouping, submit an issue.
It is assumed that most, if not all use cases, will benefit from more simulations.

# Database upgrade notes:

## to v0.0.3
Introduce XML-based cell initial conditions. This introduces `ic_cell_variations`. Also, standardized the use of `config_variation` in place of `variation`. Key changes include:
- Renaming the `variation_id` column in the `simulations` and `monads` tables to `config_variation_id`.
- Adding the `ic_cell_variation_id` column to the `simulations` and `monads` tables.
- In `data/inputs/configs`, renaming all instances of "variation" to "config_variation" in filenames and databases.

## to v0.0.10
Start tracking the PhysiCell version used in the simulation.
This introduces the `physicell_versions` table which tracks the PhysiCell versions used in simulations.
Currently, only supports reading the PhysiCell version, not setting it (e.g., through git commands).
Key changes include:
- Adding the `physicell_version_id` column to the `simulations`, `monads`, and `samplings` tables.
- Adding the `physicell_versions` table.
  - If `PhysiCell` is a git-tracked repo, this will store the commit hash as well as any tag and repo owner it can find based on the remotes. It will also store the date of the commit.
  - If `PhysiCell` is not a git-tracked repo, it will read the `VERSION.txt` file and store that as the `commit_hash` with `-download` appended to the version.

# Notes
When an object `T <: AbstractTrial` is instantiated, immediately add it to the database AND to the CSV.
If a simulation fails, remove it from the CSV without removing it from the database/output.

# To dos
- Rename for Julia registry. It will be so nice to have user Pkg.add("pcvct") and have it work.
  - PhysiCellVT.jl
  - PhysiVT.jl (possible confusion with the OpenVT project where VT = virtual tissue)
  - PhysiCellCohorts.jl
  - PhysiCellTrials.jl
  - PhysiVirtualTrials.jl
  - PhysiCellBatch.jl
  - PhysiBatch.jl
  - PhysiCellDB.jl
  - PhysiDB.jl (the clear name for make the database portion a separate package)
  - PhysiCell.jl (kinda self-important to assume this will be all the PhysiCell stuff in Julia)