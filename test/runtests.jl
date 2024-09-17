using pcvct
using Test

include("./test-project/VCT/PrintHelpers.jl")

@testset "pcvct.jl" begin
    # Write your tests here.
    include("./test-project/VCT/RunSampling.jl")
    include("./test-project/VCT/ConfigurationTests.jl")
    include("./test-project/VCT/SensitivityTests.jl")
    include("./test-project/VCT/DatabaseTests.jl")

    # probably want this one last (it deletes/resets things)
    include("./test-project/VCT/DeletionTests.jl")
end
