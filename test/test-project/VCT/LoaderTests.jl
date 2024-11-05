using Test, pcvct

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

path_to_physicell_folder = "./test-project/PhysiCell" # path to PhysiCell folder
path_to_data_folder = "./test-project/data" # path to data folder
initializeVCT(path_to_physicell_folder, path_to_data_folder)

sequence = PhysiCellSequence(path_to_data_folder * "/outputs/simulations/1/output")

seq_dict = getCellDataSequence(sequence, "elapsed_time_in_phase"; include_dead=true)

simulation_id = 1
simulation = Simulation(simulation_id)
simulation_population_time_series = populationTimeSeries(simulation; include_dead=true)
simulation_population_time_series = populationTimeSeries(simulation; include_dead=false)

for direction in [:x, :y, :z, :any]
    local mean_speed_dicts = computeMeanSpeed(simulation_id; direction=direction)
end

mean_speed_dicts = computeMeanSpeed(VCTClassID("Monad", 1))