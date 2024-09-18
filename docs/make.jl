using pcvct
using Documenter

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
            "Guide" => "man/guide.md",
        ],
        "Documentation" => map(
            s -> "lib/$(s)",
            sort(readdir(joinpath(@__DIR__, "src/lib")))
        ),
    ],
)

deploydocs(;
    repo="github.com/drbergman/pcvct",
    devbranch="main",
)
