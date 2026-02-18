# Azure DevOps Pipeline Setup Guide

Quick reference for setting up and using the VPN Connection deployment pipeline.

## Initial Setup

### 1. Create Service Connection

In Azure DevOps:
1. Go to **Project Settings** → **Service connections**
2. Click **New service connection** → **Azure Resource Manager**
3. Choose **Service principal (automatic)**
4. Select your subscription and resource group
5. Name it (e.g., `azure-network-prod`)
6. Grant **Contributor** or **Network Contributor** permissions

### 2. Create Environment

1. Go to **Pipelines** → **Environments**
2. Click **New environment**
3. Name: `production-network`
4. Add approvals (recommended for production)
5. Configure checks and gates as needed

### 3. Update Pipeline Variables

Edit `azure-pipelines.yml` and update:

```yaml
variables:
  azureSubscription: 'your-service-connection-name'  # From step 1
  resourceGroupName: 'rg-network-prod-001'          # Your resource group
  location: 'westeurope'                            # Your Azure region
```

### 4. Import Pipeline

```bash
# Using Azure CLI
az pipelines create \
  --name "Deploy VPN Connections" \
  --repository GetToTheCloud/Website \
  --branch main \
  --yml-path AzureBicep-AzureLandingZone-AddVPNConnection/azure-pipelines.yml
```

Or use Azure DevOps UI:
1. **Pipelines** → **New pipeline**
2. Select your repository
3. Choose **Existing Azure Pipelines YAML file**
4. Select `AzureBicep-AzureLandingZone-AddVPNConnection/azure-pipelines.yml`

## Pipeline Stages

### Stage 1: Validate (5 minutes)
- ✅ Bicep build and syntax check
- ✅ ARM template validation
- ✅ What-If deployment analysis
- ✅ VPN Gateway existence check
- ✅ Publish artifacts

### Stage 2: Deploy (10-15 minutes)
- 🚀 Deploy Local Network Gateways
- 🚀 Create VPN Connections
- 📊 Display deployment outputs
- ⏸️ Environment approval gate (if configured)

### Stage 3: Verify (2 minutes)
- ✔️ Verify Local Network Gateways
- ✔️ Check VPN Connection status
- 📋 Generate deployment report
- 📄 Publish summary

**Total Runtime**: ~15-20 minutes

## Running the Pipeline

### Automatic Triggers

The pipeline runs automatically when:
- Code is pushed to `main` branch
- Files change in `AzureBicep-AzureLandingZone-AddVPNConnection/` folder
- Pull request targets `main` branch

### Manual Execution

1. Go to **Pipelines** → Select pipeline
2. Click **Run pipeline**
3. Select branch (usually `main`)
4. Click **Run**

### With Parameter Override

```bash
# Run with specific parameters
az pipelines run \
  --name "Deploy VPN Connections" \
  --branch main \
  --variables resourceGroupName=rg-network-test-001
```

## Monitoring

### View Live Logs

1. Click on running pipeline
2. Select stage (Validate/Deploy/Verify)
3. Click on job to see detailed logs

### Check Connection Status

After deployment:
```bash
# Azure CLI
az network vpn-connection list \
  --resource-group rg-network-prod-001 \
  --output table

# PowerShell
Get-AzVirtualNetworkGatewayConnection `
  -ResourceGroupName rg-network-prod-001 |
  Select-Object Name, ConnectionStatus, ProvisioningState
```

## Troubleshooting

### Issue: Service Connection Permissions

**Error**: `Authorization failed`

**Solution**:
```bash
# Add role assignment
az role assignment create \
  --assignee <service-principal-id> \
  --role "Network Contributor" \
  --scope /subscriptions/<sub-id>/resourceGroups/rg-network-prod-001
```

### Issue: VPN Gateway Not Found

**Error**: `No VPN Gateway found in resource group`

**Solution**: Verify gateway exists:
```bash
az network vnet-gateway list \
  --resource-group rg-network-prod-001 \
  --output table
```

Update `virtualNetworkGatewayName` in parameters file.

### Issue: Deployment Timeout

**Error**: Pipeline times out during deployment

**Solution**: VPN connections can take 10-15 minutes to establish.
- Increase pipeline timeout in YAML
- Check Azure Portal for resource status
- Review deployment logs

### Issue: Connection Shows "NotConnected"

Check:
1. Shared key matches on both sides
2. Remote device is configured
3. Firewall allows IPsec traffic
4. IP addresses are correct

## Security Best Practices

### Protected Parameters

Store sensitive values as pipeline variables:

1. **Pipelines** → Select pipeline → **Edit** → **Variables**
2. Add variable: `vpnSharedKey`
3. Check **Keep this value secret**
4. Reference in parameter file override

### Key Vault Integration

Link variable group to Key Vault:

1. **Pipelines** → **Library** → **Variable groups**
2. **+ Variable group**
3. Enable **Link secrets from Azure Key Vault**
4. Select your Key Vault
5. Add secrets to pipeline

In `azure-pipelines.yml`:
```yaml
variables:
  - group: 'vpn-secrets'

steps:
  - task: AzurePowerShell@5
    inputs:
      Inline: |
        # Use Key Vault secret
        $sharedKey = "$(vpn-shared-key)"
```

## Pipeline Customization

### Add Email Notifications

```yaml
- task: SendEmail@1
  displayName: 'Send Deployment Notification'
  condition: always()
  inputs:
    to: 'network-team@company.com'
    subject: 'VPN Deployment: $(deploymentName)'
    body: 'Deployment completed. Status: $(Agent.JobStatus)'
```

### Add Slack/Teams Notification

```yaml
- task: InvokeRESTAPI@1
  displayName: 'Post to Teams Channel'
  inputs:
    connectionType: 'connectedServiceName'
    serviceConnection: 'teams-webhook'
    method: 'POST'
    body: |
      {
        "text": "VPN Connection deployed: $(deploymentName)"
      }
```

### Add Approval Gates

In environment settings:
1. Go to environment `production-network`
2. **Approvals and checks** → **+** → **Approvals**
3. Add approvers
4. Set timeout
5. Save

## Rollback Procedure

If deployment fails or connections have issues:

```bash
# Remove faulty connection
az network vpn-connection delete \
  --resource-group rg-network-prod-001 \
  --name connection-name

# Remove Local Network Gateway
az network local-gateway delete \
  --resource-group rg-network-prod-001 \
  --name lng-name

# Or run pipeline with corrected parameters
```

## Artifacts

Pipeline generates:
- **bicep-templates**: Compiled templates and parameters
- **deployment-report**: Summary and documentation

Access via: **Pipeline run** → **Published artifacts**

## Useful Commands

```bash
# View pipeline runs
az pipelines runs list --pipeline-name "Deploy VPN Connections"

# Show specific run
az pipelines runs show --id <run-id>

# Cancel running pipeline
az pipelines runs cancel --run-id <run-id>

# Download artifacts
az pipelines runs artifact download \
  --artifact-name deployment-report \
  --run-id <run-id> \
  --path ./reports
```

## Additional Resources

- [Azure Pipelines YAML Schema](https://learn.microsoft.com/azure/devops/pipelines/yaml-schema)
- [Azure DevOps Service Connections](https://learn.microsoft.com/azure/devops/pipelines/library/service-endpoints)
- [Pipeline Environments](https://learn.microsoft.com/azure/devops/pipelines/process/environments)
- [VPN Gateway Documentation](https://learn.microsoft.com/azure/vpn-gateway/)

---

**Last Updated**: February 2026
