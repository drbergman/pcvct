function shellCommandExists(cmd::Union{String,Cmd})
    p = run(ignorestatus(`which $cmd`))
    return p.exitcode == 0
end

"""
    isRunningOnHPC()

Return `true` if the current environment is an HPC environment, `false` otherwise.

Currently, this function checks if the `sbatch` command is available, indicating a SLURM environment.
"""
isRunningOnHPC() = shellCommandExists(`sbatch`)

"""
    useHPC([use::Bool=true])

Set the global variable `run_on_hpc` to `use`.
"""
function useHPC(use::Bool=true)
    global run_on_hpc = use
end

"""
    defaultJobOptions()

Return a dictionary with default options for a job script for use with SLURM.
"""
function defaultJobOptions()
    return Dict(
        "job-name" => simulation_id -> "S$(simulation_id)",
        "mem" => "1G"
    )
end

"""
    setJobOptions(options::Dict)

Set the default job options for use with SLURM.
    
For any key-value pair in `options`, the corresponding key in the global `sbatch_options` dictionary is set to the value.
A flag is then added to the sbatch command for each key-value pair in `options`: `--key=value`.
"""
function setJobOptions(options::Dict)
    for (key, value) in options
        global sbatch_options[key] = value
    end
end