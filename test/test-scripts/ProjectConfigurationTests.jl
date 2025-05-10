filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

@test_throws ArgumentError pcvct.sanitizePathElement("..")
@test_throws ArgumentError pcvct.sanitizePathElement("~")
@test_throws ArgumentError pcvct.sanitizePathElement("/looks/like/absolute/path")

@test_throws ErrorException pcvct.folderIsVaried(:config, "not-a-config-folder")