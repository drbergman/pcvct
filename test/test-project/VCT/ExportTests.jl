filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

export_test(folder) = begin
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
end

export_folder = exportSimulation(1)
export_test(export_folder)

ic_cell_xml_folder = exportSimulation(simulation_with_ic_cell_xml_id)
export_test(ic_cell_xml_folder)