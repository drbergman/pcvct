# Python script to download the latest release of PhysiCell

import requests

branch = "my-physicell"

# response = requests.get(f"https://api.github.com/repos/drbergman/PhysiCell/branches/{branch}")
# print(response)
# release_name_str = response.json()["name"]

remote_url = f"https://github.com/drbergman/PhysiCell/archive/refs/heads/{branch}.zip"
print("remote_url=",remote_url)
local_file = f"PhysiCell-{branch}.zip"
data = requests.get(remote_url)
with open(local_file, 'wb')as file:
  file.write(data.content)
