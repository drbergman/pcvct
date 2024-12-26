filename = @__FILE__
filename = split(filename, "/") |> last
str = "TESTING WITH $(filename)"
hashBorderPrint(str)

config_folder = "0_template"
custom_code_folder = "0_template"
rulesets_collection_folder = "0_template"
ic_cell_folder = "0_template"
inputs = InputFolders(config_folder, custom_code_folder; rulesets_collection=rulesets_collection_folder, ic_cell=ic_cell_folder)

simulation = Simulation(inputs)
@test simulation isa Simulation

simulation = Simulation(1)
@test simulation isa Simulation

monad = Monad(1)
@test monad isa Monad

monad_min_length = 1
config_variation_ids = [1, 2]
rulesets_variation_ids = [1, 1]
ic_cell_variation_ids = [0, 0]
sampling = Sampling(inputs;
    monad_min_length=monad_min_length,
    config_variation_ids=config_variation_ids,
    rulesets_variation_ids=rulesets_variation_ids,
    ic_cell_variation_ids=ic_cell_variation_ids
)
@test sampling isa Sampling

trial = Trial(1)
@test trial isa Trial

samplings = [Sampling(1), Sampling(2)]
@test all(typeof.(samplings) .== Sampling)

trial = Trial(samplings)
@test trial isa Trial