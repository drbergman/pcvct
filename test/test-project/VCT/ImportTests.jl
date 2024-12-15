filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

path_to_project = "./test-project/PhysiCell/sample_projects/immune_function"

dest = Dict()
config_folder = "immune_sample"
dest["config"] = config_folder

src = Dict()
src["config"] = "PhysiCell_settings.xml"
success = importProject(path_to_project, src, dest)
@test success

custom_code_folder = rulesets_collection_folder = ic_cell_folder = "immune_function"

EV = ElementaryVariation[]
push!(EV, ElementaryVariation(["overall","max_time"], [12.0]))
push!(EV, ElementaryVariation(["save","full_data","interval"], [6.0]))
push!(EV, ElementaryVariation(["save","SVG","interval"], [6.0]))

config_variation_ids, rulesets_variation_ids, ic_cell_variation_ids = addVariations(GridVariation(), config_folder, rulesets_collection_folder, ic_cell_folder, EV)

sampling = Sampling(config_folder, custom_code_folder;
    monad_min_length=1,
    rulesets_collection_folder=rulesets_collection_folder,
    ic_cell_folder=ic_cell_folder,
    config_variation_ids=config_variation_ids,
    rulesets_variation_ids=rulesets_variation_ids,
    ic_cell_variation_ids=ic_cell_variation_ids
)

n_success = run(sampling; force_recompile=false)

@test n_success == length(sampling)

success = importProject(path_to_project, src, dest)
@test success
@test isdir(joinpath(pcvct.data_dir, "inputs", "configs", "immune_sample_1"))

src["rules"] = "not_rules.csv"
success = importProject(path_to_project, src, dest)
@test !success

path_to_fake_project = joinpath("test-project", "PhysiCell", "sample_projects", "not_a_project")
success = importProject(path_to_fake_project)
@test !success

path_to_project = joinpath("test-project", "PhysiCell", "sample_projects", "template")
success = importProject(path_to_project)
@test success

# intentionally sabotage the import
path_to_bad_project = joinpath("test-project", "PhysiCell", "sample_projects", "bad_template")
cp(path_to_project, "./test-project/PhysiCell/sample_projects/bad_template")

path_to_main = joinpath("test-project", "PhysiCell", "sample_projects", "bad_template", "main.cpp")
lines = readlines(path_to_main)
idx = findfirst(x->contains(x, "argument_parser"), lines)
lines[idx] = "    //no longer parsing because this is now a bad project"
open(path_to_main, "w") do f
    for line in lines
        println(f, line)
    end
end

path_to_custom_cpp = joinpath("test-project", "PhysiCell", "sample_projects", "bad_template", "custom_modules", "custom.cpp")
lines = readlines(path_to_custom_cpp)
idx = findfirst(x->contains(x, "load_initial_cells"), lines)
lines[idx] = "    //no longer loading initial cells because this is now a bad project"
open(path_to_custom_cpp, "w") do f
    for line in lines
        println(f, line)
    end
end

success = importProject(path_to_bad_project)
@test !success

