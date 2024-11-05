using Test, pcvct

filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

pcvct.createProject(; project_dir="./test-project")

