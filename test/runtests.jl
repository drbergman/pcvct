using pcvct
using Test

include("./test-project/VCT/PrintHelpers.jl")

@testset "pcvct.jl" begin
    # Write your tests here.
    include("./test-project/VCT/CreateProject.jl")
    include("./test-project/VCT/RunSampling.jl")
    include("./test-project/VCT/PrunerTests.jl")
    include("./test-project/VCT/ConfigurationTests.jl")
    include("./test-project/VCT/ICCellTests.jl")
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

    # probably want this one last (it deletes/resets things)
    include("./test-project/VCT/DeletionTests.jl")
end
