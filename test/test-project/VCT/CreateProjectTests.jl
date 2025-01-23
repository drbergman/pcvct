using LightXML
filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

project_dir = "./test-project"
createProject(project_dir)