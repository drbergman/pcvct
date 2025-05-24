# Varying parameters
All inputs that are varied by pcvct are stored in XML files, and pcvct has a standard representation of the paths to these parameters.

## XML paths
XML paths are represented as a vector of strings, where each string corresponds to a tag in the XML file.
When an attribute is needed to identify which of the identically tagged children to select, the string is formatted as
```julia
"<tag>:<attribute>:<value>"
```

If the content of a child element is needed to identify which tag to select, the string is formatted as
```julia
"<tag>::<child_tag>:<value>"
```
where `::` is used to separate the tag from the child tag.
This is necessary, e.g., for the `initial_parameter_distributions` as the `behavior` is a child element of the `distribution` element:
```julia
["cell_definitions", "cell_definition:name:T_cell", "initial_parameter_distributions", "distribution::behavior:cycle entry"]
```

## Helper functions to define targets
For each of the varied input types, pcvct has a helper function to create the XML path.

### Varying config parameters
The [`configPath`](@ref) function can be used to create the XML path to almost[^1] any parameter in the configuration file intuitively.
See [Config XML paths](@ref) for an exhaustive explanation of the available tokens.
Here are some simple examples to get you started:
```julia
configPath("max_time")
configPath("full_data_interval")
configPath(<substrate_name>, "diffusion_coefficient")
configPath(<cell_type>, "cycle", "rate", 0)
configPath(<cell_type>, "speed")
configPath(<cell_type>, "custom", <tag>)
configPath("user_parameters", <tag>)
```

[^1]: Intracellular parameters are not supported (yet). Others may also be missing. If the [`configPath`](@ref) function does not recognize the tokens you pass it, it will throw an error showing the available tokens (for the given number of tokens you passed).