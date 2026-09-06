export PhysiCellSimulator

#! AbstractSimulator and all interface function stubs are defined in ModelManager.jl.
#! This file defines the PhysiCell concrete backend and re-exports AbstractSimulator
#! (already exported by ModelManager, re-exported from the module level).

"""
    PhysiCellSimulator <: AbstractSimulator

The PhysiCell backend for [`AbstractSimulator`](@ref ModelManager.AbstractSimulator). Holds all PhysiCell-specific
state (paths, compiler, version ID) so that the generic infrastructure in
[`ModelManagerGlobals`](@ref) remains simulator-agnostic.

Interface methods are implemented in `src/physicell_simulator.jl`.

# Fields
- `dir::String`: Path to the PhysiCell source directory.
- `compiler::String`: C++ compiler command (default `"g++"`; overridden by `PHYSICELL_CPP` env var).
- `current_version_id::Int`: Database ID for the active PhysiCell version; re-resolved before every compilation.
- `march_flag::String`: `-march` flag for compilation, set by [`initializeModelManager`](@ref) to
  `"x86-64"` when ModelManager detects a scheduler and `"native"` otherwise, since a cluster runs
  the cached executable on a machine that did not build it.
- `path_to_python::Union{Missing,String}`: Python executable path for PhysiCell Studio.
- `path_to_studio::Union{Missing,String}`: PhysiCell Studio directory path.
- `path_to_magick::Union{Missing,String}`: ImageMagick binary path for movie creation.
- `path_to_ffmpeg::Union{Missing,String}`: FFmpeg binary path for movie creation.
"""
mutable struct PhysiCellSimulator <: ModelManager.AbstractSimulator
    dir::String
    compiler::String
    current_version_id::Int
    march_flag::String
    path_to_python::Union{Missing,String}
    path_to_studio::Union{Missing,String}
    path_to_magick::Union{Missing,String}
    path_to_ffmpeg::Union{Missing,String}
end

"""
    PhysiCellSimulator()

Construct a default `PhysiCellSimulator` with placeholder values. Fields are
populated during `__init__` and [`initializeModelManager`](@ref).
"""
#! No `isRunningOnHPC()` here. It shells out to `which sbatch`, and this constructor runs in
#! `__init__` *before* the precompilation guard, so every precompilation of every dependent package
#! spawned a process -- while the comment there called that block "pure in-memory work".
#! `initializeModelManager` sets `march_flag` from the `run_on_hpc` ModelManager has just probed,
#! which is also one source of truth instead of two independent probes.
function PhysiCellSimulator()
    return PhysiCellSimulator(
        "",          # dir — set by initializeModelManager
        "g++",       # compiler — overridden by __init__ from ENV
        -1,          # current_version_id — set during DB init, refreshed at each compile
        "native",    # march_flag — set by initializeModelManager from ModelManager's HPC probe
        missing,     # path_to_python
        missing,     # path_to_studio
        missing,     # path_to_magick
        missing,     # path_to_ffmpeg
    )
end
