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
    path_to_output_folder = "$(data_dir)/outputs/simulations/$(simulation.id)/output"
    if prune_options.prune_svg
        rm(glob("snapshot*.svg", path_to_output_folder), force=true)
        if prune_options.prune_initial
            rm(glob("initial*.svg", path_to_output_folder), force=true)
        end
        if prune_options.prune_final
            rm(glob("final*.svg", path_to_output_folder), force=true)
        end
    end
    if prune_options.prune_txt
        rm(glob("output*.txt", path_to_output_folder), force=true)
        if prune_options.prune_initial
            rm(glob("initial*.txt", path_to_output_folder), force=true)
        end
        if prune_options.prune_final
            rm(glob("final*.txt", path_to_output_folder), force=true)
        end
    end
    if prune_options.prune_mat
        rm(glob("output*.mat", path_to_output_folder), force=true)
        if prune_options.prune_initial
            rm(glob("initial*.mat", path_to_output_folder), force=true)
        end
        if prune_options.prune_final
            rm(glob("final*.mat", path_to_output_folder), force=true)
        end
    end
end