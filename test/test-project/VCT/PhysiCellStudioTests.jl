using SQLite
filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

fake_python_path = "fake_python_path"
fake_studio_path = "fake_studio_path"
@test_throws ArgumentError pcvct.resolveStudioGlobals(missing, missing)
@test_throws ArgumentError pcvct.resolveStudioGlobals(fake_python_path, missing)

@test_throws Base.IOError runStudio(1; python_path=fake_python_path, studio_path=fake_studio_path)

@test pcvct.path_to_python == fake_python_path
@test pcvct.path_to_studio == fake_studio_path