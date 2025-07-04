# 🛑 Multicloud VM Snooze SousChef

> **Professional PowerShell script that discovers and analyzes stopped compute instances across Google Cloud Platform projects. Fast gcloud CLI integration with comprehensive CSV + HTML reporting for resource optimization.**

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://docs.microsoft.com/en-us/powershell/)
[![GCP](https://img.shields.io/badge/GCP-Compute%20Engine-4285f4.svg)](https://cloud.google.com/compute)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![CloudCostChefs](https://img.shields.io/badge/CloudCostChefs-VM%20Snooze%20SousChef-orange.svg)](https://cloudcostchefs.com)

## 🎯 Overview

The **Multicloud VM Snooze SousChef** is a comprehensive PowerShell script designed to help organizations identify and analyze stopped (TERMINATED) compute instances across their Google Cloud Platform infrastructure. Like a skilled sous chef organizing ingredients in a professional kitchen, this tool helps you maintain a clean, cost-effective cloud environment by providing detailed visibility into your instance lifecycle.

### Key Benefits

- **💰 Cost Optimization**: Identify stopped instances that may no longer be needed, reducing unnecessary storage costs
- **📊 Comprehensive Reporting**: Generate both CSV and HTML reports for technical analysis and executive presentation
- **⚡ High Performance**: Parallel processing across projects and zones with configurable concurrency
- **🔍 Deep Analysis**: Age-based filtering, owner detection, and detailed instance metadata
- **🌍 Multi-Project Support**: Scan across your entire GCP organization or target specific projects

## 🚀 Quick Start

### Prerequisites

Before running the script, ensure you have:

1. **PowerShell 5.1 or later** installed
2. **Google Cloud SDK** installed and configured
3. **Active gcloud authentication** with appropriate permissions
4. **Compute Engine Viewer** role or equivalent across target projects

### Installation

1. Clone this repository:
```bash
git clone https://github.com/cloudcostchefs/Multicloud-VM-Snooze-SousChef.git
cd Multicloud-VM-Snooze-SousChef
```

2. Verify gcloud authentication:
```bash
gcloud auth list
gcloud projects list
```

3. Run the script:
```powershell
.\GCP-StoppedInstances.ps1
```

## 📋 Usage Examples

### Basic Usage

```powershell
# Scan all accessible projects for stopped instances
.\GCP-StoppedInstances.ps1

# Filter instances older than 30 days
.\GCP-StoppedInstances.ps1 -MinDays 30

# Scan specific projects only
.\GCP-StoppedInstances.ps1 -ProjectIds "project1,project2,project3"

# Target specific zones
.\GCP-StoppedInstances.ps1 -Zones "us-central1-a,us-east1-b"

# Skip problematic zones
.\GCP-StoppedInstances.ps1 -SkipZones "europe-west1-a,asia-east1-c"

# Adjust performance settings
.\GCP-StoppedInstances.ps1 -MaxConcurrent 15 -OutputPath "./reports"
```

### Advanced Scenarios

```powershell
# Comprehensive audit of production projects
.\GCP-StoppedInstances.ps1 -ProjectIds "prod-web,prod-api,prod-data" -MinDays 7 -OutputPath "C:\Reports\GCP"

# Development environment cleanup analysis
.\GCP-StoppedInstances.ps1 -ProjectIds "dev-sandbox,test-env" -MinDays 1

# Regional analysis for cost optimization
.\GCP-StoppedInstances.ps1 -Zones "us-central1-a,us-central1-b,us-central1-c" -MinDays 14
```

## 🛠️ Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ProjectIds` | String | `""` | Comma-separated list of GCP project IDs to scan |
| `Zones` | String | `""` | Comma-separated list of specific zones to scan |
| `MinDays` | Integer | `0` | Minimum days since creation to include instances |
| `OutputPath` | String | `"."` | Output directory for reports |
| `MaxConcurrent` | Integer | `10` | Maximum number of concurrent operations |
| `SkipZones` | String | `""` | Comma-separated list of zones to skip |

## 📊 Report Outputs

The script generates two types of reports:

### CSV Report
- **Purpose**: Data analysis and integration with BI tools
- **Format**: Structured CSV with all instance details
- **Use Cases**: Filtering, sorting, pivot tables, automated processing

### HTML Report
- **Purpose**: Executive presentation and visual analysis
- **Features**: 
  - Executive summary with key metrics
  - Age distribution analysis with priority levels
  - Project and region breakdowns
  - Top oldest instances highlighting
  - Performance metrics and statistics

### Sample Report Data

| Field | Description | Example |
|-------|-------------|---------|
| InstanceName | GCP instance name | `web-server-001` |
| InstanceId | Unique instance identifier | `1234567890123456789` |
| ProjectId | GCP project ID | `my-production-project` |
| Zone | GCP zone location | `us-central1-a` |
| Region | GCP region | `us-central1` |
| MachineType | Instance machine type | `n1-standard-2` |
| DaysSinceCreated | Age in days | `45` |
| Owner | Extracted from labels | `john.doe@company.com` |
| TotalDiskSizeGB | Total disk space | `100` |
| LastStoppedDate | When instance was stopped | `2024-01-15 14:30:22` |

## 🔧 Technical Architecture

### Discovery Engine
The script employs a sophisticated discovery mechanism that:

- **Authenticates** via gcloud CLI for secure access
- **Discovers** all accessible projects automatically or uses specified projects
- **Enumerates** zones within each project, filtering out unavailable zones
- **Queries** compute instances with `status:TERMINATED` filter for efficiency
- **Processes** results in parallel using PowerShell jobs for optimal performance

### Data Processing Pipeline
1. **Instance Retrieval**: Parallel gcloud API calls across projects/zones
2. **Data Transformation**: Convert GCP JSON responses to standardized objects
3. **Enrichment**: Add calculated fields (age, owner, disk totals)
4. **Filtering**: Apply age-based and other criteria
5. **Aggregation**: Generate statistics and breakdowns
6. **Export**: Create CSV and HTML reports

### Performance Optimization
- **Parallel Execution**: Configurable concurrent job limits
- **Efficient Filtering**: Server-side filtering via gcloud CLI
- **Memory Management**: Streaming data processing to handle large datasets
- **Error Handling**: Comprehensive retry logic and graceful failure recovery

## 🏗️ Architecture Diagram

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   PowerShell    │    │   gcloud CLI     │    │   GCP APIs      │
│   Script        │───▶│   Integration    │───▶│   Compute       │
│                 │    │                  │    │   Engine        │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Parallel      │    │   Data           │    │   Report        │
│   Processing    │    │   Transformation │    │   Generation    │
│                 │    │                  │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 ▼
                    ┌─────────────────────┐
                    │   CSV + HTML        │
                    │   Reports           │
                    │                     │
                    └─────────────────────┘
```

## 🔐 Security & Permissions

### Required IAM Permissions
The script requires the following permissions across target projects:

- `compute.instances.list` - List compute instances
- `compute.zones.list` - List available zones
- `compute.projects.get` - Access project information

### Recommended IAM Roles
- **Compute Engine Viewer** (`roles/compute.viewer`)
- **Project Viewer** (`roles/viewer`) - for broader access

### Security Best Practices
1. **Principle of Least Privilege**: Grant only necessary permissions
2. **Service Account Usage**: Consider using service accounts for automation
3. **Audit Logging**: Enable Cloud Audit Logs for compliance
4. **Network Security**: Run from trusted networks or secure environments

## 🎨 Customization

### Owner Detection Logic
The script extracts owner information from GCP labels using the following priority:

1. `owner` label
2. `created-by` label  
3. `contact` label
4. `team` label

To customize owner detection, modify the `Convert-GcpInstance` function:

```powershell
# Custom owner detection logic
$owner = "Unknown"
if ($Instance.labels) {
    foreach ($label in $Instance.labels.PSObject.Properties) {
        if ($label.Name -match "your-custom-pattern") {
            $owner = $label.Value
            break
        }
    }
}
```

### Report Customization
Modify the HTML report template in the `Export-HtmlReport` function to:
- Add custom branding
- Include additional metrics
- Modify visual styling
- Add custom analysis sections

### Performance Tuning
Adjust performance parameters based on your environment:

```powershell
# For large organizations (100+ projects)
.\GCP-StoppedInstances.ps1 -MaxConcurrent 5

# For smaller environments (fast processing)
.\GCP-StoppedInstances.ps1 -MaxConcurrent 20

# For rate-limited environments
.\GCP-StoppedInstances.ps1 -MaxConcurrent 3
```

## 🚨 Troubleshooting

### Common Issues

#### Authentication Errors
```
❌ No active gcloud authentication found.
```
**Solution**: Run `gcloud auth login` and verify with `gcloud auth list`

#### Permission Denied
```
❌ Failed to get instances in project/zone: Permission denied
```
**Solution**: Verify IAM permissions and project access with `gcloud projects list`

#### Rate Limiting
```
⚠️ Timeout in region/project, retrying...
```
**Solution**: Reduce `MaxConcurrent` parameter or add delays

#### Large Dataset Performance
```
Script running slowly with many projects
```
**Solution**: 
- Use project filtering (`-ProjectIds`)
- Increase `MaxConcurrent` gradually
- Use zone filtering for targeted analysis

### Debug Mode
Enable verbose output for troubleshooting:

```powershell
$VerbosePreference = "Continue"
.\GCP-StoppedInstances.ps1 -Verbose
```

### Log Analysis
The script provides real-time progress logging:
- ⚡ Progress updates with timing
- ✅ Success confirmations
- ⚠️ Warning messages for non-critical issues
- ❌ Error messages for failures

## 📈 Performance Benchmarks

### Typical Performance Metrics
- **Small Environment** (1-5 projects): 30-60 seconds
- **Medium Environment** (10-25 projects): 2-5 minutes  
- **Large Environment** (50+ projects): 5-15 minutes
- **Processing Speed**: 50-200 instances/second (depending on concurrency)

### Optimization Tips
1. **Use Project Filtering**: Target specific projects to reduce scope
2. **Zone Filtering**: Focus on specific regions for faster results
3. **Concurrent Jobs**: Start with 10, adjust based on performance
4. **Network Location**: Run from same region as GCP resources when possible

## 🤝 Contributing

We welcome contributions to improve the Multicloud VM Snooze SousChef! Here's how you can help:

### Development Setup
1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Make your changes and test thoroughly
4. Commit your changes: `git commit -m 'Add amazing feature'`
5. Push to the branch: `git push origin feature/amazing-feature`
6. Open a Pull Request

### Contribution Guidelines
- Follow PowerShell best practices and style guidelines
- Include comprehensive error handling
- Add appropriate comments and documentation
- Test with multiple GCP environments
- Update README.md for new features

### Areas for Contribution
- Additional cloud provider support (AWS, Azure)
- Enhanced reporting features
- Performance optimizations
- Additional filtering options
- Integration with other tools

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **Google Cloud Platform** for providing comprehensive APIs
- **PowerShell Community** for excellent parallel processing capabilities
- **CloudCostChefs Community** for feedback and feature requests
- **Contributors** who help improve this tool

## 📞 Support

### Documentation
- [CloudCostChefs Tools](https://cloudcostchefs.com/tools/gcp-stopped-instances-lister)
- [GCP Optimization Guide](https://cloudcostchefs.com/learn/cloud-optimization-gcp)

### Professional Support
For enterprise support, custom development, or consulting services, contact us at [support@cloudcostchefs.com](mailto:support@cloudcostchefs.com).

---

**Made with ❤️ by the CloudCostChefs team**

*Helping organizations optimize their cloud costs, one instance at a time.*

