using Plots

include("./VCTExtraction.jl")

cd("/Users/bergmand/pcvct/data/")
path_to_outputs = ["/Users/bergmand/pcvct/data/simulations/$d/output/" for d in 1:8]
t = VCTExtraction.loadTimeTimeSeries(path_to_outputs)
counts = VCTExtraction.loadCellCountTimeSeries(path_to_outputs)

p = plot(t,counts)

savefig("temp.png")

x=VCTExtraction.loadCellTypeCountTimeSeries(path_to_outputs,collect(0:8))

VCTExtraction.loadCellTypeCountTimeSeries(path_to_outputs[end],0)


x = VCTExtraction.loadCellTypeCountTimeSeries(1,1,0,collect(0:3))

y = VCTExtraction.extractCellData(path_to_outputs[1],"initial_cells.mat","position")


substrates = VCTExtraction.loadSubstrateDensityTimeSeries(path_to_outputs,"oxygen")



