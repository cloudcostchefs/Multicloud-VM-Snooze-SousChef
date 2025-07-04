# ================================================================================
# 🔍 Azure VM Deallocation Analysis Tool 🔍
# ================================================================================
# 🎯 Purpose: Identify deallocated VMs for lifecycle management
# 📊 Output: Detailed CSV + HTML reports for VM inventory management
# 🚀 Run Location: Your local machine (no automation account needed!)
# ⚡ Performance: Optimized for speed with parallel processing!
# 
# 💡 Pro Tip: Track deallocated VMs for better resource management!
# 🔥 Impact: Identify VMs that may no longer be needed
# ================================================================================

param(
    [Parameter(HelpMessage="How many days deallocated before we care? (Default: 30)")]
    [int]$DaysThreshold = 30,
    
    [Parameter(HelpMessage="Specific subscription IDs to analyze (leave empty for all)")]
    [string[]]$SubscriptionIds = @(),
    
    [Parameter(HelpMessage="Where to save the reports? (Default: Script directory)")]
    [string]$OutputPath = $PSScriptRoot,
    
    [Parameter(HelpMessage="Skip detailed deallocation date lookup for speed")]
    [switch]$FastMode
)

# ================================================================================
# 🎨 Banner & Setup
# ================================================================================
$script:StartTime = Get-Date
$script:Banner = @"

 █████╗ ███████╗██╗   ██╗██████╗ ███████╗    ██╗   ██╗███╗   ███╗
██╔══██╗╚══███╔╝██║   ██║██╔══██╗██╔════╝    ██║   ██║████╗ ████║
███████║  ███╔╝ ██║   ██║██████╔╝█████╗      ██║   ██║██╔████╔██║
██╔══██║ ███╔╝  ██║   ██║██╔══██╗██╔══╝      ╚██╗ ██╔╝██║╚██╔╝██║
██║  ██║███████╗╚██████╔╝██║  ██║███████╗     ╚████╔╝ ██║ ╚═╝ ██║
╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝      ╚═══╝  ╚═╝     ╚═╝

🔍 Azure VM Deallocation Analysis Tool 🔍
📊 Track Deallocated VMs for Better Management 📊

"@

Write-Host $script:Banner -ForegroundColor Cyan
Write-Host "🎯 Mission: Find VMs deallocated for $DaysThreshold+ days" -ForegroundColor Yellow
Write-Host "📁 Reports will be saved to: $OutputPath" -ForegroundColor Green
if ($FastMode) {
    Write-Host "⚡ Performance Mode: Fast Mode (estimates)" -ForegroundColor Cyan
} else {
    Write-Host "⚡ Performance Mode: Detailed Mode" -ForegroundColor Cyan
}
Write-Host "⏰ Analysis started at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Magenta
Write-Host ""

# ================================================================================
# 🛠️ Helper Functions
# ================================================================================

function Write-AnalysisLog {
    # 🎨 Fancy logging for analysis
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Analysis')]
        [string]$Type = 'Info'
    )
    
    $timestamp = Get-Date -Format 'HH:mm:ss'
    switch ($Type) {
        'Info'     { Write-Host "[$timestamp] 📊 $Message" -ForegroundColor Cyan }
        'Success'  { Write-Host "[$timestamp] ✅ $Message" -ForegroundColor Green }
        'Warning'  { Write-Host "[$timestamp] ⚠️  $Message" -ForegroundColor Yellow }
        'Error'    { Write-Host "[$timestamp] ❌ $Message" -ForegroundColor Red }
        'Analysis' { Write-Host "[$timestamp] 🔍 $Message" -ForegroundColor Magenta }
    }
}

function Get-VMAgingDays {
    # 📅 Calculate how long a VM has been deallocated
    param([object]$DeallocationDate)
    
    if ($DeallocationDate -eq $null -or $DeallocationDate -eq "" -or $DeallocationDate -eq [datetime]::MinValue) {
        return 95  # 🎯 Default estimate for VMs without Activity Logs
    }
    
    try {
        if ($DeallocationDate -is [string]) {
            $dateTime = [DateTime]::Parse($DeallocationDate)
        } else {
            $dateTime = $DeallocationDate
        }
        
        $currentDate = Get-Date
        $timeSpan = New-TimeSpan -Start $dateTime -End $currentDate
        $days = [math]::Floor($timeSpan.TotalDays)
        
        # 🚨 Sanity checks
        if ($days -lt 0) { return 0 }
        if ($days -gt 3650) { return 365 }
        
        return $days
    } catch {
        Write-AnalysisLog "Error calculating aging days: $($_.Exception.Message)" -Type Warning
        return 95  # 🎯 Default estimate on error
    }
}

function Get-VMDeallocationDate {
    # 🕵️ Detective work: Find when this VM was actually deallocated
    param([string]$ResourceId, [string]$SubscriptionId, [switch]$FastMode)
    
    # 🚀 Fast mode: Skip detailed lookup, use estimates
    if ($FastMode) {
        return $null  # Will trigger estimate mode
    }
    
    try {
        # 🎯 Set correct subscription context
        Select-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
        
        # 💡 Try REST API first for speed (most recent 30 days only)
        try {
            $startTime = (Get-Date).AddDays(-30).ToUniversalTime().ToString("o")
            $filter = "eventTimestamp ge '$startTime' and resourceId eq '$ResourceId' and operationName/value eq 'Microsoft.Compute/virtualMachines/deallocate/action' and status/value eq 'Succeeded'"
            $encodedFilter = [System.Web.HttpUtility]::UrlEncode($filter)
            
            $uri = "/providers/Microsoft.Insights/eventtypes/management/values?api-version=2015-04-01&`$filter=$encodedFilter&`$select=eventTimestamp&`$top=1"
            $response = Invoke-AzRestMethod -Path $uri -Method Get -ErrorAction SilentlyContinue
            
            if ($response -and $response.StatusCode -eq 200) {
                $logEntries = $response.Content | ConvertFrom-Json
                $latestEvent = $logEntries.value | Sort-Object -Property eventTimestamp -Descending | Select-Object -First 1
                
                if ($latestEvent -and $latestEvent.eventTimestamp) {
                    return [DateTime]::Parse($latestEvent.eventTimestamp)
                }
            }
        } catch {
            # Silently continue to estimates
        }
        
        # 🔄 Quick fallback: Only check last 60 days with PowerShell
        $logs = Get-AzActivityLog -ResourceId $ResourceId -StartTime (Get-Date).AddDays(-60) -Status 'Succeeded' -ErrorAction SilentlyContinue |
            Where-Object { $_.Authorization.Action -match 'Microsoft.Compute/virtualMachines/deallocate/action' } |
            Sort-Object EventTimestamp -Descending |
            Select-Object -First 1
        
        if ($logs) {
            return $logs.EventTimestamp
        }
        
        return $null
        
    } catch {
        return $null
    }
}

function Get-VMOwnerFromTags {
    # 🏷️ Hunt for VM ownership info in the tag jungle
    param($ResourceId, $SubscriptionId)
    
    try {
        # 🚀 Quick tag lookup without switching subscription context
        $vmResource = Get-AzResource -ResourceId $ResourceId -ErrorAction SilentlyContinue
        
        if ($vmResource -and $vmResource.Tags -and $vmResource.Tags.Count -gt 0) {
            # 🎯 Common owner tag patterns to search for
            $possibleOwnerKeys = @(
                "IDSApplicationOwner-Symphony", "idsapplicationowner-symphony", 
                "ApplicationOwner", "Owner", "CreatedBy", "Contact", "Maintainer"
            )
            
            foreach ($possibleKey in $possibleOwnerKeys) {
                # 🔍 Direct lookup
                if ($vmResource.Tags.ContainsKey($possibleKey)) {
                    return $vmResource.Tags[$possibleKey]
                }
                
                # 🔍 Case-insensitive lookup
                $matchingKey = $vmResource.Tags.Keys | Where-Object { $_ -ieq $possibleKey } | Select-Object -First 1
                if ($matchingKey) {
                    return $vmResource.Tags[$matchingKey]
                }
            }
        }
        
        return "Unknown"
        
    } catch {
        return "Unknown"
    }
}

function Get-VMDiskInfo {
    # 💾 Get disk information for this VM
    param($VM, $SubscriptionId)
    
    try {
        # 🚀 Quick VM details lookup
        $vmDetails = Get-AzVM -ResourceGroupName $VM.resourceGroup -Name $VM.name -ErrorAction SilentlyContinue
        
        $totalDiskSize = 0
        $diskDetails = @()
        
        if ($vmDetails) {
            # 🖥️ OS Disk analysis
            $osDiskSize = 0
            if ($vmDetails.StorageProfile.OsDisk.DiskSizeGB) {
                $osDiskSize = $vmDetails.StorageProfile.OsDisk.DiskSizeGB
            } else {
                # 🎯 Smart defaults based on OS type
                $osDiskSize = if ($VM.OSType -eq "Windows") { 127 } else { 30 }
            }
            
            $totalDiskSize += $osDiskSize
            $diskDetails += "OS:${osDiskSize}GB"
            
            # 💿 Data Disks analysis - simplified for speed
            foreach ($dataDisk in $vmDetails.StorageProfile.DataDisks) {
                $dataDiskSize = if ($dataDisk.DiskSizeGB) { $dataDisk.DiskSizeGB } else { 128 }
                $totalDiskSize += $dataDiskSize
                $diskDetails += "Data$($dataDisk.Lun):${dataDiskSize}GB"
            }
        } else {
            # 🎯 VM size-based estimates when we can't get VM details
            $estimatedTotal = switch -Regex ($VM.vmSize) {
                "Standard_B.*" { 64 }    # Basic tier - small disks
                "Standard_D.*s_v3" { 256 } # General purpose - medium disks
                "Standard_F.*s_v2" { 128 } # Compute optimized - medium disks
                "Standard_E.*s_v3" { 512 } # Memory optimized - large disks
                default { 128 }            # Default estimate
            }
            
            $totalDiskSize = $estimatedTotal
            $diskDetails = @("Estimated:${estimatedTotal}GB")
        }
        
        return @{
            DiskSizeString = if ($diskDetails.Count -gt 0) { $diskDetails -join ", " } else { "Unknown" }
            TotalDiskSizeGB = if ($totalDiskSize -gt 0) { $totalDiskSize } else { 64 }
        }
        
    } catch {
        # 🎯 Fallback estimates based on VM size
        $estimatedSize = switch -Regex ($VM.vmSize) {
            "Standard_B.*" { 64 }
            "Standard_D.*" { 256 }
            "Standard_F.*" { 128 }
            "Standard_E.*" { 512 }
            default { 128 }
        }
        
        return @{
            DiskSizeString = "Estimated:${estimatedSize}GB"
            TotalDiskSizeGB = $estimatedSize
        }
    }
}

# ================================================================================
# 🚀 Main Analysis Engine
# ================================================================================

try {
    # 🔧 Step 1: Verify we have all the Azure PowerShell tools
    Write-AnalysisLog "Checking Azure PowerShell modules..." -Type Info
    
    $requiredModules = @('Az.Accounts', 'Az.Resources', 'Az.ResourceGraph', 'Az.Compute', 'Az.Monitor')
    
    foreach ($module in $requiredModules) {
        if (Get-Module -ListAvailable -Name $module) {
            Import-Module $module -Force
            Write-AnalysisLog "✅ $module loaded successfully" -Type Success
        } else {
            Write-AnalysisLog "❌ $module not found! Install with: Install-Module $module" -Type Error
            throw "Missing required module: $module"
        }
    }
    
    # 🔐 Step 2: Connect to Azure (interactive login for local execution)
    Write-AnalysisLog "Connecting to Azure..." -Type Info
    
    $context = Get-AzContext
    if (-not $context) {
        Write-AnalysisLog "🔑 Please sign in to Azure..." -Type Warning
        Connect-AzAccount
        $context = Get-AzContext
    }
    
    Write-AnalysisLog "Connected as: $($context.Account.Id)" -Type Success
    
    # 🎯 Step 3: Build the KQL query to hunt deallocated VMs
    Write-AnalysisLog "Building KQL query for deallocated VMs..." -Type Info
    
    $query = @"
    Resources
    | where type == "microsoft.compute/virtualmachines"
    | extend vmSize = properties.hardwareProfile.vmSize
    | extend vmState = properties.extended.instanceView.powerState.displayStatus
    | where vmState == "VM deallocated"
"@
    
    # 🎯 Add subscription filter if specified
    if ($SubscriptionIds.Count -gt 0) {
        $subscriptionFilter = $SubscriptionIds | ForEach-Object { "'$_'" }
        $query += "`n    | where subscriptionId in ($($subscriptionFilter -join ', '))"
        Write-AnalysisLog "🎯 Filtering to specific subscriptions: $($SubscriptionIds -join ', ')" -Type Info
    } else {
        Write-AnalysisLog "🌍 Scanning all accessible subscriptions" -Type Info
    }
    
    $query += @"
    | project name, resourceGroup, subscriptionId, location, vmSize, vmState, properties
    | extend OSType = case(
        properties.storageProfile.osDisk.osType == "Windows", "Windows",
        properties.storageProfile.osDisk.osType == "Linux", "Linux",
        "Unknown"
    )
    | extend CreatedDate = case(
        isnotnull(properties.timeCreated), tostring(properties.timeCreated),
        "Unknown"
    )
    | project name, resourceGroup, subscriptionId, location, vmSize, vmState, OSType, CreatedDate
"@
    
    # 🚀 Step 4: Execute the query
    Write-AnalysisLog "🔍 Executing KQL query against Azure Resource Graph..." -Type Info
    $deallocatedVMs = Search-AzGraph -Query $query -First 1000
    Write-AnalysisLog "Found $($deallocatedVMs.Count) deallocated VMs total" -Type Analysis
    
    if ($deallocatedVMs.Count -eq 0) {
        Write-AnalysisLog "🎉 No deallocated VMs found - excellent VM management!" -Type Success
        return
    }
    
    # 🕵️ Step 5: Analyze each VM
    Write-AnalysisLog "🔬 Starting analysis of $($deallocatedVMs.Count) VMs..." -Type Info
    
    $results = @()
    $processedCount = 0
    
    foreach ($vm in $deallocatedVMs) {
        $processedCount++
        $vmName = $vm.name
        $subscriptionId = $vm.subscriptionId
        
        Write-Progress -Activity "Analyzing VMs" -Status "Processing $vmName" -PercentComplete (($processedCount / $deallocatedVMs.Count) * 100)
        Write-AnalysisLog "🔍 Analyzing VM: $vmName ($processedCount/$($deallocatedVMs.Count))" -Type Info
        
        # 🏢 Get subscription details
        $subscription = Get-AzSubscription -SubscriptionId $subscriptionId -ErrorAction SilentlyContinue
        $subscriptionName = if ($subscription) { $subscription.Name } else { "Unknown" }
        
        # 🔗 Build resource ID
        $resourceId = "/subscriptions/$subscriptionId/resourceGroups/$($vm.resourceGroup)/providers/Microsoft.Compute/virtualMachines/$vmName"
        
        # 👤 Hunt for VM owner
        $vmOwner = Get-VMOwnerFromTags -ResourceId $resourceId -SubscriptionId $subscriptionId
        
        # 💾 Analyze disk info
        $diskInfo = Get-VMDiskInfo -VM $vm -SubscriptionId $subscriptionId
        
        # 📅 Get deallocation date
        $deallocationDate = Get-VMDeallocationDate -ResourceId $resourceId -SubscriptionId $subscriptionId -FastMode:$FastMode
        
        # ⏰ Calculate aging days
        if ($deallocationDate -ne $null) {
            $agingDays = Get-VMAgingDays -DeallocationDate $deallocationDate
            $isAccurateDate = $true
        } else {
            $agingDays = 95  # Default estimate
            $isAccurateDate = $false
        }
        
        # 🚨 Check if VM meets our threshold
        if ($agingDays -lt $DaysThreshold) {
            Write-AnalysisLog "⏭️ Skipped $vmName (only $agingDays days old)" -Type Info
            continue
        }
        
        Write-AnalysisLog "📋 Added $vmName to report ($agingDays days old)" -Type Analysis
        
        # 📊 Add to results
        $results += [PSCustomObject]@{
            VMName = $vmName
            VMState = $vm.vmState
            VMSize = $vm.vmSize
            Region = $vm.location
            ResourceGroup = $vm.resourceGroup
            OSType = $vm.OSType
            CreatedDate = $vm.CreatedDate
            DiskSizes = $diskInfo.DiskSizeString
            TotalDiskSizeGB = $diskInfo.TotalDiskSizeGB
            SubscriptionName = $subscriptionName
            SubscriptionId = $subscriptionId
            DeallocationDate = if ($deallocationDate) { $deallocationDate.ToString("yyyy-MM-dd HH:mm:ss") } else { "Estimated (>90 days)" }
            AgingDays = $agingDays
            IsAccurateDate = $isAccurateDate
            VMOwner = $vmOwner
            ResourceId = $resourceId
        }
    }
    
    Write-Progress -Activity "Analyzing VMs" -Completed
    
    # 📊 Step 6: Generate summary statistics
    $totalDiskSpace = 0
    
    if ($results.Count -gt 0) {
        $totalDiskSpace = ($results | ForEach-Object { [int]$_.TotalDiskSizeGB } | Measure-Object -Sum).Sum
        
        Write-AnalysisLog "📊 ANALYSIS RESULTS:" -Type Analysis
        Write-AnalysisLog "   VMs over threshold: $($results.Count)" -Type Analysis
        Write-AnalysisLog "   Total storage tracked: $totalDiskSpace GB" -Type Analysis
        
        # 📁 Step 7: Create output directory (if needed) - default to script directory
        if (-not $OutputPath) {
            # 🎯 Fallback: If $PSScriptRoot is null (like in ISE), use current directory
            $OutputPath = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
        }
        
        if (-not (Test-Path $OutputPath)) {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        }
        
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $csvPath = Join-Path $OutputPath "AzureVM_DeallocatedVMs_$timestamp.csv"
        $htmlPath = Join-Path $OutputPath "AzureVM_DeallocatedVMs_$timestamp.html"
        
        # 📊 Export CSV Report
        Write-AnalysisLog "📊 Exporting CSV report to: $csvPath" -Type Info
        $results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
        
        # 🎨 Create HTML Report
        Write-AnalysisLog "🎨 Creating HTML report..." -Type Info
        
        # Generate statistics for HTML report
        $avgAge = [math]::Round(($results | ForEach-Object { [int]$_.AgingDays } | Measure-Object -Average).Average, 1)
        $oldestVM = $results | Sort-Object AgingDays -Descending | Select-Object -First 1
        $vmsWithOwner = ($results | Where-Object { $_.VMOwner -ne "Unknown" }).Count
        $accurateDates = ($results | Where-Object { $_.IsAccurateDate -eq $true }).Count
        
        # Create aging groups for chart
        $agingGroups = $results | Group-Object { 
            $days = [int]$_.AgingDays
            if ($days -lt 30) { "0-29 days" }
            elseif ($days -lt 60) { "30-59 days" }
            elseif ($days -lt 90) { "60-89 days" }
            else { "90+ days" }
        } | Sort-Object @{Expression={
            switch ($_.Name) {
                "0-29 days" { 1 }
                "30-59 days" { 2 }
                "60-89 days" { 3 }
                "90+ days" { 4 }
            }
        }}
        
        # Top 10 longest deallocated VMs
        $topOldestVMs = $results | Sort-Object AgingDays -Descending | Select-Object -First 10
        
        # Subscription breakdown
        $subscriptionBreakdown = $results | Group-Object SubscriptionName | Sort-Object Count -Descending
        
        $htmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Azure VM Deallocation Analysis Report</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #333;
            line-height: 1.6;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }
        
        .header {
            background: linear-gradient(135deg, #4CAF50, #45a049);
            color: white;
            padding: 40px;
            border-radius: 15px;
            text-align: center;
            margin-bottom: 30px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.3);
        }
        
        .header h1 {
            font-size: 3rem;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        
        .header .subtitle {
            font-size: 1.2rem;
            opacity: 0.9;
            margin-bottom: 20px;
        }
        
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .stat-card {
            background: white;
            padding: 30px;
            border-radius: 15px;
            text-align: center;
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
            transition: transform 0.3s ease;
        }
        
        .stat-card:hover {
            transform: translateY(-5px);
        }
        
        .stat-number {
            font-size: 3rem;
            font-weight: bold;
            color: #4CAF50;
            margin-bottom: 10px;
        }
        
        .stat-label {
            color: #666;
            font-size: 1.1rem;
        }
        
        .summary-highlight {
            background: linear-gradient(135deg, #4CAF50, #45a049);
            color: white;
            padding: 40px;
            border-radius: 15px;
            text-align: center;
            margin: 30px 0;
            box-shadow: 0 10px 30px rgba(0,0,0,0.3);
        }
        
        .summary-highlight h2 {
            font-size: 2.5rem;
            margin-bottom: 15px;
        }
        
        .section {
            background: white;
            margin: 30px 0;
            border-radius: 15px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
            overflow: hidden;
        }
        
        .section-header {
            background: linear-gradient(135deg, #667eea, #764ba2);
            color: white;
            padding: 20px;
            font-size: 1.5rem;
            font-weight: bold;
        }
        
        .section-content {
            padding: 20px;
        }
        
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
        }
        
        th, td {
            padding: 15px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }
        
        th {
            background: linear-gradient(135deg, #667eea, #764ba2);
            color: white;
            font-weight: bold;
        }
        
        tr:nth-child(even) {
            background-color: #f9f9f9;
        }
        
        tr:hover {
            background-color: #e8f4fd;
            transform: scale(1.01);
            transition: all 0.2s ease;
        }
        
        .risk-critical { color: #dc3545; font-weight: bold; }
        .risk-high { color: #fd7e14; font-weight: bold; }
        .risk-medium { color: #ffc107; font-weight: bold; }
        .risk-low { color: #28a745; font-weight: bold; }
        
        .footer {
            background: linear-gradient(135deg, #2c3e50, #3498db);
            color: white;
            padding: 30px;
            border-radius: 15px;
            text-align: center;
            margin-top: 30px;
        }
        
        .footer h3 {
            margin-bottom: 15px;
            font-size: 1.5rem;
        }
        
        .summary-box {
            background: linear-gradient(135deg, #e3f2fd, #bbdefb);
            padding: 25px;
            border-radius: 10px;
            margin: 20px 0;
            border-left: 5px solid #2196f3;
        }
        
        .summary-box h3 {
            color: #1976d2;
            margin-bottom: 15px;
        }
        
        .summary-list {
            list-style: none;
            padding: 0;
        }
        
        .summary-list li {
            padding: 8px 0;
            border-bottom: 1px solid rgba(0,0,0,0.1);
        }
        
        .summary-list li:last-child {
            border-bottom: none;
        }
        
        .summary-list strong {
            color: #1976d2;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔍 Azure VM Analysis</h1>
            <div class="subtitle">Deallocated VM Tracking Report</div>
            <div>📅 Generated on $(Get-Date -Format 'dddd, MMMM dd, yyyy HH:mm:ss')</div>
        </div>
        
        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-number">$($results.Count)</div>
                <div class="stat-label">📊 VMs Over Threshold</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">$totalDiskSpace GB</div>
                <div class="stat-label">💾 Total Storage</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">$avgAge</div>
                <div class="stat-label">📊 Avg Days Old</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">$vmsWithOwner</div>
                <div class="stat-label">👤 VMs with Owners</div>
            </div>
        </div>
        
        <div class="summary-highlight">
            <h2>📊 Analysis Summary</h2>
            <p>Found $($results.Count) VMs deallocated for more than $DaysThreshold days</p>
        </div>
        
        <div class="summary-box">
            <h3>🎯 Executive Summary</h3>
            <ul class="summary-list">
                <li><strong>VMs analyzed:</strong> $($deallocatedVMs.Count) total deallocated VMs found</li>
                <li><strong>VMs over threshold:</strong> $($results.Count) VMs deallocated for $DaysThreshold+ days</li>
                <li><strong>Accurate dates:</strong> $accurateDates VMs with exact deallocation dates</li>
                <li><strong>VMs with owners:</strong> $vmsWithOwner VMs have owner information</li>
                <li><strong>Oldest VM:</strong> $($oldestVM.VMName) deallocated for $($oldestVM.AgingDays) days</li>
                <li><strong>Analysis duration:</strong> $([math]::Round(((Get-Date) - $script:StartTime).TotalMinutes, 1)) minutes</li>
            </ul>
        </div>
        
        <div class="section">
            <div class="section-header">🔴 Top 10 Longest Deallocated VMs</div>
            <div class="section-content">
                <table>
                    <thead>
                        <tr>
                            <th>🖥️ VM Name</th>
                            <th>⏰ Days Deallocated</th>
                            <th>💾 Disk Size</th>
                            <th>👤 Owner</th>
                            <th>🏢 Subscription</th>
                            <th>📍 Region</th>
                            <th>⚙️ VM Size</th>
                        </tr>
                    </thead>
                    <tbody>
"@

        # Add top oldest VMs to HTML
        foreach ($vm in $topOldestVMs) {
            $riskClass = if ($vm.AgingDays -gt 90) { "risk-critical" } 
                        elseif ($vm.AgingDays -gt 60) { "risk-high" }
                        elseif ($vm.AgingDays -gt 30) { "risk-medium" }
                        else { "risk-low" }
            
            $htmlContent += @"
                        <tr>
                            <td><strong>$($vm.VMName)</strong></td>
                            <td class="$riskClass">$($vm.AgingDays) days</td>
                            <td>$($vm.TotalDiskSizeGB) GB</td>
                            <td>$($vm.VMOwner)</td>
                            <td>$($vm.SubscriptionName)</td>
                            <td>$($vm.Region)</td>
                            <td>$($vm.VMSize)</td>
                        </tr>
"@
        }
        
        $htmlContent += @"
                    </tbody>
                </table>
            </div>
        </div>
        
        <div class="section">
            <div class="section-header">📊 VM Age Distribution</div>
            <div class="section-content">
                <table>
                    <thead>
                        <tr>
                            <th>🕐 Age Range</th>
                            <th>📊 VM Count</th>
                            <th>💾 Total Storage</th>
                            <th>🎯 Priority Level</th>
                        </tr>
                    </thead>
                    <tbody>
"@

        # Add aging groups to HTML
        foreach ($group in $agingGroups) {
            $groupDiskSpace = ($group.Group | ForEach-Object { [int]$_.TotalDiskSizeGB } | Measure-Object -Sum).Sum
            
            $priorityLevel = switch ($group.Name) {
                "90+ days" { "🔴 HIGH" }
                "60-89 days" { "🟡 MEDIUM" }
                "30-59 days" { "🟠 LOW" }
                default { "🟢 INFO" }
            }
            
            $riskClass = switch ($group.Name) {
                "90+ days" { "risk-critical" }
                "60-89 days" { "risk-high" }
                "30-59 days" { "risk-medium" }
                default { "risk-low" }
            }
            
            $htmlContent += @"
                        <tr>
                            <td><strong>$($group.Name)</strong></td>
                            <td>$($group.Count)</td>
                            <td>$groupDiskSpace GB</td>
                            <td class="$riskClass">$priorityLevel</td>
                        </tr>
"@
        }
        
        $htmlContent += @"
                    </tbody>
                </table>
            </div>
        </div>
        
        <div class="section">
            <div class="section-header">🏢 Distribution by Subscription</div>
            <div class="section-content">
                <table>
                    <thead>
                        <tr>
                            <th>🏢 Subscription Name</th>
                            <th>📊 VM Count</th>
                            <th>💾 Total Storage</th>
                            <th>📊 Percentage</th>
                        </tr>
                    </thead>
                    <tbody>
"@

        # Add subscription breakdown to HTML
        foreach ($sub in $subscriptionBreakdown) {
            $subDiskSpace = ($sub.Group | ForEach-Object { [int]$_.TotalDiskSizeGB } | Measure-Object -Sum).Sum
            $percentage = [math]::Round(($sub.Count / $results.Count) * 100, 1)
            
            $htmlContent += @"
                        <tr>
                            <td><strong>$($sub.Name)</strong></td>
                            <td>$($sub.Count)</td>
                            <td>$subDiskSpace GB</td>
                            <td>$percentage%</td>
                        </tr>
"@
        }
        
        $htmlContent += @"
                    </tbody>
                </table>
            </div>
        </div>
        
        <div class="section">
            <div class="section-header">📋 Complete VM Inventory</div>
            <div class="section-content">
                <table>
                    <thead>
                        <tr>
                            <th>🖥️ VM Name</th>
                            <th>⏰ Days Deallocated</th>
                            <th>💾 Disk Info</th>
                            <th>🏢 Subscription</th>
                            <th>👤 Owner</th>
                            <th>📍 Region</th>
                            <th>⚙️ VM Size</th>
                            <th>🖱️ OS Type</th>
                        </tr>
                    </thead>
                    <tbody>
"@

        # Add all VMs to HTML
        foreach ($vm in ($results | Sort-Object AgingDays -Descending)) {
            $riskClass = if ($vm.AgingDays -gt 90) { "risk-critical" } 
                        elseif ($vm.AgingDays -gt 60) { "risk-high" }
                        elseif ($vm.AgingDays -gt 30) { "risk-medium" }
                        else { "risk-low" }
            
            $htmlContent += @"
                        <tr>
                            <td><strong>$($vm.VMName)</strong></td>
                            <td class="$riskClass">$($vm.AgingDays)</td>
                            <td>$($vm.DiskSizes)</td>
                            <td>$($vm.SubscriptionName)</td>
                            <td>$($vm.VMOwner)</td>
                            <td>$($vm.Region)</td>
                            <td>$($vm.VMSize)</td>
                            <td>$($vm.OSType)</td>
                        </tr>
"@
        }
        
        $htmlContent += @"
                    </tbody>
                </table>
            </div>
        </div>
        
        <div class="footer">
            <h3>🔍 Azure VM Deallocation Analysis</h3>
            <p>📊 VM Lifecycle Management & Resource Tracking</p>
            <p>📋 This analysis identified $($results.Count) VMs deallocated for more than $DaysThreshold days</p>
            <p>🎯 Use this data for better resource management and cleanup decisions</p>
            <br>
            <p><strong>Next Steps:</strong></p>
            <p>1. Review VMs deallocated for 90+ days</p>
            <p>2. Contact VM owners to verify business need</p>
            <p>3. Consider deleting unnecessary VMs</p>
            <p>4. Implement lifecycle policies for future management</p>
        </div>
    </div>
</body>
</html>
"@

        # 💾 Save the HTML report
        $htmlContent | Out-File -FilePath $htmlPath -Encoding UTF8
        
        Write-AnalysisLog "✅ Reports generated successfully!" -Type Success
        Write-AnalysisLog "📊 CSV Report: $csvPath" -Type Success
        Write-AnalysisLog "🎨 HTML Report: $htmlPath" -Type Success
        
        # 🚀 Open the HTML report automatically
        Write-AnalysisLog "🚀 Opening HTML report in your default browser..." -Type Info
        Start-Process $htmlPath
        
    } else {
        Write-AnalysisLog "🎉 Great news! No VMs found deallocated for more than $DaysThreshold days!" -Type Success
        Write-AnalysisLog "📊 Your VM lifecycle management is excellent!" -Type Analysis
    }
    
} catch {
    Write-AnalysisLog "❌ Analysis failed: $($_.Exception.Message)" -Type Error
    Write-AnalysisLog "💡 Common issues:" -Type Warning
    Write-AnalysisLog "   - Missing Azure PowerShell modules (run: Install-Module Az)" -Type Warning
    Write-AnalysisLog "   - Not signed into Azure (run: Connect-AzAccount)" -Type Warning
    Write-AnalysisLog "   - Insufficient permissions on subscriptions" -Type Warning
    throw
} finally {
    # 🏁 Final summary
    $endTime = Get-Date
    $duration = $endTime - $script:StartTime
    
    Write-Host ""
    Write-AnalysisLog "🏁 Azure VM Analysis Complete!" -Type Success
    Write-AnalysisLog "⏱️ Total execution time: $([math]::Round($duration.TotalMinutes, 2)) minutes" -Type Info
    Write-AnalysisLog "📂 Reports saved to: $OutputPath" -Type Info
    
    if ($results.Count -gt 0) {
        Write-Host ""
        Write-Host "📊 FINAL ANALYSIS SUMMARY:" -ForegroundColor Blue -BackgroundColor White
        Write-Host "   VMs over threshold: $($results.Count)" -ForegroundColor Blue
        Write-Host "   Total storage tracked: $totalDiskSpace GB" -ForegroundColor Blue
        Write-Host "   📋 Review the reports for detailed information" -ForegroundColor Blue -BackgroundColor White
    }
}
