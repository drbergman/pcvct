filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

@test_throws ArgumentError pcvct.sanitizePathElements("..")
@test_throws ArgumentError pcvct.sanitizePathElements("~")
@test_throws ArgumentError pcvct.sanitizePathElements("/looks/like/absolute/path")

@test_throws ErrorException pcvct.folderIsVaried(:config, "not-a-config-folder")