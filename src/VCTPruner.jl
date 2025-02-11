using Glob, Parameters

export PruneOptions

"""
    PruneOptions

Automatically prune some of the generated output files from a simulation.

# Fields
- `prune_svg::Bool=false`: Prune SVG files
- `prune_txt::Bool=false`: Prune TXT files
- `prune_mat::Bool=false`: Prune MAT files
- `prune_initial::Bool=false`: If any of the above are true, also prune the initial files for that type
- `prune_final::Bool=false`: If any of the above are true, also prune the final files for that type
"""
@with_kw struct PruneOptions
    prune_svg::Bool = false
    prune_txt::Bool = false
    prune_mat::Bool = false

    prune_initial::Bool = false
    prune_final::Bool = false
end

function pruneSimulationOutput(simulation_id::Integer; prune_options::PruneOptions=PruneOptions())
    path_to_output_folder = joinpath(outputFolder("simulation", simulation_id), "output")
    if prune_options.prune_svg
        glob("snapshot*.svg", path_to_output_folder) .|> x->rm(x, force=true)
        if prune_options.prune_initial
            glob("initial*.svg", path_to_output_folder) .|> x->rm(x, force=true)
        end
        if prune_options.prune_final
            glob("final*.svg", path_to_output_folder) .|> x->rm(x, force=true)
        end
    end
    if prune_options.prune_txt
        glob("output*.txt", path_to_output_folder) .|> x->rm(x, force=true)
        if prune_options.prune_initial
            glob("initial*.txt", path_to_output_folder) .|> x->rm(x, force=true)
        end
        if prune_options.prune_final
            glob("final*.txt", path_to_output_folder) .|> x->rm(x, force=true)
        end
    end
    if prune_options.prune_mat
        glob("output*.mat", path_to_output_folder) .|> x->rm(x, force=true)
        if prune_options.prune_initial
            glob("initial*.mat", path_to_output_folder) .|> x->rm(x, force=true)
        end
        if prune_options.prune_final
            glob("final*.mat", path_to_output_folder) .|> x->rm(x, force=true)
        end
    end
end

pruneSimulationOutput(simulation::Simulation; prune_options::PruneOptions=PruneOptions()) = pruneSimulationOutput(simulation.id; prune_options=prune_options)
