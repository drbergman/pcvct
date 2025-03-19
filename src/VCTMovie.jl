export makeMovie

function makeMovie(simulation_id::Int)
    path_to_output_folder = joinpath(trialFolder("simulation", simulation_id), "output")
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
    jpgs = readdir(joinpath(trialFolder("simulation", simulation_id), "output"), sort=false)
    filter!(f -> endswith(f, ".jpg"), jpgs)
    for jpg in jpgs
        rm(joinpath(trialFolder("simulation", simulation_id), "output", jpg))
    end
    return movie_generated
end

"""
    makeMovie(T::AbstractTrial)

Make movies for all simulations in `T`, a simulation, monad, sampling, or trial.

Uses the PhysiCell Makefile to generate the movies.
Deletes the JPEG files after the movie is generated.    

Passing a single simulation ID into `makeMovie` will generate a movie for that simulation.

# Examples
```
makeMovie(123) # make a movie for simulation 123
makeMovie(sampling) # make movies for all simulations in sampling
```
"""
function makeMovie(T::AbstractTrial)
    simulation_ids = getSimulationIDs(T)
    println("Making movies for $(typeof(T)) $(T.id) with $(length(simulation_ids)) simulations...")
    for simulation_id in simulation_ids
        print("\tMaking movie for simulation $simulation_id...")
        makeMovie(simulation_id)
        println("done.")
    end
end