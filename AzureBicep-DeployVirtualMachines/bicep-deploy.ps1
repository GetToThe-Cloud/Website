$LocationName = "westeurope"
$ResourceGroupName = "TestDomain"

## creating resource group
Try {
    $newGroup = New-AzResourceGroup -Name $ResourceGroupName -Location $LocationName -InformationAction SilentlyContinue
    Write-host "[SUCCESS] Resource Group is created with the name $($ResourceGroupName)" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Creating Resource group" -ForegroundColor Red
}

# creating deployment name
$date = Get-Date -Format "MM-dd-yyyy"
$rand = Get-Random -Maximum 1000
$deploymentName = "DeploymentDC-" + "$date" + "-" + "$rand"

# starting deployment
New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $ResourceGroupName -TemplateFile "C:\Users\Alex ter Neuzen\OneDrive - Buzz ICT\Github\development\GetToTheCloud\AzureBicep\DeployVirtualMachines\DC.bicep" -TemplateParameterFile "C:\Users\Alex ter Neuzen\OneDrive - Buzz ICT\Github\development\GetToTheCloud\AzureBicep\DeployVirtualMachines\azuredeploy.parameters.json" 

New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $ResourceGroupName -TemplateFile "C:\Users\Alex ter Neuzen\OneDrive - Buzz ICT\Github\development\GetToTheCloud\AzureBicep\DeployVirtualMachines\EX.bicep" -TemplateParameterFile "C:\Users\Alex ter Neuzen\OneDrive - Buzz ICT\Github\development\GetToTheCloud\AzureBicep\DeployVirtualMachines\azuredeploy.parameters.json"
New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $ResourceGroupName -TemplateFile "C:\Users\Alex ter Neuzen\OneDrive - Buzz ICT\Github\development\GetToTheCloud\AzureBicep\DeployVirtualMachines\WIN11.bicep" -TemplateParameterFile "C:\Users\Alex ter Neuzen\OneDrive - Buzz ICT\Github\development\GetToTheCloud\AzureBicep\DeployVirtualMachines\azuredeploy.parameters.json"