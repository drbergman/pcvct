filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

pcvct.useHPC()

simulation = Simulation(1)

cmd_local = pcvct.prepareSimulationCommand(simulation, missing, true, false)
cmd_local_str = string(cmd_local)
cmd_local_str = strip(cmd_local_str, '`')
cmd_hpc = pcvct.prepareHPCCommand(cmd_local, simulation.id)

cmd_string = string(cmd_hpc)
cmd_string = strip(cmd_string, '`')

@test startswith(cmd_string, "sbatch")
@test contains(cmd_string, "--wrap=$(cmd_local_str)")
@test contains(cmd_string, "--wait")

pcvct.useHPC(false)