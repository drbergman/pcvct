export makeMovie

function makeMovie(simulation_id::Int)
    path_to_output_folder = joinpath(data_dir, "outputs", "simulations", string(simulation_id), "output")
    if isfile("$(path_to_output_folder)/out.mp4")
        movie_generated = false
        return movie_generated
    end
    env = copy(ENV)
    env["PATH"] = "/opt/homebrew/bin:$(env["PATH"])"
    cmd = Cmd(`make jpeg OUTPUT=$(path_to_output_folder)`; env=env)
    cd(()->run(cmd), physicell_dir)
    cmd = Cmd(`make movie OUTPUT=$(path_to_output_folder)`; env=env)
    cd(()->run(cmd), physicell_dir)
    movie_generated = true
    jpgs = readdir(joinpath(data_dir, "outputs", "simulations", string(simulation_id), "output"), sort=false)
    filter!(f -> endswith(f, ".jpg"), jpgs)
    for jpg in jpgs
        rm(joinpath(data_dir, "outputs", "simulations", string(simulation_id), "output", jpg))
    end
    return movie_generated
end

function makeMovie(T::AbstractTrial)
    simulation_ids = getSimulationIDs(T)
    for simulation_id in simulation_ids
        makeMovie(simulation_id)
    end
end