using Documenter, pcvct

DocMeta.setdocmeta!(pcvct, :DocTestSetup, :(using pcvct); recursive=true)

makedocs(;
    modules=[pcvct],
    authors="Daniel Bergman <danielrbergman@gmail.com> and contributors",
    sitename="pcvct",
    format=Documenter.HTML(;
        canonical="https://drbergman.github.io/pcvct",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
        "Manual" => Any[
            "Best practices" => "man/best_practices.md",
            "Getting started" => "man/getting_started.md",
            "Data directory" => "man/data_directory.md",
            "Known limitations" => "man/known_limitations.md",
            "PhysiCell Studio" => "man/physicell_studio.md",
        ],
        "Documentation" => map(
            s -> "lib/$(s)",
            sort(readdir(joinpath(@__DIR__, "src/lib")))
        ),
        "Miscellaneous" => Any[
            "Renaming" => "misc/renaming.md",
        ],
    ],
)

deploydocs(;
    repo="github.com/drbergman/pcvct",
    devbranch="test-doc-updates",
    push_preview=true,
)
