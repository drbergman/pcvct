# Renaming
Julia packages are supposed to follow certain [conventions](https://pkgdocs.julialang.org/v1/creating-packages/#Package-naming-rules) to be admitted to the General registry.
In particular, it must end with `.jl`, be `CamelCase`, avoid jargon/acronyms (looking at you pcvct), and be descriptive.
We want to clearly tie it to PhysiCell but not make it sound like a replacement for PhysiCell, i.e. not `PhysiCell.jl`.
Here are the options brainstormed thus far:
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