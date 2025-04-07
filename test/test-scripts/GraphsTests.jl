filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

snapshot = PhysiCellSnapshot(1, :final)
c = connectedComponents(snapshot)
c = connectedComponents(snapshot; include_cell_types=:all)
cell_types = pcvct.getCellTypeToNameDict(snapshot) |> values |> collect
c = connectedComponents(snapshot; include_cell_types=[cell_types])
c = connectedComponents(snapshot, "neighbors"; include_cell_types=[cell_types], exclude_cell_types=cell_types) #! for it to have empty keys after excluding

simulation_id = sampling_from_import |> getSimulationIDs |> first
snapshot = pcvct.PhysiCellSnapshot(simulation_id, :final)
c = connectedComponents(snapshot; include_cell_types=["fast T cell", "slow T cell", "effector T cell", "exhausted T cell"])
c = connectedComponents(snapshot; include_dead=true)