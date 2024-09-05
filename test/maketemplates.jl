using PkgTemplates
Codecov()
tpl = Template(plugins=[GitHubActions(), Documenter{GitHubActions}()])