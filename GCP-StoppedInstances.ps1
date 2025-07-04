#Requires -Version 5.1
<#
================================================================================
🛑 GCP Stopped Instances Lister - PowerShell Edition
================================================================================
🎯 Purpose: List all stopped compute instances across your GCP projects
📊 Output: Clean CSV + HTML reports of stopped instances
⚡ Fast PowerShell with gcloud CLI integration
🌩️ Works with multiple projects and regions
================================================================================
.SYNOPSIS
    Lists all stopped GCP compute instances across projects and generates reports.

.DESCRIPTION
    This script scans your GCP projects for stopped compute instances and generates
    detailed CSV and HTML reports. It uses the gcloud CLI for authentication and
    data retrieval.

.PARAMETER ProjectIds
    Comma-separated list of GCP project IDs to scan. If not provided, scans all accessible projects.

.PARAMETER Zones
    Comma-separated list of specific zones to scan. If not provided, scans all zones.

.PARAMETER MinDays
    Minimum days since creation to include instances (default: 0)

.PARAMETER OutputPath
    Output directory for reports (default: current directory)

.PARAMETER MaxConcurrent
    Maximum number of concurrent operations (default: 10)

.PARAMETER SkipZones
    Comma-separated list of zones to skip

.EXAMPLE
    .\GCP-StoppedInstances.ps1
    Lists all stopped instances across all accessible projects

.EXAMPLE
    .\GCP-StoppedInstances.ps1 -ProjectIds "project1,project2" -MinDays 30
    Lists stopped instances older than 30 days in specific projects

.EXAMPLE
    .\GCP-StoppedInstances.ps1 -Zones "us-central1-a,us-east1-b"
    Lists stopped instances in specific zones only
#>

[CmdletBinding()]
param(
    [string]$ProjectIds = "",
    [string]$Zones = "",
    [int]$MinDays = 0,
    [string]$OutputPath = ".",
    [int]$MaxConcurrent = 10,
    [string]$SkipZones = ""
)

# Global variables for tracking
$Script:Stats = @{
    ProjectsScanned = 0
    ZonesScanned = 0
    StoppedInstancesFound = 0
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

function Test-GcloudAuth {
    <#
    .SYNOPSIS
    Tests if gcloud is installed and authenticated
    #>
    Write-Progress-Log "Checking gcloud authentication..."
    
    try {
        $null = Get-Command gcloud -ErrorAction Stop
        Write-Success-Log "gcloud CLI found"
    }
    catch {
        Write-Error-Log "gcloud CLI not found. Please install Google Cloud SDK."
        Write-Host "Download from: https://cloud.google.com/sdk/docs/install" -ForegroundColor Blue
        exit 1
    }
    
    try {
        $authCheck = gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>$null
        if (-not $authCheck) {
            Write-Error-Log "No active gcloud authentication found."
            Write-Host "Run: gcloud auth login" -ForegroundColor Blue
            exit 1
        }
        Write-Success-Log "gcloud authentication verified: $authCheck"
    }
    catch {
        Write-Error-Log "Failed to check gcloud authentication: $_"
        exit 1
    }
}

function Get-GcpProjects {
    <#
    .SYNOPSIS
    Gets list of accessible GCP projects
    #>
    param([string[]]$SpecificProjects = @())
    
    Write-Progress-Log "Discovering GCP projects..."
    
    try {
        if ($SpecificProjects.Count -gt 0) {
            Write-Progress-Log "Using specified projects: $($SpecificProjects -join ', ')"
            return $SpecificProjects
        }
        
        $Script:Stats.ApiCallsMade++
        $projectsJson = gcloud projects list --format="json" 2>$null
        
        if (-not $projectsJson) {
            Write-Warning-Log "No projects found or accessible"
            return @()
        }
        
        $projects = $projectsJson | ConvertFrom-Json
        $activeProjects = $projects | Where-Object { $_.lifecycleState -eq "ACTIVE" } | ForEach-Object { $_.projectId }
        
        Write-Success-Log "Found $($activeProjects.Count) active projects"
        return $activeProjects
    }
    catch {
        Write-Error-Log "Failed to get projects: $_"
        return @()
    }
}

function Get-GcpZones {
    <#
    .SYNOPSIS
    Gets list of available zones for a project
    #>
    param(
        [string]$ProjectId,
        [string[]]$SpecificZones = @(),
        [string[]]$SkipZonesList = @()
    )
    
    try {
        if ($SpecificZones.Count -gt 0) {
            return $SpecificZones | Where-Object { $_ -notin $SkipZonesList }
        }
        
        $Script:Stats.ApiCallsMade++
        $zonesJson = gcloud compute zones list --project=$ProjectId --format="json" 2>$null
        
        if (-not $zonesJson) {
            return @()
        }
        
        $zones = $zonesJson | ConvertFrom-Json
        $availableZones = $zones | Where-Object { $_.status -eq "UP" } | ForEach-Object { $_.name }
        $filteredZones = $availableZones | Where-Object { $_ -notin $SkipZonesList }
        
        return $filteredZones
    }
    catch {
        Write-Warning-Log "Failed to get zones for project $ProjectId : $_"
        return @()
    }
}

function Get-StoppedInstancesInZone {
    <#
    .SYNOPSIS
    Gets stopped instances in a specific project/zone
    #>
    param(
        [string]$ProjectId,
        [string]$Zone
    )
    
    try {
        $Script:Stats.ApiCallsMade++
        
        # Get instances with TERMINATED status (stopped in GCP)
        $instancesJson = gcloud compute instances list `
            --project=$ProjectId `
            --zones=$Zone `
            --filter="status:TERMINATED" `
            --format="json" 2>$null
        
        if (-not $instancesJson -or $instancesJson -eq "[]") {
            return @()
        }
        
        $instances = $instancesJson | ConvertFrom-Json
        
        Write-Host "📍 Found $($instances.Count) stopped instances in $ProjectId/$Zone" -ForegroundColor Green
        
        return $instances
    }
    catch {
        Write-Warning-Log "Failed to get instances in $ProjectId/$Zone : $_"
        return @()
    }
}

function Convert-GcpInstance {
    <#
    .SYNOPSIS
    Converts GCP instance to standardized format
    #>
    param(
        [object]$Instance,
        [string]$ProjectId
    )
    
    try {
        # Parse creation timestamp
        $createdDate = [DateTime]::Parse($Instance.creationTimestamp)
        $daysSinceCreated = [math]::Floor(((Get-Date) - $createdDate).TotalDays)
        
        # Extract zone from zone URL
        $zoneName = ($Instance.zone -split '/')[-1]
        
        # Extract region from zone
        $region = $zoneName -replace '-[a-z]$', ''
        
        # Get machine type
        $machineType = ($Instance.machineType -split '/')[-1]
        
        # Get labels for owner information
        $owner = "Unknown"
        if ($Instance.labels) {
            foreach ($label in $Instance.labels.PSObject.Properties) {
                if ($label.Name -match "owner|created-by|contact|team") {
                    $owner = $label.Value
                    break
                }
            }
        }
        
        # Get network tags
        $tags = if ($Instance.tags -and $Instance.tags.items) { 
            $Instance.tags.items -join ", " 
        } else { 
            "None" 
        }
        
        # Get disk information
        $diskInfo = @()
        $totalDiskSizeGB = 0
        if ($Instance.disks) {
            foreach ($disk in $Instance.disks) {
                if ($disk.diskSizeGb) {
                    $totalDiskSizeGB += [int]$disk.diskSizeGb
                    $diskType = if ($disk.boot) { "Boot" } else { "Data" }
                    $diskInfo += "$diskType`: $($disk.diskSizeGb)GB"
                }
            }
        }
        $diskSizes = if ($diskInfo.Count -gt 0) { $diskInfo -join ", " } else { "Unknown" }
        
        return [PSCustomObject]@{
            InstanceName = $Instance.name
            InstanceId = $Instance.id
            ProjectId = $ProjectId
            Zone = $zoneName
            Region = $region
            MachineType = $machineType
            Status = $Instance.status
            CreatedDate = $createdDate.ToString("yyyy-MM-dd HH:mm:ss")
            DaysSinceCreated = $daysSinceCreated
            Owner = $owner
            Tags = $tags
            DiskSizes = $diskSizes
            TotalDiskSizeGB = $totalDiskSizeGB
            SelfLink = $Instance.selfLink
            LastStartedDate = if ($Instance.lastStartTimestamp) { 
                [DateTime]::Parse($Instance.lastStartTimestamp).ToString("yyyy-MM-dd HH:mm:ss") 
            } else { 
                "Never" 
            }
            LastStoppedDate = if ($Instance.lastStopTimestamp) { 
                [DateTime]::Parse($Instance.lastStopTimestamp).ToString("yyyy-MM-dd HH:mm:ss") 
            } else { 
                "Unknown" 
            }
        }
    }
    catch {
        Write-Warning-Log "Failed to convert instance $($Instance.name): $_"
        return $null
    }
}

function Start-ParallelInstanceDiscovery {
    <#
    .SYNOPSIS
    Discovers stopped instances across projects and zones in parallel
    #>
    param(
        [string[]]$Projects,
        [string[]]$SpecificZones = @(),
        [string[]]$SkipZonesList = @()
    )
    
    Write-Progress-Log "Starting parallel discovery across $($Projects.Count) projects..."
    
    $jobs = @()
    
    foreach ($project in $Projects) {
        Write-Progress-Log "Discovering zones for project: $project"
        $zones = Get-GcpZones -ProjectId $project -SpecificZones $SpecificZones -SkipZonesList $SkipZonesList
        
        if ($zones.Count -eq 0) {
            Write-Warning-Log "No zones found for project $project"
            continue
        }
        
        Write-Progress-Log "Found $($zones.Count) zones for project $project"
        $Script:Stats.ZonesScanned += $zones.Count
        
        # Create jobs for each zone (limit concurrent jobs)
        foreach ($zone in $zones) {
            # Wait if we have too many concurrent jobs
            while ($jobs.Count -ge $MaxConcurrent) {
                $completed = $jobs | Where-Object { $_.State -eq 'Completed' -or $_.State -eq 'Failed' }
                foreach ($job in $completed) {
                    try {
                        $instances = Receive-Job -Job $job
                        if ($instances.Count -gt 0) {
                            foreach ($instance in $instances) {
                                $converted = Convert-GcpInstance -Instance $instance -ProjectId $project
                                if ($converted) {
                                    $Script:StoppedInstances += $converted
                                }
                            }
                        }
                    }
                    catch {
                        Write-Warning-Log "Job failed for $project/$zone : $_"
                    }
                    Remove-Job -Job $job
                }
                $jobs = $jobs | Where-Object { $_.State -eq 'Running' }
                Start-Sleep -Milliseconds 100
            }
            
            # Start new job for this zone
            $job = Start-Job -ScriptBlock {
                param($ProjectId, $Zone)
                
                try {
                    $instancesJson = gcloud compute instances list `
                        --project=$ProjectId `
                        --zones=$Zone `
                        --filter="status:TERMINATED" `
                        --format="json" 2>$null
                    
                    if ($instancesJson -and $instancesJson -ne "[]") {
                        return $instancesJson | ConvertFrom-Json
                    }
                    return @()
                }
                catch {
                    return @()
                }
            } -ArgumentList $project, $zone
            
            $jobs += $job
        }
        
        $Script:Stats.ProjectsScanned++
    }
    
    # Wait for all remaining jobs to complete
    Write-Progress-Log "Waiting for remaining discovery jobs to complete..."
    $jobs | Wait-Job | ForEach-Object {
        try {
            $instances = Receive-Job -Job $_
            if ($instances.Count -gt 0) {
                $projectId = $_.Name -split '_' | Select-Object -First 1
                foreach ($instance in $instances) {
                    $converted = Convert-GcpInstance -Instance $instance -ProjectId $projectId
                    if ($converted) {
                        $Script:StoppedInstances += $converted
                    }
                }
            }
        }
        catch {
            Write-Warning-Log "Failed to process job results: $_"
        }
        Remove-Job -Job $_
    }
    
    $Script:Stats.StoppedInstancesFound = $Script:StoppedInstances.Count
    Write-Progress-Log "Discovery complete: $($Script:StoppedInstances.Count) stopped instances found"
}

function Export-CsvReport {
    <#
    .SYNOPSIS
    Exports stopped instances to CSV
    #>
    param([object[]]$Instances, [string]$OutputPath)
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $csvFile = Join-Path $OutputPath "GCP_Stopped_Instances_$timestamp.csv"
    
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
    $htmlFile = Join-Path $OutputPath "GCP_Stopped_Instances_$timestamp.html"
    
    try {
        # Calculate statistics
        $totalInstances = $Instances.Count
        if ($totalInstances -eq 0) {
            return ""
        }
        
        $avgDays = ($Instances | Measure-Object -Property DaysSinceCreated -Average).Average
        $oldestInstance = $Instances | Sort-Object DaysSinceCreated -Descending | Select-Object -First 1
        $totalDiskGB = ($Instances | Measure-Object -Property TotalDiskSizeGB -Sum).Sum
        
        # Breakdowns
        $projectBreakdown = $Instances | Group-Object ProjectId | Sort-Object Count -Descending
        $regionBreakdown = $Instances | Group-Object Region | Sort-Object Count -Descending
        $machineTypeBreakdown = $Instances | Group-Object MachineType | Sort-Object Count -Descending
        $ownerBreakdown = $Instances | Group-Object Owner | Sort-Object Count -Descending
        
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
        
        # Generate HTML content
        $htmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>🛑 GCP Stopped Instances Report</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', sans-serif; background: linear-gradient(135deg, #4285f4, #34a853); color: #333; line-height: 1.6; }
        .container { max-width: 1400px; margin: 0 auto; padding: 20px; }
        .header { background: linear-gradient(135deg, #4285f4, #34a853); color: white; padding: 30px; border-radius: 15px; text-align: center; margin-bottom: 20px; box-shadow: 0 10px 30px rgba(0,0,0,0.3); }
        .header h1 { font-size: 2.5rem; margin-bottom: 10px; }
        .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 15px; margin-bottom: 20px; }
        .stat-card { background: white; padding: 20px; border-radius: 10px; text-align: center; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .stat-number { font-size: 1.8rem; font-weight: bold; color: #4285f4; margin-bottom: 5px; }
        .stat-label { color: #666; font-size: 0.85rem; }
        .section { background: white; margin: 20px 0; border-radius: 10px; overflow: hidden; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .section-header { background: linear-gradient(135deg, #4285f4, #34a853); color: white; padding: 15px; font-size: 1.2rem; font-weight: bold; }
        .section-content { padding: 15px; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 8px; text-align: left; border-bottom: 1px solid #ddd; font-size: 0.85rem; }
        th { background: #f5f5f5; font-weight: bold; }
        tr:hover { background-color: #e8f0fe; }
        .age-critical { color: #ea4335; font-weight: bold; }
        .age-high { color: #ff9800; font-weight: bold; }
        .age-medium { color: #fbc02d; font-weight: bold; }
        .age-low { color: #34a853; font-weight: bold; }
        .breakdown-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }
        .perf-note { background: #e8f0fe; border: 1px solid #4285f4; color: #1a73e8; padding: 15px; border-radius: 5px; margin: 15px 0; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🛑 GCP <span style="color: #FFE0B2;">Stopped</span> Instances Report</h1>
            <div>⚡ PowerShell + gcloud CLI Analysis - $currentTime</div>
            <div>🎯 Analysis Time: $($analysisTime.ToString('F1'))s | Projects: $($Script:Stats.ProjectsScanned)</div>
        </div>
        
        <div class="perf-note">
            <strong>📊 Analysis Summary:</strong> 
            Found $totalInstances stopped instances across $($Script:Stats.ProjectsScanned) projects and $($Script:Stats.ZonesScanned) zones | 
            API calls: $($Script:Stats.ApiCallsMade) | 
            Processing speed: $($totalInstances / $analysisTime | ForEach-Object { $_.ToString('F1') }) instances/sec
        </div>
        
        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-number">$totalInstances</div>
                <div class="stat-label">🛑 Stopped Instances</div>
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
                <div class="stat-number">$($projectBreakdown.Count)</div>
                <div class="stat-label">📁 Projects</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">$($regionBreakdown.Count)</div>
                <div class="stat-label">🌍 Regions</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">$totalDiskGB</div>
                <div class="stat-label">💾 Total Disk GB</div>
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
            <div class="section-header">🔝 Top 20 Oldest Stopped Instances</div>
            <div class="section-content">
                <table>
                    <thead>
                        <tr>
                            <th>Instance Name</th>
                            <th>Days Old</th>
                            <th>Project</th>
                            <th>Zone</th>
                            <th>Machine Type</th>
                            <th>Owner</th>
                            <th>Last Stopped</th>
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
            
            $htmlContent += @"
                        <tr>
                            <td><strong>$($instance.InstanceName)</strong></td>
                            <td class="$ageClass">$($instance.DaysSinceCreated)</td>
                            <td>$($instance.ProjectId)</td>
                            <td>$($instance.Zone)</td>
                            <td>$($instance.MachineType)</td>
                            <td>$($instance.Owner)</td>
                            <td>$($instance.LastStoppedDate)</td>
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
                <div class="section-header">📁 Project Distribution</div>
                <div class="section-content">
                    <table>
                        <thead>
                            <tr><th>Project</th><th>Count</th><th>%</th></tr>
                        </thead>
                        <tbody>
"@

        foreach ($project in $projectBreakdown | Select-Object -First 10) {
            $percentage = ($project.Count / $totalInstances * 100).ToString('F1')
            $htmlContent += @"
                            <tr>
                                <td><strong>$($project.Name)</strong></td>
                                <td>$($project.Count)</td>
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
                <div class="section-header">🌍 Region Distribution</div>
                <div class="section-content">
                    <table>
                        <thead>
                            <tr><th>Region</th><th>Count</th><th>%</th></tr>
                        </thead>
                        <tbody>
"@

        foreach ($region in $regionBreakdown | Select-Object -First 10) {
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
        </div>
        
        <div class="section">
            <div class="section-header">📋 Complete Stopped Instances Inventory</div>
            <div class="section-content">
                <p style="margin-bottom: 15px;">Showing all $totalInstances stopped instances (sorted by age, oldest first):</p>
                <table>
                    <thead>
                        <tr>
                            <th>Instance Name</th>
                            <th>Days Old</th>
                            <th>Project</th>
                            <th>Zone</th>
                            <th>Machine Type</th>
                            <th>Owner</th>
                            <th>Disk Size</th>
                            <th>Last Stopped</th>
                        </tr>
                    </thead>
                    <tbody>
"@

        foreach ($instance in ($Instances | Sort-Object DaysSinceCreated -Descending)) {
            $ageClass = if ($instance.DaysSinceCreated -ge 365) { "age-critical" } 
                       elseif ($instance.DaysSinceCreated -ge 180) { "age-high" }
                       elseif ($instance.DaysSinceCreated -ge 90) { "age-medium" }
                       else { "age-low" }
            
            $htmlContent += @"
                        <tr>
                            <td><strong>$($instance.InstanceName)</strong></td>
                            <td class="$ageClass">$($instance.DaysSinceCreated)</td>
                            <td>$($instance.ProjectId)</td>
                            <td>$($instance.Zone)</td>
                            <td>$($instance.MachineType)</td>
                            <td>$($instance.Owner)</td>
                            <td>$($instance.TotalDiskSizeGB)GB</td>
                            <td>$($instance.LastStoppedDate)</td>
                        </tr>
"@
        }

        $htmlContent += @"
                    </tbody>
                </table>
            </div>
        </div>
        
        <div style="background: linear-gradient(135deg, #4285f4, #34a853); color: white; padding: 30px; border-radius: 15px; text-align: center; margin-top: 30px;">
            <h3>🛑 GCP Stopped Instances Analysis Complete</h3>
            <p>⚡ PowerShell analysis completed in $($analysisTime.ToString('F1')) seconds</p>
            <p>📊 Found $totalInstances stopped instances across $($Script:Stats.ProjectsScanned) projects</p>
            <p>🎯 Performance: $($totalInstances / $analysisTime | ForEach-Object { $_.ToString('F1') }) instances/second</p>
            <br>
            <p><strong>💡 Next Steps:</strong></p>
            <p>• Review instances over 365 days old for potential deletion</p>
            <p>• Contact owners of long-running stopped instances</p>
            <p>• Consider cost optimization for unused resources</p>
            <p>• Use <strong>gcloud compute instances delete INSTANCE_NAME --zone=ZONE</strong> to remove instances</p>
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
    $avgDays = ($Instances | Measure-Object -Property DaysSinceCreated -Average).Average
    $oldestInstance = $Instances | Sort-Object DaysSinceCreated -Descending | Select-Object -First 1
    $totalDiskGB = ($Instances | Measure-Object -Property TotalDiskSizeGB -Sum).Sum
    
    # Project breakdown
    $projectCounts = $Instances | Group-Object ProjectId | Sort-Object Count -Descending
    
    # Region breakdown
    $regionCounts = $Instances | Group-Object Region | Sort-Object Count -Descending
    
    $analysisTime = ((Get-Date) - $Script:Stats.StartTime).TotalSeconds
    
    Write-Host "`n🛑 GCP STOPPED INSTANCES SUMMARY" -ForegroundColor Red
    Write-Host "===============================" -ForegroundColor Red
    Write-Host "📊 Total stopped instances: $totalInstances" -ForegroundColor Cyan
    Write-Host "📅 Average days since created: $($avgDays.ToString('F1'))" -ForegroundColor Cyan
    Write-Host "🕰️ Oldest instance: $($oldestInstance.InstanceName) ($($oldestInstance.DaysSinceCreated) days)" -ForegroundColor Cyan
    Write-Host "💾 Total disk space: $totalDiskGB GB" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "📁 By Project:" -ForegroundColor Yellow
    foreach ($project in $projectCounts | Select-Object -First 10) {
        Write-Host "   $($project.Name): $($project.Count)" -ForegroundColor White
    }
    Write-Host ""
    
    Write-Host "🌍 By Region:" -ForegroundColor Yellow
    foreach ($region in $regionCounts | Select-Object -First 10) {
        Write-Host "   $($region.Name): $($region.Count)" -ForegroundColor White
    }
    Write-Host ""
    
    Write-Host "⏱️ Analysis completed in $($analysisTime.ToString('F1')) seconds" -ForegroundColor Green
    Write-Host "📡 Total gcloud API calls made: $($Script:Stats.ApiCallsMade)" -ForegroundColor Green
}

# Main execution
function Start-GcpStoppedInstancesAnalysis {
    <#
    .SYNOPSIS
    Main function to orchestrate the analysis
    #>
    
    Write-Host "🛑 GCP Stopped Instances Lister - PowerShell Edition" -ForegroundColor Red
    Write-Host "⚡ Fast and focused - powered by gcloud CLI" -ForegroundColor Cyan
    Write-Host "📅 Minimum days filter: $MinDays" -ForegroundColor Cyan
    Write-Host ""
    
    # Test prerequisites
    Test-GcloudAuth
    
    # Parse input parameters
    $projectList = if ($ProjectIds) { $ProjectIds -split ',' | ForEach-Object { $_.Trim() } } else { @() }
    $zoneList = if ($Zones) { $Zones -split ',' | ForEach-Object { $_.Trim() } } else { @() }
    $skipZonesList = if ($SkipZones) { $SkipZones -split ',' | ForEach-Object { $_.Trim() } } else { @() }
    
    # Create output directory
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    
    try {
        # Get projects to scan
        $projects = Get-GcpProjects -SpecificProjects $projectList
        
        if ($projects.Count -eq 0) {
            Write-Error-Log "No projects found to scan"
            return
        }
        
        Write-Progress-Log "Will scan $($projects.Count) projects"
        if ($skipZonesList.Count -gt 0) {
            Write-Warning-Log "Skipping zones: $($skipZonesList -join ', ')"
        }
        
        # Discover stopped instances
        Start-ParallelInstanceDiscovery -Projects $projects -SpecificZones $zoneList -SkipZonesList $skipZonesList
        
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
            Write-Host "$($i + 1). $($instance.InstanceName)" -ForegroundColor White
            Write-Host "    📅 $($instance.DaysSinceCreated) days old | 🌍 $($instance.Zone) | 📁 $($instance.ProjectId)" -ForegroundColor Gray
            Write-Host "    👤 $($instance.Owner) | ⚙️ $($instance.MachineType) | 💾 $($instance.TotalDiskSizeGB)GB" -ForegroundColor Gray
            Write-Host ""
        }
        
        Write-Host "💡 Use 'gcloud compute instances delete INSTANCE_NAME --zone=ZONE --project=PROJECT_ID' to remove instances" -ForegroundColor Yellow
        
    }
    catch {
        Write-Error-Log "Analysis failed: $_"
        Write-Host $_.ScriptStackTrace -ForegroundColor Red
    }
}

# Execute the main function
Start-GcpStoppedInstancesAnalysis
