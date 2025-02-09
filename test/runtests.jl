using pcvct, Test

include("./test-project/VCT/PrintHelpers.jl")

@testset "pcvct.jl" begin
    # Write your tests here.
    include("./test-project/VCT/CreateProjectTests.jl")
    
    include("./test-project/VCT/GenerateData.jl") # this file is created by CreateProjectTests.jl

    include("./test-project/VCT/RunnerTests.jl")
    include("./test-project/VCT/UserAPITests.jl")
    include("./test-project/VCT/ImportTests.jl")
    include("./test-project/VCT/PrunerTests.jl")
    include("./test-project/VCT/ConfigurationTests.jl")
    include("./test-project/VCT/ICCellTests.jl")
    include("./test-project/VCT/ICECMTests.jl")
    include("./test-project/VCT/ExportTests.jl")
    include("./test-project/VCT/SensitivityTests.jl")
    include("./test-project/VCT/DatabaseTests.jl")
    include("./test-project/VCT/ClassesTests.jl")
    include("./test-project/VCT/LoaderTests.jl")
    if Sys.isapple()
        include("./test-project/VCT/MovieTests.jl")
    end
    include("./test-project/VCT/PopulationTests.jl")
    include("./test-project/VCT/SubstrateTests.jl")
    include("./test-project/VCT/VariationsTests.jl")
    include("./test-project/VCT/HPCTests.jl")
    include("./test-project/VCT/ModuleTests.jl")
    include("./test-project/VCT/PhysiCellVersionTests.jl")
    include("./test-project/VCT/PhysiCellStudioTests.jl")

    # probably want this one last (it deletes/resets things)
    include("./test-project/VCT/DeletionTests.jl")
end
