# Setting up your project repository

To set up your pcvct-enabled repository within `project-dir` (the name of your project directory), create the following directory structure:

```
project-dir/
├── data/
│   └── inputs/
│       ├── configs/
│       ├── custom_codes/
│       ├── ics/
│       │   ├── cells/
│       │   ├── ecms/
│       │   └── substrates/
│       ├── rulesets_collections/
└── VCT/
```

## Setting up the `data/inputs/` directory

Within each of the terminal subdirectories above within `data/inputs/`, add a subdirectory with a user-defined name with content described below.
We will use the name `"default"` for all as an example.

### Configs

Add a single file within `data/inputs/configs/default/` called `PhysiCell_settings.xml` with the base configuration file for your PhysiCell project.

### Custom codes

Add within `data/inputs/custom_codes/default/` the following, each exactly as is used in a PhysiCell project:
- `main.cpp`
- `Makefile`
- `custom_modules/`

### ICs

These folders are optional as not every model includes initial conditions as separate files.
If your model does, for each initial condition add a subfolder.
For example, if you have two initial cell position conditions, `random_cells.csv` and `structured_cells.csv`, the `data/inputs/ics/cells/` directory would look like this:
```
cells/
├── random_cells/
│   └── cells.csv
└── structured_cells/
    └── cells.csv
```
**Note:** Place the files in their corresponding folders and rename to `cells.csv`.

Proceed similarly for `ecms/` and `substrates/`, renaming those files to `ecm.csv` and `substrates.csv` respectively.

### Rulesets collections

Add a single file within `data/inputs/rulesets_collections/default/` called `base_rulesets.csv` with the base ruleset collection for your PhysiCell project.
If your project does not use rules, you can skip this step.