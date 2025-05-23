# Varying parameters
pcvct makes it super easy to vary parameters in your model.
This is useful for model exploration, sensitivity analysis, and parameter estimation.
To start varying parameters in your model, you need to specify where the parameter is located in the input files and what value(s) you want to use.

## XML paths
The "where" is internally in pcvct called the `target` and it is represented as a vector of strings, representing the XML path to the parameter.
As pcvct supports varying parameters only in XML files, every target can be determined by reading the XML file and writing the path to the parameter.
When the XML path needs to find a child element with a specific attribute--e.g., `cell_definitions` has many `cell_definition` children each with a `name` attribute--the element in the XML path vector is formatted as
```julia
"<tag>:<attribute>:<value>"
```

For example, if you want to vary the `death_rate` of the `apoptosis` process--PhysiCell assigns the model code `100` to `apoptosis`--in the `T_cell` cell type, the XML path would be
```julia
["cell_definitions", "cell_definition:name:T_cell", "phenotype", "death", "model:code:100", "death_rate"]
```
There is also another unique attribute that can be used for apoptosis, but pcvct has better support for the `model:code` attribute.
```julia
["cell_definitions", "cell_definition:name:T_cell", "phenotype", "death", "model:name:apoptosis", "death_rate"]
```

In instances in which the "label" that identifies the element to select is not an attribute but a child element, the following format is used:
```julia
"<tag>::<child_tag>:<value>"
```
Note the `::` in the first separator.
This is necessary, e.g., for the `initial_parameter_distributions` as the `behavior` is a child element of the `distribution` element:
```julia
["cell_definitions", "cell_definition:name:T_cell", "initial_parameter_distributions", "distribution::behavior:cycle entry"]
```

## Helper functions to define targets
Remembering the XML paths can be cumbersome, error-prone, and repetitive.
So, pcvct provides a set of helper functions for the varied input types.

### Varying config parameters
Most of the parameters in your model are (likely) located in the configuration XML file, the one typically called `PhysiCell_settings.xml`.
The [`configPath`](@ref) function can be used to create the XML path to almost[^1] any parameter in the configuration file.
This function is crafted to infer the desired XML path and should feel fairly intuitive for most parameters.
Here is a near-exhaustive list of the available tokens (the flexibiilty of `configPath` allows for some of these XML paths to be created in multiple ways):

#### Single tokens
The following can be passed in alone to `configPath`:
```julia
- "x_min", "x_max", "y_min", "y_max", "z_min", "z_max", "dx", "dy", "dz", "use_2D" (see [`domainPath`](@ref))
- "max_time", "dt_intracellular", "dt_diffusion", "dt_mechanics", "dt_phenotype" (see [`timePath`](@ref))
- "full_data_interval" (see [`fullSavePath`](@ref))
- "SVG_save_interval" (see [`svgSavePath`](@ref))
```

#### Double tokens
The following can be passed in as the second argument to `configPath(<substrate_name>, <token>)` where `<substrate_name>` is the name of the substrate in your model:
```julia
- "diffusion_coefficient", "decay_rate" (see [`substratePath`](@ref))
- "initial_condition", "Dirichlet_boundary_condition" (see [`substratePath`](@ref))
- "xmin", "xmax", "ymin", "ymax", "zmin", "zmax" (see [`substratePath`](@ref))
```

The following can be passed in as the second argument to `configPath(<cell_type>, <token>)` where `<cell_type>` is the name of the cell type in your model:
```julia
- "total", "fluid_fraction", "nuclear", "fluid_change_rate", "cytoplasmic_biomass_change_rate", "nuclear_biomass_change_rate", "calcified_fraction", "calcification_rate", "relative_rupture_volume" (see [`volumePath`](@ref))
- "cell_cell_adhesion_strength", "cell_cell_repulsion_strength", "relative_maximum_adhesion_distance", "attachment_elastic_constant", "attachment_rate", "detachment_rate", "maximum_number_of_attachments" (see [`mechanicsPath`](@ref))
- "set_relative_equilibrium_distance", "set_absolute_equilibrium_distance" (see [`mechanicsPath`](@ref))
- "speed", "persistence_time", "migration_bias" (see [`motilityPath`](@ref))
- "apoptotic_phagocytosis_rate", "necrotic_phagocytosis_rate", "other_dead_phagocytosis_rate", "attack_damage_rate", "attack_duration" (see [`cellInteractionsPath`](@ref))
- "damage_rate", "damage_repair_rate" (see [`integrityPath`](@ref))
- "custom:<tag>" (see [`customDataPath`](@ref))
```

Finally, for a user parameter you can use the following:
```julia
configPath("user_parameters", <tag>)
```
where `<tag>` is the name of the user parameter in your model.

#### Triple tokens
The following can be passed in as the third argument to `configPath(<substrate_name>, "Dirichlet_options", <token>)` where `<substrate_name>` is the name of the substrate in your model:
```julia
- "xmin", "xmax", "ymin", "ymax", "zmin", "zmax" (see [`substratePath`](@ref))
```

The following tokens work with a `cell_type` from your model:
```julia
- `configPath(<cell_type>, "cycle_rate", "0")` (see [`cyclePath`](@ref))
- `configPath(<cell_type>, "cycle_duration", "0")` (see [`cyclePath`](@ref))
- `configPath(<cell_type>, "apoptosis", <parameter>)` (see [`apoptosisPath`](@ref))
- `configPath(<cell_type>, "necrosis", <parameter>)` (see [`necrosisPath`](@ref))
- `configPath(<cell_type>, "adhesion", <cell_type>)` (see [`mechanicsPath`](@ref))
- `configPath(<cell_type>, "motility", <parameter>)` (see [`motilityPath`](@ref))
- `configPath(<cell_type>, "chemotaxis", <parameter>)` (see [`motilityPath`](@ref))
- `configPath(<cell_type>, "advanced_chemotaxis", <parameter>)` (see [`motilityPath`](@ref))
- `configPath(<cell_type>, "advanced_chemotaxis", <substrate_name>)` (see [`motilityPath`](@ref))
- `configPath(<cell_type>, <substrate_name>, <parameter>)` (see [`secretionPath`](@ref))
- `configPath(<cell_type>, <interaction>, <cell_type>)` (`<interaction>` is one of "phagocytosis", "fusion", "transformation", "attack_rate") (see [`cellInteractionsPath`](@ref))
- `configPath(<cell_type>, "custom", <tag>)` (see [`customDataPath`](@ref))
```

#### Four tokens
The following tokens work with a `cell_type` from your model:
```julia
- `configPath(<cell_type>, "cycle", "duration", <index>)` (see [`cyclePath`](@ref))
- `configPath(<cell_type>, "cycle", "rate", <start_index>)` (see [`cyclePath`](@ref))
- `configPath(<cell_type>, "necrosis", "duration", <index>)` (see [`necrosisPath`](@ref))
- `configPath(<cell_type>, "necrosis", "transition_rate", <start_index>)` (see [`necrosisPath`](@ref))
- `configPath(<cell_type>, "initial_parameter_distribution", <behavior>, <parameter>)` (see [`initialParameterDistributionPath`](@ref))
```

[^1]: Intracellular parameters are not supported (yet). Others may also be missing. If the [`configPath`](@ref) function does not recognize the tokens you pass it, it will throw an error showing the available tokens (for the given number of tokens you passed).