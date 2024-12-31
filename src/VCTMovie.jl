export makeMovie_____

function makeMovie_____(simulation_id::Int)
    path_to_output_folder = joinpath(outputFolder("simulation", simulation_id), "output")
    if isfile("$(path_to_output_folder)/out.mp4")
        movie_generated = false
        return movie_generated
    end
    env = copy(ENV)
    env["PATH"] = "/opt/homebrew/bin:$(env["PATH"])"
    cmd = Cmd(`make jpeg OUTPUT=$(path_to_output_folder)`; env=env)
    cd(() -> run(pipeline(cmd; stdout=devnull, stderr=devnull)), physicell_dir)
    cmd = Cmd(`make movie OUTPUT=$(path_to_output_folder)`; env=env)
    cd(() -> run(pipeline(cmd; stdout=devnull, stderr=devnull)), physicell_dir)
    movie_generated = true
    jpgs = readdir(joinpath(outputFolder("simulation", simulation_id), "output"), sort=false)
    filter!(f -> endswith(f, ".jpg"), jpgs)
    for jpg in jpgs
        rm(joinpath(outputFolder("simulation", simulation_id), "output", jpg))
    end
    return movie_generated
end

function makeMovie_____(T::AbstractTrial)
    simulation_ids = getSimulationIDs(T)
    println("Making movies for $(typeof(T)) $(T.id) with $(length(simulation_ids)) simulations...")
    for simulation_id in simulation_ids
        print("\tMaking movie for simulation $simulation_id...")
        makeMovie_____(simulation_id)
        println("done.")
    end
end