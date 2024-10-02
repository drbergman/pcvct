# pcvct

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://drbergman.github.io/pcvct/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://drbergman.github.io/pcvct/dev/)
[![Build Status](https://github.com/drbergman/pcvct/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/drbergman/pcvct/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/drbergman/pcvct/branch/main/graph/badge.svg)](https://codecov.io/gh/drbergman/pcvct)

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