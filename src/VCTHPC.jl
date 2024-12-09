"""
`isRunningOnHPC()`
Returns `true` if the current environment is an HPC environment, `false` otherwise.
Currently, this function checks if the `sbatch` command is available, indicating a SLURM environment.
"""
function isRunningOnHPC()
    cmd = `which sbatch`
    p = run(ignorestatus(cmd))
    return p.exitcode == 0
end

"""
`useHPC(use::Bool=true)`
Sets the global variable `submit_on_hpc` to `use`.
"""
function useHPC(use::Bool=true)
    global submit_on_hpc = use
end

"""
`runSimulationOnHPC(simulation::Simulation, cmd::Cmd, path_to_simulation_folder::String, monad_id::Int, prune_options::PruneOptions)`
Runs a simulation on an HPC environment using SLURM.
"""
function runSimulationOnHPC(simulation::Simulation, cmd::Cmd, path_to_simulation_folder::String, monad_id::Int, prune_options::PruneOptions)
    path_to_job = writeSimulationJob(simulation, monad_id, cmd, path_to_simulation_folder, prune_options)
    run(`sbatch $path_to_job`)
    return true
end

"""
`writeSimulationJob(simulation::Simulation, monad_id::Int, cmd::Cmd, path_to_simulation_folder::String, prune_options::PruneOptions)`
Writes a job script for a simulation on an HPC environment.
Also writes a resolution script to handle the simulation status after completion.
"""
function writeSimulationJob(simulation::Simulation, monad_id::Int, cmd::Cmd, path_to_simulation_folder::String, prune_options::PruneOptions)
    path_to_err = sbatch_options["error"](simulation)
    path_to_resolution_script = writeSimulationResolutionScript(simulation, monad_id, path_to_err, cmd, prune_options)
    path_to_job = joinpath(path_to_simulation_folder, "job.sh")
    header_str = """#!/bin/bash
    #SBATCH --job-name=$(sbatch_options["job-name"](simulation))
    """
    for (key, value) in sbatch_options
        if key == "module_load_julia" || key == "job-name"
            continue
        end
        if typeof(value) == Function
            value = value(simulation)
        end
        header_str *= "#SBATCH --$key=$value\n"
    end
    
    job_str = """
    $(header_str)

    $(cmd)

    exit_code=\$?

    $(sbatch_options["module_load_julia"])

    julia $(path_to_resolution_script) \$exit_code
    """
    open(path_to_job, "w") do io
        println(io, job_str)
    end

    return path_to_job
end

"""
`defaultJobOptions()`
Returns a dictionary with default options for a job script for use with SLURM.
"""
function defaultJobOptions()
    path_to_simulation_folder = s -> joinpath(data_dir, "outputs", "simulations", string(s.id))
    return Dict(
        "job-name" => simulation -> "pcvct_$(simulation.id)",
        "output" => simulation -> joinpath(path_to_simulation_folder(simulation), "output.log"),
        "error" => simulation -> joinpath(path_to_simulation_folder(simulation), "output.err"),
        "time" => "1:00:00",
        "ntasks" => 1,
        "cpus-per-task" => 1,
        "mem" => "1G",
        "partition" => "standard",
        "module_load_julia" => "module load julia/1.11.1"
    )
end

"""
`setDefaultJobOptions(options::Dict)`
Sets the default job options for use with SLURM.
For any key-value pair in `options`, the corresponding key in the global `sbatch_options` dictionary is set to the value.
A line is then added to the job script for each key-value pair in `options`: `#SBATCH --key=value`.

Additionally, the `module_load_julia` key is used to set the command to load the Julia module.
"""
function setDefaultJobOptions(options::Dict)
    for (key, value) in options
        global sbatch_options[key] = value
    end
end

"""
`writeSimulationResolutionScript(simulation::Simulation, monad_id::Int, path_to_err::String, cmd::Cmd, prune_options::PruneOptions)`
Writes a resolution script for a simulation on an HPC environment.
Handles updating the database and pruning the simulation output.
"""
function writeSimulationResolutionScript(simulation::Simulation, monad_id::Int, path_to_err::String, cmd::Cmd, prune_options::PruneOptions)
    path_to_resolution_script = joinpath(data_dir, "outputs", "simulations", string(simulation.id), "resolveThisHPCSimulationStatus.jl")
    prune_options_fields = ["$fn=$(getfield(prune_options, fn))" for fn in fieldnames(PruneOptions)]
    prune_options_str = "PruneOptions($(join(prune_options_fields, ", ")))"
    open(path_to_resolution_script, "w") do io
        println(io, """
        using pcvct
        initializeVCT($(physicell_dir), $(data_dir))

        simulation_id = $(simulation.id)
        monad_id = $(monad_id)
        exit_code = parse(Int, ARGS[1])
        path_to_err = \"$(path_to_err)\"
        cmd = $(cmd)

        prune_options = $(prune_options_str)
        
        pcvct.resolveHPCSimulationStatus(simulation_id, monad_id, exit_code, path_to_err, cmd, prune_options)
        """
        )
    end
    return path_to_resolution_script
end

"""
`resolveHPCSimulationStatus(simulation_id::Int, monad_id::Int, exit_code::Int, path_to_err::String, cmd::Cmd, prune_options::PruneOptions)`
Resolves the status of a simulation on an HPC environment.
This is called from the programmatically written resolution script.
"""
function resolveHPCSimulationStatus(simulation_id::Int, monad_id::Int, exit_code::Int, path_to_err::String, cmd::Cmd, prune_options::PruneOptions)
    if exit_code != 0
        resolveSimulationError(simulation_id, monad_id, path_to_err, cmd)
    else
        rm(path_to_err; force=true)
        DBInterface.execute(db,"UPDATE simulations SET status_code_id=$(getStatusCodeID("Completed")) WHERE simulation_id=$(simulation_id);" )
    end

    pruneSimulationOutput(simulation_id; prune_options=prune_options)
end