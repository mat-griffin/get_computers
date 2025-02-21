# get_computers.sh

## Description
DISCLAIMER - Use at your own risk. Always test on a non production server.
`get_computers.sh` is a (very long!) EXPERIMENTAL Bash script that retrieves Mac device information from Jamf Pro using Advanced Computer Search groups in the Terminal. It supports various operations including viewing device status, OS distribution, and sending DDM updates. It uses Jamf API roles and clients for authentication so requires a Client ID and Client secret (see requirements)

On first run (see setup_1.png & setup_2.png) you will be asked to enter:
- Jamf Pro URL 
- Client ID
- Client Secret

![setup_1](https://github.com/user-attachments/assets/11dc4a24-8072-41da-99ea-13e860ac09d0)

![setup_2](https://github.com/user-attachments/assets/010edb93-29b0-473a-881a-e9848fc43ad6)

You can set the Advanced search group ID, if not set it will default to 113.
Details are stored in /.jamf_credentials 

## Features
- Retrieve device information from Jamf Pro (see jamf_data.png)
- View OS version distribution
- List outdated systems
- Show inactive machines
- Export data to CSV
- Search by username/email
- Send DDM updates

![jamf_data](https://github.com/user-attachments/assets/7a114ff6-80ce-4193-aa41-1d4f80b08a50)


## Requirements
- Bash
- `curl`
- `jq`
- Jamf Pro API (API roles and clients) credentials (see jamf_API_roles_and_clients.png) with the following privileges:
  - Read Advanced Computer Searches
  - Read Computers
  - Send Computer Remote Command to Download and Install OS X Update
  - Read Managed Software Updates
  - Create Managed Software Updates

![jamf_API_roles_and_clients](https://github.com/user-attachments/assets/f1c327b2-78d3-42e8-aba1-7fd6410b59c5)


## Installation
1. Clone the repository:
    ```sh
    git clone https://github.com/yourusername/get_computers.git
    cd get_computers
    ```

2. Make the script executable:
    ```sh
    chmod +x get_computers.sh
    ```

## Usage
Options
```
-d : Enable debug mode for detailed logging
-i search_id : Specify Jamf Pro Advanced Computer Search ID (default: 113)
-h : Show help message
```

Examples
Run with default search ID
`./get_computers.sh`

Run in debug mode:
`./get_computers.sh -d`

Run with a different search ID:
`./get_computers.sh -i 276`

Run in debug mode with a custom search ID:
`./get_computers.sh -d -i 276`

License
This project is licensed under the MIT License. See the LICENSE file for details.

Author
Mat Griffin

Run at your own risk.
Always test on a non production server
