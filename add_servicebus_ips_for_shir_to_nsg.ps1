# The documentation of Synapse self hosted integration runtime (SHIR) mentions that the SHIR requires access to the Azure Service Bus IP addresses
# https://learn.microsoft.com/en-us/azure/data-factory/create-self-hosted-integration-runtime
# It is a requirement to use a wildcard (*.servicebus.windows.net) in your firewalls.
# While this is the easiest way to clear the firewall, it also opens the firewall to all Azure Service Bus IP addresses, including malicious_actor.servicebus.windows.net.
# This might be restricted by your security policies.
# This script resolves the Azure Service Bus IP addresses used by an integration runtime and adds them to the network security group (NSG) rule for the Synapse self-hosted integration runtime (SHIR).
# As the mapping of IP addresses to Domain Names might change, we recommend to run at least once a day to keep the NSG up to date.
# An alternative to running this script is to use the "Self-contained interactive authoring" feature of the self hosted integration runtime.

# Prerequisites:
# - PowerShell installed
# - Azure CLI (az) installed and logged in (https://learn.microsoft.com/en-us/cli/azure/)
# - signed in user needs rights to modify NSG (e.g. Network contributor) and to read status of the SHIR (e.g. reader), plus reader on the subscription

param (
    [string]$synapseRresourceGroupName = "synapse_test",
    [string]$nsgResourceGroupName = "adf_shir_rg",
    [string]$synapseWorkspaceName = "synapse-test-jugi2",
    [string]$integrationRuntimeName = "IntegrationRuntime2",
    [string]$networkSecurityGroupName = "jugis-shir-nsg",
    [string]$securityRuleName = "AllowSynapseServiceBusIPs",
    [int]$priority = 100
)

# Check if the user is already logged in
$azAccount = az account show 2>$null

if (-not $azAccount) {
    # Run az login with managed identity if not logged in
    az login --identity
}

# Retrieve the URLs of the connections from the Synapse self-hosted integration runtime
$urls = az synapse integration-runtime get-status `
    --resource-group $synapseRresourceGroupName `
    --workspace-name $synapseWorkspaceName `
    --name $integrationRuntimeName `
    --query "properties.serviceUrls" -o tsv

# Initialize an empty array to hold the IP addresses
$ipAddresses = @()

# Iterate over the URLs to resolve and collect the IP addresses
# The proper DNS resolution might only work within Azure, not locally
foreach ($url in $urls) {
    Write-Output "Processing URL: $url"
    $ip = [System.Net.Dns]::GetHostAddresses($url) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -ExpandProperty IPAddressToString
    if ($ip) {
        $ipAddresses += $ip
    }
}

# Remove duplicate IP addresses from the array
$ipAddresses = $ipAddresses | Sort-Object -Unique

# Convert the array of IP addresses to a space-separated string
$ipAddressesString = $ipAddresses -join ' '

# Create or update the network security group rule to allow outbound traffic for the collected IP addresses
# Using Invoke-Expression to handle the command string
$az_cmd = "az network nsg rule create --resource-group $nsgResourceGroupName --nsg-name $networkSecurityGroupName --name $securityRuleName --priority $priority --destination-address-prefixes $ipAddressesString --destination-port-ranges '443' --direction Outbound --access Allow --protocol '*' --description 'Allow outbound access to Synapse servicebus IPs'"
Invoke-Expression $az_cmd