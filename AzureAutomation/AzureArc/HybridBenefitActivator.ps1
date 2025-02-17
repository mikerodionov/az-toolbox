Import-Module Az.ResourceGraph

function GetRequestProperties() {
    $ErrorActionPreference = 'Stop'
    # Check if the Az.Accounts module is installed
    if (-not (Get-Module Az.Accounts)) {
        Import-Module Az.Accounts
    }
    # Check if the Az.Accounts module version is at least 3.0.0
    if ([version](Get-Module Az.Accounts).Version -lt [version]"3.0.0") {
        throw "At least Az.Accounts 3.0.0 is required, please update before continuing."
    }
    # Get the current context
    $CurrentContext = Get-AzContext
    if (-not $CurrentContext) {
        throw "Not logged in. Use Connect-AzAccount to log in"
    }
    $TenantId = $CurrentContext.Tenant.Id
    $UserId = $CurrentContext.Account.Id
    if ((-not $TenantId) -or (-not $UserId)) {
        throw "Tenant not selected. Use Select-AzSubscription to select a subscription"
    }
    $Environment = $CurrentContext.Environment.Name
    $SubscriptionId = $CurrentContext.Subscription.Id
    if (-not $SubscriptionId) {
        throw "No subscription selected. Use Select-AzSubscription to select a subscription"
    }
    # Set the Resource URL based on the environment
    if ($Environment -eq "AzureUSGovernment") {
        New-Variable -Name ResourceURL -Value "https://management.core.usgovcloudapi.net" -Option Constant
    }
    else {
        New-Variable -Name ResourceURL -Value "https://management.core.windows.net" -Option Constant
    }
    # Get the access token
    $SecureToken = (Get-AzAccessToken -ResourceUrl $ResourceURL -AsSecureString).Token
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureToken)
    $Token = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    if (-not $Token) {
        throw "Missing token, please make sure you are signed in."
    }
    # Set the Authorization header
    $AuthorizationHeader = "Bearer " + $Token
    # Set the headers
    $Headers = [ordered]@{Accept = "application/json"; Authorization = $AuthorizationHeader } 
    if ($Environment -eq "AzureUSGovernment") {
        $baseurl = "https://management.usgovcloudapi.net"
    }
    else {
        $baseurl = "https://management.azure.com" 
    }
    # Return the properties in a hashtable
    return [ordered]@{
        SubscriptionId = $SubscriptionId
        Headers        = $Headers
        baseurl        = $baseurl
    }   
}
function Get-AzResourceGraph {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        $GQuery
    )
    $AzGQyueryResults = [System.Collections.ArrayList]@()
    $SkipToken = $null
    $Count = 1000
    do {
        $AzGraphResponse = (Search-AzGraph -Query $GQuery -First $Count -SkipToken $SkipToken)
        $SkipToken = $AzGraphResponse.SkipToken
        foreach ($AzGraphResponseLine in $AzGraphResponse) {
            $AzGQyueryResults.Add($AzGraphResponseLine) | Out-Null
        }
    } while ($SkipToken)
    return $AzGQyueryResults
}
# Connect to Azure if not already connected
$context = Get-AzContext -ErrorAction SilentlyContinue
if ($context -and $context.Account) {
    $SubInfo = $context
    Write-Host "`n`nALREADY logged in to Azure..." -ForegroundColor Green
    Write-Host " User: " -ForegroundColor Green -NoNewline
    Write-Host $SubInfo.Account.Id  -ForegroundColor Blue
    Write-Host " Subscription: "  -ForegroundColor Green -NoNewline
    Write-Host $SubInfo.Subscription.Name "`n" -ForegroundColor Blue
    $SubInfo = $null
}
else {
    Write-Host "`n`n------------------------ Authentication ------------------------" -ForegroundColor Green
    Write-Host "Logging in to Azure..." -ForegroundColor Green
    Connect-AzAccount
}
Write-Host " [" -ForegroundColor DarkCyan -NoNewline
Write-Host "WARMUP" -ForegroundColor Magenta -NoNewline
Write-Host "] " -ForegroundColor DarkCyan -NoNewline
Write-Host "The script is collecting Arc-enabled servers " -ForegroundColor Green
# Agent Version: Connected Machine Agent version 1.47 or higher is required.
$alluniqarcsubsquery = @"
resources
| where type == 'microsoft.hybridcompute/machines'
| extend arcagent = properties.agentVersion
| extend agentVersion = strcat_delim('.', split(arcagent, '.')[0], split(arcagent, '.')[1])
| distinct subscriptionId
"@
# Activation is not available in US Gov Virginia, US Gov Arizona, China North 2, China North 3, and China East 2.
$alluniqarcsubs = Get-AzResourceGraph -GQuery $alluniqarcsubsquery
# Check if the module  Az.ConnectedMachine is installed
Write-Host " [" -ForegroundColor DarkCyan -NoNewline
Write-Host "WARMUP" -ForegroundColor Magenta -NoNewline
Write-Host "] " -ForegroundColor DarkCyan -NoNewline
Write-Host "The script is checking if the Az.ConnectedMachine is available " -ForegroundColor Green
if (Get-Module -ListAvailable -Name Az.ConnectedMachine) {
    # Initialaze Counters 
    $TotalArcServers = 0
    $SuccededActivation = 0 
    $FailedActivation = 0
    $SkippedServer = 0
    foreach ($arcsub in $alluniqarcsubs) {
        # Set the subscription context
        $CurrentContext = Set-AzContext -SubscriptionId $arcsub.subscriptionId
        Write-Host " [" -ForegroundColor DarkCyan -NoNewline
        Write-Host $CurrentContext.Subscription.Name -ForegroundColor Green -NoNewline
        Write-Host "]" -ForegroundColor DarkCyan -NoNewline
        # Retrieve all Azure Arc-enabled machines grouped by location
        $azcmachines = Get-AzConnectedMachine | Group-Object -Property Location
        $Properties = GetRequestProperties
        foreach ($azcmachine in $azcmachines.Group) {
            if ($azcmachine.status -eq "Connected" -and $azcmachine.agentVersion -ge "1.47" -and $azcmachine.OSType -eq "Windows" -and -not $azcmachine.licenseProfile.softwareAssuranceCustomer) {
                Write-Host " [" -ForegroundColor DarkCyan -NoNewline
                Write-Host $azcmachine.Name -ForegroundColor Green -NoNewline
                Write-Host "]" -ForegroundColor DarkCyan -NoNewline
                $subscriptionId = $CurrentContext.Subscription.Id
                $resourceGroupName = $azcmachine.ResourceGroupName 
                $machineName = $azcmachine.Name
                $location = $azcmachine.Location
                $uri = [System.Uri]::new( $Properties['baseurl'] + "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.HybridCompute/machines/$machineName/licenseProfiles/default?api-version=2023-10-03-preview" )
                $contentType = "application/json"  
                $data = @{         
                    location   = $location; 
                    properties = @{ 
                        softwareAssurance = @{ 
                            softwareAssuranceCustomer = $true; 
                        }; 
                    }; 
                }
                $json = $data | ConvertTo-Json
                try {
                    $response = Invoke-RestMethod -Method PUT -Uri $uri.AbsoluteUri -ContentType $contentType -Headers $Properties['Headers'] -Body $json
                    $response.properties
                    $SuccededActivation++
                }
                catch {
                    Write-Host " [" -ForegroundColor Magenta -NoNewline
                    Write-Host "ERROR" -ForegroundColor Red -NoNewline
                    Write-Host "] " -ForegroundColor Magenta -NoNewline
                    Write-Host $_.Exception.Message -ForegroundColor Red
                    $FailedActivation++
                }
            }
            else { $SkippedServer++ }
            $TotalArcServers++
        }
        Write-Host "`n`n`t [" -ForegroundColor DarkCyan -NoNewline
        Write-Host "Arc Server" -ForegroundColor Magenta -NoNewline
        Write-Host "]" -ForegroundColor DarkCyan -NoNewline
        Write-Host $TotalArcServers -ForegroundColor Green -NoNewline
        Write-Host " [" -ForegroundColor DarkCyan -NoNewline
        Write-Host "Activated" -ForegroundColor Magenta -NoNewline
        Write-Host "]" -ForegroundColor DarkCyan -NoNewline
        Write-Host $SuccededActivation -ForegroundColor Green -NoNewline
        Write-Host " [" -ForegroundColor DarkCyan -NoNewline
        Write-Host "Failed" -ForegroundColor Magenta -NoNewline
        Write-Host "]" -ForegroundColor DarkCyan -NoNewline
        Write-Host $FailedActivation -ForegroundColor Green -NoNewline
        Write-Host " [" -ForegroundColor DarkCyan -NoNewline
        Write-Host "Skipped" -ForegroundColor Magenta -NoNewline
        Write-Host "]" -ForegroundColor DarkCyan -NoNewline
        Write-Host $SkippedServer -ForegroundColor Green
        Write-Host "`n`t Azure Arc task completed.`n`n" -ForegroundColor DarkCyan
    }
}
else {
    Write-Host "`n`nAz.ConnectedMachine" -NoNewline -ForegroundColor Green
    Write-Host " module is mandatory to run this script" -ForegroundColor Yellow
    Write-Host "`n`tTo install this module, please run:" -ForegroundColor Yellow
    Write-Host "`t > Install-Module -Name Az.ConnectedMachine -Scope CurrentUser" -ForegroundColor Yellow
    Write-Host "`t > Import-Module Az.ConnectedMachine`n" -ForegroundColor Yellow
}
