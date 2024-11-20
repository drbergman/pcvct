# pcvct

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://drbergman.github.io/pcvct/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://drbergman.github.io/pcvct/dev/)
[![Build Status](https://github.com/drbergman/pcvct/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/drbergman/pcvct/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/drbergman/pcvct/branch/main/graph/badge.svg)](https://codecov.io/gh/drbergman/pcvct)

# Database upgrade notes:

## to v0.0.3
Introduce XML-based cell initial conditions. This introduces `ic_cell_variations`. Also, standardized the use of `config_variation` in place of `variation`. Key changes include:
- Renaming the `variation_id` column in the `simulations` and `monads` tables to `config_variation_id`.
- Adding the `ic_cell_variation_id` column to the `simulations` and `monads` tables.
- In `data/inputs/configs`, renaming all instances of "variation" to "config_variation" in filenames and databases.

## to v0.0.9
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
- Figure out how to link pcvct verions to PhysiCell versions
  - where does PhysiCell submodule fit in? Just for tests? Or for the whole package?
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