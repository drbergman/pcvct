using Glob, Parameters

export PruneOptions

@with_kw struct PruneOptions
    prune_svg::Bool = false
    prune_txt::Bool = false
    prune_mat::Bool = false

    prune_initial::Bool = false
    prune_final::Bool = false
end

function pruneSimulationOutput(simulation::Simulation; prune_options::PruneOptions=PruneOptions())
    path_to_output_folder = joinpath(data_dir, "outputs", "simulations", string(simulation.id), "output")
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