println("make.jl: pwd = $(pwd())")
println("make.jl: @__DIR__ = $(@__DIR__)")

using pcvct
using Documenter

DocMeta.setdocmeta!(pcvct, :DocTestSetup, :(using pcvct); recursive=true)

makedocs(;
    modules=[pcvct],
    authors="Daniel Bergman <danielrbergman@gmail.com> and contributors",
    sitename="pcvct.jl",
    format=Documenter.HTML(;
        canonical="https://drbergman.github.io/pcvct.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/drbergman/pcvct.jl",
    devbranch="main",
)
