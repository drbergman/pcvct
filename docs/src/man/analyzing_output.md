# Analyzing output

## Loading output

### `PhysiCellSnapshot`
The base unit of PhysiCell output is the [`PhysiCellSnapshot`](@ref).
These are currently considered pcvct internals and so the API may change.
Each snapshot records the path to the PhysiCell output folder, its index in the sequence of outputs, the time of the snapshot in the simulation, and optionally the cell, substrate, and mesh data at that snapshot.

### `PhysiCellSequence`
A [`PhysiCellSequence`](@ref) is the full sequence of snapshots corresponding to a single PhysiCell simulation.
As with `PhysiCellSnapshot`'s, these are currently considered internals and their API may change.
In addition to the path to the PhysiCell output folder and the vector of `PhysiCellSnapshot`'s, it holds metadata for the simulation.

### `getCellDataSequence`
The main function to get sequences of cell data is [`getCellDataSequence`](@ref).
It accepts any of a simulation ID (`<:Integer`), a simulation (`::Simulation`), or a sequence (`::PhysiCellSequence`) and either a single label (`::String`) or a vector of labels (`::Vector{String}`).
For each cell in the simulation (as determined by the cell ID), the output creates a dictionary entry (the key is the integer cell ID) whose value is a named tuple with the input labels as keys as well as `:time`.
This means that if one sets

```julia
data = getCellDataSequence(1, "position")
```
Then one can access the positions of the cell with ID 78 by
```julia
cell_78_positions = data[78].position # an Nx3 matrix for the N integer-indexed outputs (ignores the `initial_*` and `final_*` files)
```
and plot the x-coordinates of this cell over time using
```julia
cell_78_times = data[78].time

using Plots
plot(cell_78_times, cell_78_positions[:,1])
```

**Note**: Each call to `getCellDataSequence` will load *all* the data unless a `PhysiCellSequence` is passed in.
Plan your analyses accordingly as loading simulation data is not fast.

## Population plots

### Group by Monad
Plotting population plots is one the most basic analysis tasks and pcvct makes it super easy!
If you call `plot` on a `Simulation`, `Monad`, `Sampling`, or the return value of a call to `run` (though not for a sensitivity analysis),
then a sequence of panels will be generated in a single figure.
Each panel will correspond to a `Monad` (replicates using the same parameter values) and will plot mean +/- SD for each cell type.

Finer-grained control of the output is possible, too!
- to include dead cells in your counts: `plot(...; ..., include_dead=true, ...)`
- select a subset of cell types to include: `plot(...; ..., include_cell_types="cancer", ...)`
- select a subset of cell types to exclude: `plot(...; ..., exclude_cell_types="cancer", ...)`

The `include_cell_types` and `exclude_cell_types` can also accept a `Vector{String}` to include or exclude certain cell types, respectively.
Furthermore, if the value of `include_cell_types` is a `Vector` and one of its entries is a `Vector{String}`, pcvct will interpret this to sum up those cell types.
In other words, to get the total tumor cell count in addition to the epithelial (`"epi"`) and mesenchymal (`"mes"`) components, you could use
```julia
using Plots
plot(Monad(1); include_cell_types=["epi", "mes", ["epi", "mes"]])
``` 

Finally, this makes use of Julia's Plot Recipes (see [RecipesBase.jl](https://docs.juliaplots.org/stable/RecipesBase/)) so any standard plotting keywords can be passed in:
```julia
using Plots
colors = [:blue :red] # Note the absence of a `,` or `;`. This is how Julia requires different series parameters to be passed in 
plot(Simulation(1); color=colors, include_cell_types=["cd8", "cancer"]) # will plot cd8s in blue and cancer in red.
```

### Group by cell type
Invert the above by including all data for a single cell type across all monads in a single panel with a call to `plotbycelltype`.
This function works on any `T<:AbstractTrial` (`Simulation`, `Monad`, `Sampling`, or `Trial`) as well as any `PCVCTOutput` object (the return value to `run`).
Everything above for `plot` applies here.

```julia
using Plots
plotbycelltype(Sampling(1); include_cell_types=["epi", "mes", ["epi", "mes"]], color=[:blue :red :purple], labels=["epi" "mes" "both"], legend=true)
```

## Substrate analysis
pcvct supports two ways to summarize substrate information over time.

### AverageSubstrateTimeSeries
An [`AverageSubstrateTimeSeries`](@ref) gives the time series for the average substrate across the entire domain.

```julia
simulation_id = 1
asts = AverageSubstrateTimeSeries(simulation_id)
using Plots
plot(asts.time, asts["oxygen"])
```

### `ExtracellularSubstrateTimeSeries`
An [`ExtracellularSubstrateTimeSeries`](@ref) gives the time series for the average substrate concentration in the extracellular space neighboring all cells of a given cell type.
In a simulation with `cd8` cells and `IFNg` diffusible substrate, plot the average concentration of IFNg experienced by CD8+ T cells using the following:

```julia
simulation_id = 1
ests = ExtracellularSubstrateTimeSeries(simulation_id)
using Plots
plot(ests.time, ests["cd8"]["IFNg"])
```

## Motility analysis
The `motilityStatistics` function returns the time alive, distance traveled, and mean speed for each cell in the simulation.
For each cell, these values are split amongst the cell types the given cell assumed throughout (or at least at the save times).
To calculate these values, the cell type at the start of the save interval is used and the net displacement is used to calculate the speed.
Optionally, users can pass in a coordinate direction to only consider speed in a given axis.

```julia
simulation_id = 1
mss = motilityStatistics(simulation_id)
all_mean_speeds_as_mes = [ms["mes"].speed for ms in mss if haskey(ms, "mes")] # concatenate all speeds as a "mes" cell type (if the given cell ever was a "mes")
all_times_as_mes = [ms["mes"].time for ms in mss if haskey(ms, "mes")] # similarly, get the time spent in the "mes" state
mean_mes_speed = all_mean_speeds_as_mes .* all_times_as_mes |> sum # start computing the weighted average of their speeds
mean_mes_speed /= sum(all_times_as_mes) # finish computing weighted average
```

```julia
mss = motilityStatistics(simulation_id; direction=:x) # only consider the movement in the x direction
```