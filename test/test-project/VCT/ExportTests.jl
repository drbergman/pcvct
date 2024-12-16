using Test, pcvct

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

path_to_physicell_folder = "./test-project/PhysiCell" # path to PhysiCell folder
path_to_data_folder = "./test-project/data" # path to data folder
initializeVCT(path_to_physicell_folder, path_to_data_folder)

export_folder = exportSimulation(1)
@test isdir(export_folder)
@test isfile(joinpath(export_folder, "config", "PhysiCell_settings.xml"))
@test isfile(joinpath(export_folder, "main.cpp"))
@test isfile(joinpath(export_folder, "Makefile"))
@test isfile(joinpath(export_folder, "custom_modules", "custom.cpp"))

@test begin
    lines = readlines(joinpath(export_folder, "main.cpp"))
    return !any(contains.(lines, "argument_parser"))
end

@test begin
    lines = readlines(joinpath(export_folder, "custom_modules", "custom.cpp"))
    return !any(contains.(lines, "load_initial_cells"))
end