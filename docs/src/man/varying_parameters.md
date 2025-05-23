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
So, pcvct provides a set of helper functions for the 
Most of the parameters in your model are (likely) located in the configuration XML file, the one typically called `PhysiCell_settings.xml`.