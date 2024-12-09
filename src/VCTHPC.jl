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
    path_to_out, path_to_err = setSimulationOutputPaths(path_to_simulation_folder)
    path_to_job = joinpath(path_to_simulation_folder, "job.sh")
    job_name = "pcvct_$(simulation.id)"
    run(`sbatch --wrap="$cmd" --job-name=$(job_name) --output=$(path_to_out) --error=$(path_to_err)`)
    return false
end