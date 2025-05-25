"""
    processIncludeCellTypes(include_cell_type_names, all_cell_types::Vector{String})

Process the `include_cell_type_names` argument to ensure it is in the correct format.

Uses the `all_cell_types` vector to determine the valid cell types.

# Arguments
- `include_cell_type_names`: the cell types to include in the analysis (default is `:all_in_one`). Full list of options:
    - `:all` - return the vector of all cell types
    - `:all_in_one` - return a vector with a single element, which is a vector of all cell types
    - `"cell_type_1"` - return ["cell_type_1"]
    - `["cell_type_1", "cell_type_2"]` - return ["cell_type_1", "cell_type_2"]
    - `[["cell_type_1", "cell_type_2"]]` - return [["cell_type_1", "cell_type_2"]]
    - `[["cell_type_1", "cell_type_2"], "cell_type_3"]` - return [["cell_type_1", "cell_type_2"], "cell_type_3"]
- `all_cell_types`: a vector of all cell types in the simulation
"""
function processIncludeCellTypes(include_cell_type_names, all_cell_types::Vector{String})
    if include_cell_type_names isa Symbol
        #! include_cell_type_names = :all
        if include_cell_type_names == :all
            return all_cell_types
        elseif include_cell_type_names == :all_in_one
            return [all_cell_types]
        end
        throw(ArgumentError("include_cell_type_names must be :all or :all_in_one if a symbol. Got $include_cell_type_names."))
    elseif include_cell_type_names isa String
        #! include_cell_type_names = "cancer"
        return [include_cell_type_names]
    elseif include_cell_type_names isa AbstractVector{<:AbstractString}
        #! include_cell_type_names = ["cancer", "immune"]
    elseif include_cell_type_names isa AbstractVector
        #! include_cell_type_names = [["cancer_epi", "cancer_mes"], "immune"]
        @assert isa.(include_cell_type_names, Union{String,AbstractVector{<:AbstractString}}) |> all "include_cell_type_names must consist of strings and vectors of strings."
    else
        throw(ArgumentError("If listing all cell types to include, use either 1) a string or 2) a vector consisting of strings and vectors of strings. Got $(typeof(include_cell_type_names))."))
    end
    return include_cell_type_names
end

"""
    processExcludeCellTypes(exclude_cell_type_names)

Process the `exclude_cell_type_names` argument to ensure it is in the correct format.

If `exclude_cell_type_names` is a string, it is converted to a single-element vector.
If it is a vector, it is returned as is.
"""
function processExcludeCellTypes(exclude_cell_type_names)
    if exclude_cell_type_names isa String
        return [exclude_cell_type_names]
    elseif exclude_cell_type_names isa AbstractVector{<:AbstractString}
        return exclude_cell_type_names
    end
    throw(ArgumentError("exclude_cell_type_names must be a string or a vector of strings."))
end