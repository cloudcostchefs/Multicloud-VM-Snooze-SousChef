#Requires -Version 5.1
<#
================================================================================
🛑 AWS Stopped Instances Lister - PowerShell Edition
================================================================================
🎯 Purpose: List all stopped EC2 instances across your AWS accounts and regions
📊 Output: Clean CSV + HTML reports of stopped instances
⚡ Fast PowerShell with AWS CLI integration
☁️ Works with multiple accounts, regions, and profiles
================================================================================
.SYNOPSIS
    Lists all stopped AWS EC2 instances across regions and generates reports.

.DESCRIPTION
    This script scans your AWS account(s) for stopped EC2 instances and generates
    detailed CSV and HTML reports. It uses the AWS CLI for authentication and
    data retrieval, supporting multiple profiles and regions.

.PARAMETER Regions
    Comma-separated list of AWS regions to scan. If not provided, scans all enabled regions.

.PARAMETER MinDays
    Minimum days since creation to include instances (default: 0)

.PARAMETER OutputPath
    Output directory for reports (default: current directory)

.PARAMETER MaxConcurrent
    Maximum number of concurrent operations (default: 10)

.PARAMETER SkipRegions
    Comma-separated list of regions to skip

.PARAMETER Profile
    AWS CLI profile to use (default: default profile)

.PARAMETER IncludeTerminated
    Include terminated instances in addition to stopped ones

.EXAMPLE
    .\AWS-StoppedInstances.ps1
    Lists all stopped instances across all enabled regions

.EXAMPLE
    .\AWS-StoppedInstances.ps1 -Regions "us-east-1,us-west-2" -MinDays 30
    Lists stopped instances older than 30 days in specific regions

.EXAMPLE
    .\AWS-StoppedInstances.ps1 -Profile "production" -IncludeTerminated
    Lists stopped and terminated instances using a specific AWS profile
#>

[CmdletBinding()]
param(
    [string]$Regions = "",
    [int]$MinDays = 0,
    [string]$OutputPath = ".",
    [int]$MaxConcurrent = 10,
    [string]$SkipRegions = "",
    [string]$Profile = "",
    [switch]$IncludeTerminated
)

# Global variables for tracking
$Script:Stats = @{
    RegionsScanned = 0
    StoppedInstancesFound = 0
    TerminatedInstancesFound = 0
    ApiCallsMade = 0
    StartTime = Get-Date
}

$Script:StoppedInstances = @()

function Write-Progress-Log {
    param([string]$Message)
    $elapsed = (Get-Date) - $Script:Stats.StartTime
    Write-Host "⚡ [$($elapsed.TotalSeconds.ToString('F1'))s] $Message" -ForegroundColor Cyan
}

function Write-Error-Log {
    param([string]$Message)
    Write-Host "❌ $Message" -ForegroundColor Red
}

function Write-Warning-Log {
    param([string]$Message)
    Write-Host "⚠️ $Message" -ForegroundColor Yellow
}

function Write-Success-Log {
    param([string]$Message)
    Write-Host "✅ $Message" -ForegroundColor Green
}

function Test-AwsCli {
    <#
    .SYNOPSIS
    Tests if AWS CLI is installed and configured
    #>
    Write-Progress-Log "Checking AWS CLI setup..."
    
    try {
        $null = Get-Command aws -ErrorAction Stop
        Write-Success-Log "AWS CLI found"
    }
    catch {
        Write-Error-Log "AWS CLI not found. Please install AWS CLI v2."
        Write-Host "Download from: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html" -ForegroundColor Blue
        exit 1
    }
    
    # Build AWS CLI command with profile if specified
    $awsCmd = "aws"
    $profileParam = if ($Profile) { "--profile $Profile" } else { "" }
    
    try {
        $identity = if ($Profile) {
            aws sts get-caller-identity --profile $Profile --output json 2>$null
        } else {
            aws sts get-caller-identity --output json 2>$null
        }
        
        if (-not $identity) {
            $profileMsg = if ($Profile) { " for profile '$Profile'" } else { "" }
            Write-Error-Log "AWS CLI not configured or credentials invalid$profileMsg"
            Write-Host "Run: aws configure$($Profile ? " --profile $Profile" : "")" -ForegroundColor Blue
            exit 1
        }
        
        $identityObj = $identity | ConvertFrom-Json
        $profileMsg = if ($Profile) { " (Profile: $Profile)" } else { " (Default profile)" }
        Write-Success-Log "AWS authentication verified$profileMsg"
        Write-Host "   Account: $($identityObj.Account)" -ForegroundColor Gray
        Write-Host "   User/Role: $($identityObj.Arn)" -ForegroundColor Gray
    }
    catch {
        Write-Error-Log "Failed to verify AWS authentication: $_"
        exit 1
    }
}

function Get-AwsRegions {
    <#
    .SYNOPSIS
    Gets list of available AWS regions
    #>
    param(
        [string[]]$SpecificRegions = @(),
        [string[]]$SkipRegionsList = @()
    )
    
    Write-Progress-Log "Discovering AWS regions..."
    
    try {
        if ($SpecificRegions.Count -gt 0) {
            $filteredRegions = $SpecificRegions | Where-Object { $_ -notin $SkipRegionsList }
            Write-Progress-Log "Using specified regions: $($filteredRegions -join ', ')"
            return $filteredRegions
        }
        
        $Script:Stats.ApiCallsMade++
        $regionsJson = if ($Profile) {
            aws ec2 describe-regions --profile $Profile --output json 2>$null
        } else {
            aws ec2 describe-regions --output json 2>$null
        }
        
        if (-not $regionsJson) {
            Write-Warning-Log "Could not retrieve regions, using common ones"
            return @("us-east-1", "us-west-1", "us-west-2", "eu-west-1")
        }
        
        $regions = ($regionsJson | ConvertFrom-Json).Regions
        $regionNames = $regions | ForEach-Object { $_.RegionName } | Where-Object { $_ -notin $SkipRegionsList }
        
        Write-Success-Log "Found $($regionNames.Count) available regions"
        return $regionNames
    }
    catch {
        Write-Error-Log "Failed to get regions: $_"
        return @("us-east-1", "us-west-2")
    }
}

function Get-StoppedInstancesInRegion {
    <#
    .SYNOPSIS
    Gets stopped instances in a specific AWS region
    #>
    param(
        [string]$Region,
        [bool]$IncludeTerminated = $false
    )
    
    try {
        $Script:Stats.ApiCallsMade++
        
        # Build filter for instance states
        $stateFilter = "Name=instance-state-name,Values=stopped"
        if ($IncludeTerminated) {
            $stateFilter = "Name=instance-state-name,Values=stopped,terminated"
        }
        
        # Get instances with specified states
        $instancesJson = if ($Profile) {
            aws ec2 describe-instances --region $Region --profile $Profile --filters $stateFilter --output json 2>$null
        } else {
            aws ec2 describe-instances --region $Region --filters $stateFilter --output json 2>$null
        }
        
        if (-not $instancesJson) {
            return @()
        }
        
        $reservations = ($instancesJson | ConvertFrom-Json).Reservations
        $instances = @()
        
        foreach ($reservation in $reservations) {
            $instances += $reservation.Instances
        }
        
        if ($instances.Count -gt 0) {
            Write-Host "📍 Found $($instances.Count) stopped instances in $Region" -ForegroundColor Green
        }
        
        return $instances
    }
    catch {
        Write-Warning-Log "Failed to get instances in region $Region : $_"
        return @()
    }
}

function Convert-AwsInstance {
    <#
    .SYNOPSIS
    Converts AWS instance to standardized format
    #>
    param(
        [object]$Instance,
        [string]$Region
    )
    
    try {
        # Parse launch time
        $launchTime = [DateTime]::Parse($Instance.LaunchTime)
        $daysSinceCreated = [math]::Floor(((Get-Date) - $launchTime).TotalDays)
        
        # Get instance name from tags
        $instanceName = "Unnamed"
        $owner = "Unknown"
        $environment = "Unknown"
        $project = "Unknown"
        
        if ($Instance.Tags) {
            foreach ($tag in $Instance.Tags) {
                switch ($tag.Key.ToLower()) {
                    "name" { $instanceName = $tag.Value }
                    "owner" { $owner = $tag.Value }
                    "created-by" { if ($owner -eq "Unknown") { $owner = $tag.Value } }
                    "environment" { $environment = $tag.Value }
                    "project" { $project = $tag.Value }
                    "team" { if ($owner -eq "Unknown") { $owner = $tag.Value } }
                }
            }
        }
        
        # Get availability zone
        $availabilityZone = if ($Instance.Placement) { $Instance.Placement.AvailabilityZone } else { "Unknown" }
        
        # Get VPC and subnet info
        $vpcId = if ($Instance.VpcId) { $Instance.VpcId } else { "Classic" }
        $subnetId = if ($Instance.SubnetId) { $Instance.SubnetId } else { "None" }
        
        # Get security groups
        $securityGroups = if ($Instance.SecurityGroups) {
            ($Instance.SecurityGroups | ForEach-Object { $_.GroupName }) -join ", "
        } else {
            "None"
        }
        
        # Get EBS volumes info
        $volumeInfo = @()
        $totalVolumeSize = 0
        if ($Instance.BlockDeviceMappings) {
            foreach ($mapping in $Instance.BlockDeviceMappings) {
                if ($mapping.Ebs) {
                    $volumeSize = if ($mapping.Ebs.VolumeSize) { $mapping.Ebs.VolumeSize } else { 8 }
                    $totalVolumeSize += $volumeSize
                    $deviceName = $mapping.DeviceName
                    $volumeInfo += "$deviceName`: $($volumeSize)GB"
                }
            }
        }
        $volumeSizes = if ($volumeInfo.Count -gt 0) { $volumeInfo -join ", " } else { "Unknown" }
        
        # Get state transition reason (when it was stopped)
        $stateReason = $Instance.StateReason.Message
        $stateTransitionReason = $Instance.StateTransitionReason
        
        # Try to extract stop time from state transition reason
        $stopTime = "Unknown"
        $daysStopped = 0
        if ($stateTransitionReason -match '\((\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC)\)') {
            try {
                $stopDateTime = [DateTime]::Parse($matches[1])
                $stopTime = $stopDateTime.ToString("yyyy-MM-dd HH:mm:ss")
                $daysStopped = [math]::Floor(((Get-Date) - $stopDateTime).TotalDays)
            }
            catch {
                $stopTime = "Parse Error"
            }
        }
        
        # Get platform (Windows/Linux)
        $platform = if ($Instance.Platform -eq "windows") { "Windows" } else { "Linux" }
        
        return [PSCustomObject]@{
            InstanceName = $instanceName
            InstanceId = $Instance.InstanceId
            InstanceType = $Instance.InstanceType
            State = $Instance.State.Name
            Region = $Region
            AvailabilityZone = $availabilityZone
            VpcId = $vpcId
            SubnetId = $subnetId
            LaunchTime = $launchTime.ToString("yyyy-MM-dd HH:mm:ss")
            DaysSinceCreated = $daysSinceCreated
            StopTime = $stopTime
            DaysStopped = $daysStopped
            Owner = $owner
            Environment = $environment
            Project = $project
            Platform = $platform
            SecurityGroups = $securityGroups
            VolumeSizes = $volumeSizes
            TotalVolumeGB = $totalVolumeSize
            PrivateIpAddress = if ($Instance.PrivateIpAddress) { $Instance.PrivateIpAddress } else { "None" }
            PublicIpAddress = if ($Instance.PublicIpAddress) { $Instance.PublicIpAddress } else { "None" }
            KeyName = if ($Instance.KeyName) { $Instance.KeyName } else { "None" }
            StateReason = $stateReason
            StateTransitionReason = $stateTransitionReason
            ImageId = $Instance.ImageId
            MonitoringState = if ($Instance.Monitoring) { $Instance.Monitoring.State } else { "Unknown" }
        }
    }
    catch {
        Write-Warning-Log "Failed to convert instance $($Instance.InstanceId): $_"
        return $null
    }
}

function Start-ParallelInstanceDiscovery {
    <#
    .SYNOPSIS
    Discovers stopped instances across regions in parallel
    #>
    param(
        [string[]]$Regions,
        [bool]$IncludeTerminated = $false
    )
    
    Write-Progress-Log "Starting parallel discovery across $($Regions.Count) regions..."
    
    $jobs = @()
    
    foreach ($region in $Regions) {
        # Wait if we have too many concurrent jobs
        while ($jobs.Count -ge $MaxConcurrent) {
            $completed = $jobs | Where-Object { $_.State -eq 'Completed' -or $_.State -eq 'Failed' }
            foreach ($job in $completed) {
                try {
                    $instances = Receive-Job -Job $job
                    if ($instances.Count -gt 0) {
                        foreach ($instance in $instances) {
                            $converted = Convert-AwsInstance -Instance $instance -Region $job.Name
                            if ($converted) {
                                $Script:StoppedInstances += $converted
                                if ($converted.State -eq "stopped") {
                                    $Script:Stats.StoppedInstancesFound++
                                } elseif ($converted.State -eq "terminated") {
                                    $Script:Stats.TerminatedInstancesFound++
                                }
                            }
                        }
                    }
                }
                catch {
                    Write-Warning-Log "Job failed for region $($job.Name): $_"
                }
                Remove-Job -Job $job
            }
            $jobs = $jobs | Where-Object { $_.State -eq 'Running' }
            Start-Sleep -Milliseconds 100
        }
        
        # Start new job for this region
        $job = Start-Job -Name $region -ScriptBlock {
            param($Region, $IncludeTerminated, $Profile)
            
            try {
                # Build filter for instance states
                $stateFilter = "Name=instance-state-name,Values=stopped"
                if ($IncludeTerminated) {
                    $stateFilter = "Name=instance-state-name,Values=stopped,terminated"
                }
                
                # Get instances with specified states
                $instancesJson = if ($Profile) {
                    aws ec2 describe-instances --region $Region --profile $Profile --filters $stateFilter --output json 2>$null
                } else {
                    aws ec2 describe-instances --region $Region --filters $stateFilter --output json 2>$null
                }
                
                if ($instancesJson) {
                    $reservations = ($instancesJson | ConvertFrom-Json).Reservations
                    $instances = @()
                    foreach ($reservation in $reservations) {
                        $instances += $reservation.Instances
                    }
                    return $instances
                }
                return @()
            }
            catch {
                return @()
            }
        } -ArgumentList $region, $IncludeTerminated, $Profile
        
        $jobs += $job
        $Script:Stats.RegionsScanned++
    }
    
    # Wait for all remaining jobs to complete
    Write-Progress-Log "Waiting for remaining discovery jobs to complete..."
    $jobs | Wait-Job | ForEach-Object {
        try {
            $instances = Receive-Job -Job $_
            if ($instances.Count -gt 0) {
                $region = $_.Name
                foreach ($instance in $instances) {
                    $converted = Convert-AwsInstance -Instance $instance -Region $region
                    if ($converted) {
                        $Script:StoppedInstances += $converted
                        if ($converted.State -eq "stopped") {
                            $Script:Stats.StoppedInstancesFound++
                        } elseif ($converted.State -eq "terminated") {
                            $Script:Stats.TerminatedInstancesFound++
                        }
                    }
                }
            }
        }
        catch {
            Write-Warning-Log "Failed to process job results for $($_.Name): $_"
        }
        Remove-Job -Job $_
    }
    
    $totalFound = $Script:StoppedInstances.Count
    Write-Progress-Log "Discovery complete: $totalFound instances found ($($Script:Stats.StoppedInstancesFound) stopped, $($Script:Stats.TerminatedInstancesFound) terminated)"
}

function Export-CsvReport {
    <#
    .SYNOPSIS
    Exports stopped instances to CSV
    #>
    param([object[]]$Instances, [string]$OutputPath)
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $csvFile = Join-Path $OutputPath "AWS_Stopped_Instances_$timestamp.csv"
    
    try {
        $Instances | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8
        Write-Success-Log "CSV report saved: $csvFile"
        return $csvFile
    }
    catch {
        Write-Error-Log "Failed to save CSV report: $_"
        return ""
    }
}

function Export-HtmlReport {
    <#
    .SYNOPSIS
    Generates comprehensive HTML report
    #>
    param([object[]]$Instances, [string]$OutputPath)
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $htmlFile = Join-Path $OutputPath "AWS_Stopped_Instances_$timestamp.html"
    
    try {
        # Calculate statistics
        $totalInstances = $Instances.Count
        if ($totalInstances -eq 0) {
            return ""
        }
        
        $avgDays = ($Instances | Measure-Object -Property DaysSinceCreated -Average).Average
        $oldestInstance = $Instances | Sort-Object DaysSinceCreated -Descending | Select-Object -First 1
        $totalVolumeGB = ($Instances | Measure-Object -Property TotalVolumeGB -Sum).Sum
        
        # Count stopped vs terminated
        $stoppedCount = ($Instances | Where-Object { $_.State -eq "stopped" }).Count
        $terminatedCount = ($Instances | Where-Object { $_.State -eq "terminated" }).Count
        
        # Breakdowns
        $regionBreakdown = $Instances | Group-Object Region | Sort-Object Count -Descending
        $instanceTypeBreakdown = $Instances | Group-Object InstanceType | Sort-Object Count -Descending
        $platformBreakdown = $Instances | Group-Object Platform | Sort-Object Count -Descending
        $ownerBreakdown = $Instances | Group-Object Owner | Sort-Object Count -Descending
        $environmentBreakdown = $Instances | Group-Object Environment | Sort-Object Count -Descending
        
        # Age distribution
        $ageRanges = @{
            "0-29 days" = ($Instances | Where-Object { $_.DaysSinceCreated -lt 30 }).Count
            "30-89 days" = ($Instances | Where-Object { $_.DaysSinceCreated -ge 30 -and $_.DaysSinceCreated -lt 90 }).Count
            "90-179 days" = ($Instances | Where-Object { $_.DaysSinceCreated -ge 90 -and $_.DaysSinceCreated -lt 180 }).Count
            "180-364 days" = ($Instances | Where-Object { $_.DaysSinceCreated -ge 180 -and $_.DaysSinceCreated -lt 365 }).Count
            "365+ days" = ($Instances | Where-Object { $_.DaysSinceCreated -ge 365 }).Count
        }
        
        $analysisTime = ((Get-Date) - $Script:Stats.StartTime).TotalSeconds
        $currentTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $profileInfo = if ($Profile) { " | Profile: $Profile" } else { " | Default Profile" }
        
        # Generate HTML content
        $htmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>🛑 AWS Stopped Instances Report</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', sans-serif; background: linear-gradient(135deg, #ff9900, #232f3e); color: #333; line-height: 1.6; }
        .container { max-width: 1400px; margin: 0 auto; padding: 20px; }
        .header { background: linear-gradient(135deg, #ff9900, #232f3e); color: white; padding: 30px; border-radius: 15px; text-align: center; margin-bottom: 20px; box-shadow: 0 10px 30px rgba(0,0,0,0.3); }
        .header h1 { font-size: 2.5rem; margin-bottom: 10px; }
        .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 15px; margin-bottom: 20px; }
        .stat-card { background: white; padding: 20px; border-radius: 10px; text-align: center; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .stat-number { font-size: 1.8rem; font-weight: bold; color: #ff9900; margin-bottom: 5px; }
        .stat-label { color: #666; font-size: 0.85rem; }
        .section { background: white; margin: 20px 0; border-radius: 10px; overflow: hidden; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .section-header { background: linear-gradient(135deg, #ff9900, #232f3e); color: white; padding: 15px; font-size: 1.2rem; font-weight: bold; }
        .section-content { padding: 15px; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 8px; text-align: left; border-bottom: 1px solid #ddd; font-size: 0.85rem; }
        th { background: #f5f5f5; font-weight: bold; }
        tr:hover { background-color: #fff3e0; }
        .age-critical { color: #d32f2f; font-weight: bold; }
        .age-high { color: #f57c00; font-weight: bold; }
        .age-medium { color: #fbc02d; font-weight: bold; }
        .age-low { color: #388e3c; font-weight: bold; }
        .state-stopped { color: #f57c00; font-weight: bold; }
        .state-terminated { color: #d32f2f; font-weight: bold; }
        .breakdown-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }
        .perf-note { background: #fff3e0; border: 1px solid #ff9900; color: #e65100; padding: 15px; border-radius: 5px; margin: 15px 0; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🛑 AWS <span style="color: #FFE0B2;">Stopped</span> Instances Report</h1>
            <div>⚡ PowerShell + AWS CLI Analysis - $currentTime</div>
            <div>🎯 Analysis Time: $($analysisTime.ToString('F1'))s$profileInfo</div>
        </div>
        
        <div class="perf-note">
            <strong>📊 Analysis Summary:</strong> 
            Found $totalInstances instances ($stoppedCount stopped, $terminatedCount terminated) across $($Script:Stats.RegionsScanned) regions | 
            API calls: $($Script:Stats.ApiCallsMade) | 
            Processing speed: $($totalInstances / $analysisTime | ForEach-Object { $_.ToString('F1') }) instances/sec
        </div>
        
        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-number">$totalInstances</div>
                <div class="stat-label">🛑 Total Instances</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">$stoppedCount</div>
                <div class="stat-label">⏸️ Stopped</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">$terminatedCount</div>
                <div class="stat-label">❌ Terminated</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">$($avgDays.ToString('F1'))</div>
                <div class="stat-label">📅 Avg Days Old</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">$($oldestInstance.DaysSinceCreated)</div>
                <div class="stat-label">🕰️ Oldest Instance</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">$totalVolumeGB</div>
                <div class="stat-label">💾 Total EBS GB</div>
            </div>
        </div>
        
        <div class="section">
            <div class="section-header">📊 Age Distribution Analysis</div>
            <div class="section-content">
                <table>
                    <thead>
                        <tr>
                            <th>Age Range</th>
                            <th>Instance Count</th>
                            <th>Percentage</th>
                            <th>Priority Level</th>
                        </tr>
                    </thead>
                    <tbody>
"@

        foreach ($range in $ageRanges.GetEnumerator() | Sort-Object Name) {
            $percentage = if ($totalInstances -gt 0) { ($range.Value / $totalInstances * 100).ToString('F1') } else { "0.0" }
            $priority = switch ($range.Key) {
                "365+ days" { "🔴 CRITICAL"; "age-critical" }
                "180-364 days" { "🟠 HIGH"; "age-high" }
                "90-179 days" { "🟡 MEDIUM"; "age-medium" }
                default { "🟢 LOW"; "age-low" }
            }
            $ageClass = $priority[1]
            $priorityText = $priority[0]
            
            $htmlContent += @"
                        <tr>
                            <td><strong>$($range.Key)</strong></td>
                            <td>$($range.Value)</td>
                            <td>$percentage%</td>
                            <td class="$ageClass">$priorityText</td>
                        </tr>
"@
        }

        $htmlContent += @"
                    </tbody>
                </table>
            </div>
        </div>
        
        <div class="section">
            <div class="section-header">🔝 Top 20 Oldest Stopped/Terminated Instances</div>
            <div class="section-content">
                <table>
                    <thead>
                        <tr>
                            <th>Instance Name</th>
                            <th>Days Old</th>
                            <th>State</th>
                            <th>Instance Type</th>
                            <th>Region</th>
                            <th>Owner</th>
                            <th>Environment</th>
                            <th>Stop Time</th>
                        </tr>
                    </thead>
                    <tbody>
"@

        $topInstances = $Instances | Sort-Object DaysSinceCreated -Descending | Select-Object -First 20
        foreach ($instance in $topInstances) {
            $ageClass = if ($instance.DaysSinceCreated -ge 365) { "age-critical" } 
                       elseif ($instance.DaysSinceCreated -ge 180) { "age-high" }
                       elseif ($instance.DaysSinceCreated -ge 90) { "age-medium" }
                       else { "age-low" }
            
            $stateClass = if ($instance.State -eq "stopped") { "state-stopped" } else { "state-terminated" }
            
            $htmlContent += @"
                        <tr>
                            <td><strong>$($instance.InstanceName)</strong></td>
                            <td class="$ageClass">$($instance.DaysSinceCreated)</td>
                            <td class="$stateClass">$($instance.State.ToUpper())</td>
                            <td>$($instance.InstanceType)</td>
                            <td>$($instance.Region)</td>
                            <td>$($instance.Owner)</td>
                            <td>$($instance.Environment)</td>
                            <td>$($instance.StopTime)</td>
                        </tr>
"@
        }

        $htmlContent += @"
                    </tbody>
                </table>
            </div>
        </div>
        
        <div class="breakdown-grid">
            <div class="section">
                <div class="section-header">🌍 Regional Distribution</div>
                <div class="section-content">
                    <table>
                        <thead>
                            <tr><th>Region</th><th>Count</th><th>%</th></tr>
                        </thead>
                        <tbody>
"@

        foreach ($region in $regionBreakdown | Select-Object -First 15) {
            $percentage = ($region.Count / $totalInstances * 100).ToString('F1')
            $htmlContent += @"
                            <tr>
                                <td><strong>$($region.Name)</strong></td>
                                <td>$($region.Count)</td>
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
                <div class="section-header">⚙️ Instance Type Distribution</div>
                <div class="section-content">
                    <table>
                        <thead>
                            <tr><th>Instance Type</th><th>Count</th><th>%</th></tr>
                        </thead>
                        <tbody>
"@

        foreach ($instanceType in $instanceTypeBreakdown | Select-Object -First 15) {
            $percentage = ($instanceType.Count / $totalInstances * 100).ToString('F1')
            $htmlContent += @"
                            <tr>
                                <td><strong>$($instanceType.Name)</strong></td>
                                <td>$($instanceType.Count)</td>
                                <td>$percentage%</td>
                            </tr>
"@
        }

        $htmlContent += @"
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
        
        <div class="breakdown-grid">
            <div class="section">
                <div class="section-header">👤 Owner Distribution</div>
                <div class="section-content">
                    <table>
                        <thead>
                            <tr><th>Owner</th><th>Count</th><th>%</th></tr>
                        </thead>
                        <tbody>
"@

        foreach ($owner in $ownerBreakdown | Select-Object -First 10) {
            $percentage = ($owner.Count / $totalInstances * 100).ToString('F1')
            $htmlContent += @"
                            <tr>
                                <td><strong>$($owner.Name)</strong></td>
                                <td>$($owner.Count)</td>
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
                <div class="section-header">🏷️ Environment Distribution</div>
                <div class="section-content">
                    <table>
                        <thead>
                            <tr><th>Environment</th><th>Count</th><th>%</th></tr>
                        </thead>
                        <tbody>
"@

        foreach ($env in $environmentBreakdown | Select-Object -First 10) {
            $percentage = ($env.Count / $totalInstances * 100).ToString('F1')
            $htmlContent += @"
                            <tr>
                                <td><strong>$($env.Name)</strong></td>
                                <td>$($env.Count)</td>
                                <td>$percentage%</td>
                            </tr>
"@
        }

        $htmlContent += @"
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
        
        <div class="section">
            <div class="section-header">📋 Complete Stopped/Terminated Instances Inventory</div>
            <div class="section-content">
                <p style="margin-bottom: 15px;">Showing all $totalInstances instances (sorted by age, oldest first):</p>
                <table>
                    <thead>
                        <tr>
                            <th>Instance Name</th>
                            <th>Days Old</th>
                            <th>State</th>
                            <th>Instance Type</th>
                            <th>Region</th>
                            <th>AZ</th>
                            <th>Owner</th>
                            <th>Environment</th>
                            <th>Platform</th>
                            <th>Volume Size</th>
                            <th>Instance ID</th>
                        </tr>
                    </thead>
                    <tbody>
"@

        foreach ($instance in ($Instances | Sort-Object DaysSinceCreated -Descending)) {
            $ageClass = if ($instance.DaysSinceCreated -ge 365) { "age-critical" } 
                       elseif ($instance.DaysSinceCreated -ge 180) { "age-high" }
                       elseif ($instance.DaysSinceCreated -ge 90) { "age-medium" }
                       else { "age-low" }
            
            $stateClass = if ($instance.State -eq "stopped") { "state-stopped" } else { "state-terminated" }
            
            $htmlContent += @"
                        <tr>
                            <td><strong>$($instance.InstanceName)</strong></td>
                            <td class="$ageClass">$($instance.DaysSinceCreated)</td>
                            <td class="$stateClass">$($instance.State.ToUpper())</td>
                            <td>$($instance.InstanceType)</td>
                            <td>$($instance.Region)</td>
                            <td>$($instance.AvailabilityZone)</td>
                            <td>$($instance.Owner)</td>
                            <td>$($instance.Environment)</td>
                            <td>$($instance.Platform)</td>
                            <td>$($instance.TotalVolumeGB)GB</td>
                            <td style="font-family: monospace; font-size: 0.75rem;">$($instance.InstanceId)</td>
                        </tr>
"@
        }

        $htmlContent += @"
                    </tbody>
                </table>
            </div>
        </div>
        
        <div style="background: linear-gradient(135deg, #ff9900, #232f3e); color: white; padding: 30px; border-radius: 15px; text-align: center; margin-top: 30px;">
            <h3>🛑 AWS Stopped Instances Analysis Complete</h3>
            <p>⚡ PowerShell analysis completed in $($analysisTime.ToString('F1')) seconds</p>
            <p>📊 Found $totalInstances instances ($stoppedCount stopped, $terminatedCount terminated) across $($Script:Stats.RegionsScanned) regions</p>
            <p>🎯 Performance: $($totalInstances / $analysisTime | ForEach-Object { $_.ToString('F1') }) instances/second</p>
            <br>
            <p><strong>💡 Next Steps:</strong></p>
            <p>• Review instances over 365 days old for potential termination</p>
            <p>• Contact owners of long-running stopped instances</p>
            <p>• Consider cost optimization - stopped instances still incur EBS storage costs</p>
            <p>• Use <strong>aws ec2 terminate-instances --instance-ids INSTANCE_ID</strong> to permanently remove instances</p>
        </div>
    </div>
</body>
</html>
"@

        $htmlContent | Out-File -FilePath $htmlFile -Encoding UTF8
        Write-Success-Log "HTML report saved: $htmlFile"
        return $htmlFile
    }
    catch {
        Write-Error-Log "Failed to generate HTML report: $_"
        return ""
    }
}

function Show-Summary {
    <#
    .SYNOPSIS
    Displays summary of stopped instances
    #>
    param([object[]]$Instances)
    
    if ($Instances.Count -eq 0) {
        Write-Host "`n🎉 No stopped instances found!" -ForegroundColor Green
        return
    }
    
    $totalInstances = $Instances.Count
    $stoppedCount = ($Instances | Where-Object { $_.State -eq "stopped" }).Count
    $terminatedCount = ($Instances | Where-Object { $_.State -eq "terminated" }).Count
    $avgDays = ($Instances | Measure-Object -Property DaysSinceCreated -Average).Average
    $oldestInstance = $Instances | Sort-Object DaysSinceCreated -Descending | Select-Object -First 1
    $totalVolumeGB = ($Instances | Measure-Object -Property TotalVolumeGB -Sum).Sum
    
    # Region breakdown
    $regionCounts = $Instances | Group-Object Region | Sort-Object Count -Descending
    
    # Instance type breakdown
    $typeCounts = $Instances | Group-Object InstanceType | Sort-Object Count -Descending
    
    $analysisTime = ((Get-Date) - $Script:Stats.StartTime).TotalSeconds
    
    Write-Host "`n🛑 AWS STOPPED INSTANCES SUMMARY" -ForegroundColor Red
    Write-Host "================================" -ForegroundColor Red
    Write-Host "📊 Total instances: $totalInstances ($stoppedCount stopped, $terminatedCount terminated)" -ForegroundColor Cyan
    Write-Host "📅 Average days since created: $($avgDays.ToString('F1'))" -ForegroundColor Cyan
    Write-Host "🕰️ Oldest instance: $($oldestInstance.InstanceName) ($($oldestInstance.DaysSinceCreated) days)" -ForegroundColor Cyan
    Write-Host "💾 Total EBS storage: $totalVolumeGB GB" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "🌍 By Region:" -ForegroundColor Yellow
    foreach ($region in $regionCounts | Select-Object -First 10) {
        Write-Host "   $($region.Name): $($region.Count)" -ForegroundColor White
    }
    Write-Host ""
    
    Write-Host "⚙️ By Instance Type:" -ForegroundColor Yellow
    foreach ($type in $typeCounts | Select-Object -First 10) {
        Write-Host "   $($type.Name): $($type.Count)" -ForegroundColor White
    }
    Write-Host ""
    
    Write-Host "⏱️ Analysis completed in $($analysisTime.ToString('F1')) seconds" -ForegroundColor Green
    Write-Host "📡 Total AWS API calls made: $($Script:Stats.ApiCallsMade)" -ForegroundColor Green
}

# Main execution
function Start-AwsStoppedInstancesAnalysis {
    <#
    .SYNOPSIS
    Main function to orchestrate the analysis
    #>
    
    Write-Host "🛑 AWS Stopped Instances Lister - PowerShell Edition" -ForegroundColor Red
    Write-Host "⚡ Fast and focused - powered by AWS CLI" -ForegroundColor Cyan
    Write-Host "📅 Minimum days filter: $MinDays" -ForegroundColor Cyan
    if ($Profile) {
        Write-Host "👤 AWS Profile: $Profile" -ForegroundColor Cyan
    }
    if ($IncludeTerminated) {
        Write-Host "❌ Including terminated instances" -ForegroundColor Cyan
    }
    Write-Host ""
    
    # Test prerequisites
    Test-AwsCli
    
    # Parse input parameters
    $regionList = if ($Regions) { $Regions -split ',' | ForEach-Object { $_.Trim() } } else { @() }
    $skipRegionsList = if ($SkipRegions) { $SkipRegions -split ',' | ForEach-Object { $_.Trim() } } else { @() }
    
    # Create output directory
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    
    try {
        # Get regions to scan
        $regions = Get-AwsRegions -SpecificRegions $regionList -SkipRegionsList $skipRegionsList
        
        if ($regions.Count -eq 0) {
            Write-Error-Log "No regions found to scan"
            return
        }
        
        Write-Progress-Log "Will scan $($regions.Count) regions"
        if ($skipRegionsList.Count -gt 0) {
            Write-Warning-Log "Skipping regions: $($skipRegionsList -join ', ')"
        }
        
        # Discover stopped instances
        Start-ParallelInstanceDiscovery -Regions $regions -IncludeTerminated $IncludeTerminated
        
        if ($Script:StoppedInstances.Count -eq 0) {
            Write-Host "`n🎉 No stopped instances found!" -ForegroundColor Green
            return
        }
        
        # Filter by minimum days
        $filteredInstances = $Script:StoppedInstances | Where-Object { $_.DaysSinceCreated -ge $MinDays }
        
        if ($filteredInstances.Count -eq 0) {
            Write-Host "`n🎉 No stopped instances found over $MinDays day threshold!" -ForegroundColor Green
            return
        }
        
        Write-Progress-Log "Filtered to $($filteredInstances.Count) instances over $MinDays day threshold"
        
        # Generate reports
        $csvFile = Export-CsvReport -Instances $filteredInstances -OutputPath $OutputPath
        $htmlFile = Export-HtmlReport -Instances $filteredInstances -OutputPath $OutputPath
        
        # Show summary
        Show-Summary -Instances $filteredInstances
        
        # Display report locations
        if ($csvFile) {
            Write-Host "`n📄 CSV report: $csvFile" -ForegroundColor Green
        }
        if ($htmlFile) {
            Write-Host "🎨 HTML report: $htmlFile" -ForegroundColor Green
            
            # Try to open HTML report
            try {
                Start-Process $htmlFile
            }
            catch {
                Write-Host "💡 Open the HTML file manually to view the detailed report" -ForegroundColor Yellow
            }
        }
        
        # Show top 10 oldest instances
        Write-Host "`n🔝 TOP 10 OLDEST STOPPED INSTANCES:" -ForegroundColor Red
        Write-Host "=" * 80 -ForegroundColor Red
        
        $topInstances = $filteredInstances | Sort-Object DaysSinceCreated -Descending | Select-Object -First 10
        for ($i = 0; $i -lt $topInstances.Count; $i++) {
            $instance = $topInstances[$i]
            $stateEmoji = if ($instance.State -eq "stopped") { "⏸️" } else { "❌" }
            Write-Host "$($i + 1). $($instance.InstanceName)" -ForegroundColor White
            Write-Host "    📅 $($instance.DaysSinceCreated) days old | $stateEmoji $($instance.State.ToUpper()) | 🌍 $($instance.Region)" -ForegroundColor Gray
            Write-Host "    👤 $($instance.Owner) | ⚙️ $($instance.InstanceType) | 💾 $($instance.TotalVolumeGB)GB" -ForegroundColor Gray
            if ($instance.StopTime -ne "Unknown") {
                Write-Host "    🕐 Stopped: $($instance.StopTime)" -ForegroundColor Gray
            }
            Write-Host ""
        }
        
        Write-Host "💡 Use 'aws ec2 terminate-instances --instance-ids INSTANCE_ID --region REGION' to permanently remove instances" -ForegroundColor Yellow
        Write-Host "💡 Use 'aws ec2 start-instances --instance-ids INSTANCE_ID --region REGION' to restart stopped instances" -ForegroundColor Yellow
        
    }
    catch {
        Write-Error-Log "Analysis failed: $_"
        Write-Host $_.ScriptStackTrace -ForegroundColor Red
    }
}

# Execute the main function
Start-AwsStoppedInstancesAnalysis
