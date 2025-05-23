export makeMovie

"""
    makeMovie(simulation_id::Int; magick_path::Union{Missing,String}=path_to_magick, ffmpeg_path::Union{Missing,String}=path_to_ffmpeg)

Make a movie for the simulation with ID `simulation_id`.

Use the PhysiCell Makefile to generate the movie.
This process requires first generating JPEG files, which are then used to create the movie.
Deletes the JPEG files after the movie is generated.

This relies on ImageMagick and FFmpeg being installed on the system.
There are three ways to allow this function to find these dependencies:
  1. Pass the path to the dependencies using the `magick_path` and `ffmpeg_path` keyword arguments.
  2. Set the `PATH` environment variable to include the directories containing the dependencies.
  3. Set environment variables `PCVCT_IMAGEMAGICK_PATH` and `PCVCT_FFMPEG_PATH` before `using pcvct`.
"""
function makeMovie(simulation_id::Int; magick_path::Union{Missing,String}=path_to_magick, ffmpeg_path::Union{Missing,String}=path_to_ffmpeg)
    path_to_output_folder = joinpath(trialFolder(Simulation, simulation_id), "output")
    if isfile("$(path_to_output_folder)/out.mp4")
        movie_generated = false
        return movie_generated
    end
    env = copy(ENV)
    os_variable_separator = Sys.iswindows() ? ";" : ":"
    path_components = split(env["PATH"], os_variable_separator)
    resolveMovieGlobals(magick_path, ffmpeg_path)
    if !ismissing(magick_path) && !(magick_path ∈ path_components)
        env["PATH"] = "$(magick_path)$(os_variable_separator)$(env["PATH"])"
    end
    if !ismissing(ffmpeg_path) && !(ffmpeg_path ∈ path_components) && ffmpeg_path != magick_path
        env["PATH"] = "$(ffmpeg_path)$(os_variable_separator)$(env["PATH"])"
    end
    if !shellCommandExists("magick")
        throw(ErrorException("ImageMagick is not installed. Please install it to generate movies."))
    elseif !shellCommandExists("ffmpeg")
        throw(ErrorException("FFmpeg is not installed. Please install it to generate movies."))
    end
    cmd = Cmd(`make jpeg OUTPUT=$(path_to_output_folder)`; env=env, dir=physicell_dir)
    run(pipeline(cmd; stdout=devnull, stderr=devnull))
    cmd = Cmd(`make movie OUTPUT=$(path_to_output_folder)`; env=env, dir=physicell_dir)
    run(pipeline(cmd; stdout=devnull, stderr=devnull))
    movie_generated = true
    jpgs = readdir(joinpath(trialFolder(Simulation, simulation_id), "output"), sort=false)
    filter!(f -> endswith(f, ".jpg"), jpgs)
    for jpg in jpgs
        rm(joinpath(trialFolder(Simulation, simulation_id), "output", jpg))
    end
    return movie_generated
end

"""
    resolveMovieGlobals(magick_path::Union{Missing,String}, ffmpeg_path::Union{Missing,String})

Set the global variables `path_to_magick` and `path_to_ffmpeg` to the provided paths.
"""
function resolveMovieGlobals(magick_path::Union{Missing,String}, ffmpeg_path::Union{Missing,String})
    if !ismissing(magick_path)
        global path_to_magick = magick_path
    end
    if !ismissing(ffmpeg_path)
        global path_to_ffmpeg = ffmpeg_path
    end
end

"""
    makeMovie(T::Union{AbstractTrial,PCVCTOutput}; magick_path::Union{Missing,String}=path_to_magick, ffmpeg_path::Union{Missing,String}=path_to_ffmpeg)

Make movies for all simulations in `T`, a simulation, monad, sampling, or trial.

Uses the PhysiCell Makefile to generate the movies.

# Examples
```julia
makeMovie(123) # make a movie for simulation 123
makeMovie(sampling) # make movies for all simulations in sampling
```
"""
function makeMovie(T::Union{AbstractTrial,PCVCTOutput}; kwargs...)
    simulation_ids = getSimulationIDs(T)
    println("Making movies for $(typeof(T)) $(T.id) with $(length(simulation_ids)) simulations...")
    for simulation_id in simulation_ids
        print("  Making movie for simulation $simulation_id...")
        makeMovie(simulation_id; kwargs...)
        println("done.")
    end
end