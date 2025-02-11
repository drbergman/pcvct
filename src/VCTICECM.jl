using PhysiCellECMCreator

"""
    createICECMXMLTemplate(folder::String)

Create folder with a template XML file for IC ECM.

See the PhysiCellECMCreator.jl documentation for more information on IC ECM and how this function works outside of pcvct.
This pcvct function runs the `createICECMXMLTemplate` function from PhysiCellECMCreator.jl and then reinitializes the database.
Furthermore, the folder can be passed in just as the name of the folder located in `data/inputs/ics/ecms/` rather than the full path.

This functionality is run outside of a PhysiCell runtime.
It will not work in PhysiCell!
This function creates a template XML file for IC ECM, showing all the current functionality of this initialization scheme.
The `ID` attribute in `patch` elements is there to allow variations to target specific patches within a layer.
Manually maintain these or you will not be able to vary specific patches effectively.

Each time a simulation is run that is using a ecm.xml file, a new CSV file will be created.
These will all be stored with `data/inputs/ics/ecms/folder/ic_ecm_variations` as `ic_ecm_variation_#_s#.csv` where the first `#` is the variation ID associated with variation on the XML file and the second `#` is the simulation ID.
Importantly, no two simulations will use the same CSV file.
"""
function createICECMXMLTemplate(folder::String)
    if length(splitpath(folder)) == 1
        # then the folder is just the name of the ics/ecms/folder folder
        folder = joinpath(data_dir, "inputs", "ics", "ecms", folder)
    end
    PhysiCellECMCreator.createICECMXMLTemplate(folder)
    reinitializeDatabase()
end