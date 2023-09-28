
# function initializeVariation_FunnyOutput(patient_id::Int, xml_paths::Vector{Vector{String}}, new_values::Vector{Vector{T}} where {T<:Real}; reference_variation::Int=0)
#     if length(xml_paths)==1
#         return initializeVariation(patient_id, xml_paths[1], new_values[1]; reference_variation=reference_variation)
#     end
#     for new_value_last_dim in new_values[end]
#         table_name, default_values, table_features = setupVariation(patient_id, xml_paths[end]; reference_variation=reference_variation)
#         new_variation_id = addVariationRow(table_name, table_features, default_values, new_value_last_dim)
#         initializeVariation(patient_id, xml_paths[1:end-1], new_values[1:end-1]; reference_variation=new_variation_id)
#     end
#     return nothing
# end

# function initializeVariation(patient_id::Int, xml_paths::Vector{Vector{String}}, new_values::Vector{Vector{T}} where {T<:Real}; reference_variation::Int=0)
#     if length(xml_paths)==1
#         return initializeVariation(patient_id, xml_paths[1], new_values[1]; reference_variation=reference_variation)
#     end
#     for xml_path in xml_paths
#         setupVariation(patient_id, xml_path; reference_variation=reference_variation)
#     end
#     for new_value_last_dim in new_values[1]
#         table_name, default_values, table_features = setupVariation(patient_id, xml_paths[1]; reference_variation=reference_variation)
#         new_variation_id = addVariationRow(table_name, table_features, default_values, new_value_last_dim)
#         initializeVariation(patient_id, xml_paths[2:end], new_values[2:end]; reference_variation=new_variation_id)
#     end
#     return nothing
# end

# function initializeVariation(patient_id::Int, xml_path::Vector{String}, new_values::Vector{T} where {T<:Real}; reference_variation::Int=0)
#     table_name, default_values, table_features = setupVariation(patient_id, xml_path; reference_variation=reference_variation)
#     for new_value in new_values
#         addVariationRow(table_name, table_features, default_values, new_value)
#     end
#     return nothing
# end

# function setupVariation(patient_id::Int, xml_path::Vector{String}; reference_variation::Int=0)
#     table_name = "patient_variations_$(patient_id)"
#     column_names = DBInterface.execute(db, "PRAGMA table_info($(table_name));") |> DataFrame |> x->x[!,:name]
#     filter!(x->x!="variation_id",column_names)
#     varied_column_name = join(xml_path,"/")
#     if !(varied_column_name in column_names)
#         addVariationColumn(patient_id, table_name, varied_column_name, xml_path, column_names)
#     else
#         filter!(x -> x != varied_column_name, column_names) # in case the varied column name already is in the table, remove it from the list for now so the default value does not get added
#     end

#     default_row_df = VCTDatabase.selectRow(table_name, "WHERE variation_id=$(reference_variation)")
#     if isempty(column_names)
#         default_values = ""
#     else
#         default_values = default_row_df[1,column_names] |> Vector .|> string .|> (x->x*",") |> join
#     end
#     push!(column_names, varied_column_name) 
#     column_names = "\"" .* column_names .* "\""
    
#     return table_name, default_values, table_features
# end

# function addVariationColumn(patient_id::Int, table_name::String, varied_column_name::String, xml_path::Vector{String}, column_names::Vector{String})
#     DBInterface.execute(db, "ALTER TABLE $(table_name) ADD COLUMN '$(varied_column_name)' TEXT;")
#     path_to_xml = VCTDatabase.selectRow("path", "folders", "WHERE patient_id=$(patient_id) AND cohort_id=$(VCTModule.control_cohort_id)")
#     path_to_xml *= "/config/PhysiCell_settings.xml"
#     VCTConfiguration.openXML(path_to_xml)
#     default_value = VCTConfiguration.getField(xml_path)
#     DBInterface.execute(db, "UPDATE $(table_name) SET '$(varied_column_name)'=$(default_value);")
#     VCTConfiguration.closeXML()

#     index_name = table_name * "_index"
#     SQLite.dropindex!(db, index_name; ifexists=true) # remove previous index
#     index_columns = deepcopy(column_names)
#     push!(index_columns, varied_column_name)
#     SQLite.createindex!(db, table_name, index_name, index_columns; unique=true, ifnotexists=false) # add new index to make sure no variations are repeated
#     return nothing
# end

# function addVariationColumn(patient_id::Int, table_name::String, varied_column_name::String, column_names::Vector{String})
#     xml_path = split(xml_path,"/") .|> string
#     return addVariationColumn(patient_id, table_name, varied_column_name, xml_path, column_names)
# end