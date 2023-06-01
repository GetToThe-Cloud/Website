# ![Terraform](https://img.shields.io/badge/terraform-%235835CC.svg?style=for-the-badge&logo=terraform&logoColor=white) Azure Virtual Desktop deployment

Read more about these files at the website: https://www.gettothe.cloud

# Usage
```powershell
terraform init
```
```powershell
terraform plan
```
```powershell
terraform deploy
```

## Functions

The module contains multiple functions. 

<!-- TABLE OF CONTENTS -->
<details open>
  <summary>Table of Contents</summary>
  <ol>
    <li>
      Module Management
      <ul>
        <li><a href="#install-requirements">Install-Requirements</a></li>
        <li><a href="#Update-RequiredModules">Update-RequiredModules</a></li>
        <li><a href="#Update-RapidCircleModule">Update-RapidCircleModule</a/</li>
      </ul>
    </li>
    <li>
      Azure Active Directory
      <ul>
        <li><a href="#Get-ConditionalAccessPolicies">Get-ConditionalAccessPolicies</a></li>
        <li><a href="#Import-ConditionalAccessPolicies">Import-ConditionalAccessPolicies</a></li>
      </ul>
    </li>    
        <li>
      Tools
      <ul>
        <li><a href="#New-Password">New-Password</a></li>
      </ul>
    </li>   
  </ol>
</details>

### Install-Requirements

The "Install-Requirements" function checks for the presence and version of required PowerShell modules, prompts for installation if missing, and imports the modules.

The function defines an array named "$modules" that contains the names of the required modules: 
- ExchangeOnlineManagement
- Microsoft.Graph
- Microsoft.Online.SharePoint.PowerShell
- MicrosoftTeams
- ImportExcel

 It then retrieves the list of installed modules using the "Get-InstalledModule" cmdlet.

For each module in the "$modules" array, the function checks if it is already installed. If the module is installed, it retrieves the installed module details and displays a message indicating that it is installed along with its version. It also checks if there is a newer version available and notifies accordingly.

If the module is not installed, the function displays a message indicating that it is not installed and checks if there is a newer version available. If a newer version is found, it prompts for installation, attempts to install the latest version using the "Install-Module" cmdlet, and displays the installation status.

The function iterates through all the modules in the "$modules" array, performs the necessary checks and installations, and provides status updates for each module.

No output is explicitly returned from this function.
<p align="right">(<a href="#Rapid-Circle-PowerShell-Module">back to top</a>)</p>

### Update-RequiredModules
The "Update-RequiredModules" function checks for updates of specific PowerShell modules and performs the necessary updates, optionally removing old versions of the modules.

The function defines several parameters:

-   "SkipMajorVersion": A switch parameter that skips major version updates if specified.
-   "KeepOldModuleVersions": A switch parameter that keeps old module versions if specified.
-   "ExcludedModulesforRemoval": An array parameter that specifies modules to exclude from removal.

The function starts by defining an array named "$modules" containing the names of the required modules to update. It then retrieves all installed modules that have a newer version available from the PSGallery repository.

For each module in the "$CurrentModules" array, the function checks if there is a newer version available in the PSGallery repository. If a newer version is found, it performs the following steps:

-   If "SkipMajorVersion" is specified and the gallery version has a higher major version number, it skips the update and displays a warning.
-   If the update is not skipped, it prompts for confirmation using the "ShouldProcess" cmdlet and updates the module using the "Update-Module" cmdlet.
-   If "KeepOldModuleVersions" is not specified, it removes the old versions of the module using the "Uninstall-Module" cmdlet. However, if the module is listed in the "ExcludedModulesforRemoval" array, it skips the removal and displays a manual check message.

The function provides status updates for each module, including the update or removal actions performed.

No output is explicitly returned from this function.
<p align="right">(<a href="#Rapid-Circle-PowerShell-Module">back to top</a>)</p>

### Update-RapidCircleModule
The "Update-RapidCircleModule" PowerShell function updates the RapidCircle module by retrieving the latest release from a specified GitHub repository. It then downloads the module file and imports it into the current PowerShell session. 

The function begins by defining the GitHub repository and the URL to retrieve the releases. It determines the latest release by accessing the JSON response from the GitHub API. The function constructs the download URL for the module file based on the latest release tag. 
It proceeds to download the file using Invoke-RestMethod and saves it to a specified output folder. If the download is successful, the function displays a success message; otherwise, it displays an error message. 

Next, it checks if the downloaded file exists in the output folder and verifies its presence. If the file is found, it imports the module using Import-Module. This function provides a convenient way to update the RapidCircle module by automating the process of downloading and importing the latest release.
<p align="right">(<a href="#Rapid-Circle-PowerShell-Module">back to top</a>)</p>


###  New-Password

The "New-Password" function generates a random password based on the specified requirements. It takes four mandatory parameters:

-   "LowCharacters": An integer specifying the number of lowercase characters in the password.
-   "CapitalCharacters": An integer specifying the number of uppercase characters in the password.
-   "Numbers": An integer specifying the number of numeric characters in the password.
-   "SpecialCharacters": An integer specifying the number of special characters in the password.

```powershell
New-Password -LowCharacters [number] -CapitalCharacters [number] -Numbers [number] -SpecialCharacters [number]
```

The function internally defines two helper functions:

-   "Get-RandomCharacters": Generates a random string of specified length from a given set of characters.
-   "Scramble-String": Randomizes the order of characters in a given string.

The function combines random characters from different character sets to create the password. It uses the helper function "Get-RandomCharacters" to generate random characters from specific character sets: lowercase letters, uppercase letters, numbers, and special characters. It then concatenates these random characters together to form the password. Finally, it calls the "Scramble-String" function to randomize the order of characters in the password.

The generated password is returned as the output of the function.
<p align="right">(<a href="#Rapid-Circle-PowerShell-Module">back to top</a>)</p>

### Get-ConditionalAccessPolicies
The "Get-ConditionalAccessPolicies" function retrieves conditional access policies and named locations from Microsoft Graph using PowerShell. It exports the data to JSON files in a specified folder.

The function requires the following parameter:

-   "ExportPath": A mandatory parameter specifying the path where the JSON files will be exported.

```powershell
Get-ConditionalAccessPolicies -ExportPath [your unc path]
```

The function connects to the Microsoft Graph API using the "Connect-MGGraph" cmdlet with the "Policy.read.all" delegated permission.

It sets the URLs for retrieving conditional access policies and named locations from the Graph API.

The function then retrieves the conditional access policies and named locations using the "Invoke-MGGraphRequest" cmdlet.

After successful retrieval, it processes the conditional access policies and exports each policy to a JSON file. The policy JSON file is named based on the policy's display name. If the display name contains forward slashes ("/"), they are replaced with hyphens ("-"). If the name contains square brackets ("]"), the name is split at the "]" and uses the second part as the name. The exported JSON file is cleaned by removing specific properties using the "Select-String" cmdlet.

Similarly, the function exports each named location to a JSON file. The JSON file is named based on the named location's display name. The exported JSON file is also cleaned by removing specific properties.

The function provides information and status messages during the export process.

No output is explicitly returned from this function.
<p align="right">(<a href="#Rapid-Circle-PowerShell-Module">back to top</a>)</p>

### Import-ConditionalAccessPolicies
The "Import-ConditionalAccessPolicies" function imports conditional access policies and named locations from JSON files to Microsoft Graph using PowerShell.

The function requires the following parameter:

-   "ImportPath": A mandatory parameter specifying the path to the folder containing the JSON files to import.

```powershell
Import-ConditionalAccessPolicies -ImportPath [your unc path]
```

The function connects to the Microsoft Graph API using the "Connect-MGGraph" cmdlet with the "Policy.ReadWrite.ConditionalAccess", "Policy.read.all", and "Application.read.all" delegated permissions.

It sets the URLs for retrieving conditional access policies and named locations from the Graph API.

The function retrieves existing conditional access policies and named locations using the "Invoke-MGGraphRequest" cmdlet.

After retrieving the necessary information, the function processes the JSON files in the specified import path. It filters the JSON files based on their names, expecting policy files to start with "CA - Policy - " and named location files to start with "Location - ".

For each named location file, the function checks if the named location already exists in the Azure Active Directory. If it exists, the named location is skipped. If it doesn't exist, the function creates the named location using the "Invoke-MGGraphRequest" cmdlet with a POST request.

Similarly, for each policy file, the function checks if the policy already exists in the conditional access policies. If it exists, the policy is skipped. If it doesn't exist, the function creates the policy using the "Invoke-MGGraphRequest" cmdlet with a POST request.

The function provides information and status messages during the import process.

No output is explicitly returned from this function.
<p align="right">(<a href="#Rapid-Circle-PowerShell-Module">back to top</a>)</p>

## Roadmap

- [ ] Add release of version
- [ ] Exchange Online Inventory
- [ ] Security Assessment Azure Active Directory
- [ ] Rapid Circle security baseline inventory and apply

<!-- CONTACT -->
## Contact

Alex ter Neuzen - alex.terneuzen@rapidcircle.com


<p align="right">(<a href="#Rapid-Circle-PowerShell-Module">back to top</a>)</p>

[powershell]: https://img.shields.io/badge/module-Powershell-blue?style=for-the-badge&logo=PowerShell&logoColor=4FC08D
[powershell-url]: https://learn.microsoft.com/en-gb/powershell/scripting/overview?view=powershell-7.3