filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

@test pcvct.physicellVersion() == readchomp(joinpath(pcvct.physicell_dir, "VERSION.txt"))
@test pcvct.physicellVersion(Simulation(1)) == readchomp(joinpath(pcvct.physicell_dir, "VERSION.txt"))

path_to_file = joinpath("PhysiCell", "Makefile")

lines = readlines(path_to_file)
lines[1] *= " "
open(path_to_file, "w") do f
    for line in lines
        println(f, line)
    end
end

@test !pcvct.gitDirectoryIsClean(pcvct.physicell_dir)
initializeModelManager(pcvct.physicell_dir, pcvct.data_dir)

lines[1] = lines[1][1:end-1]
open(path_to_file, "w") do f
    for line in lines
        println(f, line)
    end
end

@test pcvct.gitDirectoryIsClean(pcvct.physicell_dir)

# test with PhysiCell download
original_data_dir = pcvct.data_dir
original_physicell_dir = pcvct.physicell_dir

project_dir = "./test-project-download"
createProject(project_dir; clone_physicell=false)
data_dir = joinpath(project_dir, "data")
physicell_dir = joinpath(project_dir, "PhysiCell")
initializeModelManager(physicell_dir, data_dir)

initializeModelManager(original_physicell_dir, original_data_dir)