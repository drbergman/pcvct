using pcvct
using Test

@testset "pcvct.jl" begin
    # Write your tests here.
    include("./test-project/VCT/RunSampling.jl")
    include("./test-project/VCT/ConfigurationTests.jl")
    include("./test-project/VCT/SensitivityTests.jl")
end
