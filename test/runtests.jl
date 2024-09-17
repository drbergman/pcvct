using pcvct
using Test

include("./test-project/VCT/PrintHelpers.jl")

@testset "pcvct.jl" begin
    # Write your tests here.
    include("./test-project/VCT/RunSampling.jl")
    include("./test-project/VCT/ConfigurationTests.jl")
    include("./test-project/VCT/SensitivityTests.jl")
end
