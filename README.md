# 🛑 Multicloud VM Snooze SousChef

> **Professional multicloud toolkit for discovering and analyzing stopped/deallocated compute instances across AWS, Azure, GCP, and OCI. Comprehensive PowerShell and Python scripts with enterprise-grade reporting for resource optimization.**

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://docs.microsoft.com/en-us/powershell/)
[![Python](https://img.shields.io/badge/Python-3.6%2B-green.svg)](https://www.python.org/)
[![AWS](https://img.shields.io/badge/AWS-EC2-ff9900.svg)](https://aws.amazon.com/ec2/)
[![Azure](https://img.shields.io/badge/Azure-Compute-0078d4.svg)](https://azure.microsoft.com/en-us/services/virtual-machines/)
[![GCP](https://img.shields.io/badge/GCP-Compute%20Engine-4285f4.svg)](https://cloud.google.com/compute)
[![OCI](https://img.shields.io/badge/OCI-Compute-f80000.svg)](https://www.oracle.com/cloud/compute/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![CloudCostChefs](https://img.shields.io/badge/CloudCostChefs-VM%20Snooze%20SousChef-orange.svg)](https://cloudcostchefs.com)

## 🎯 Overview

The **Multicloud VM Snooze SousChef** is a comprehensive toolkit designed to help organizations identify and analyze stopped, deallocated, or terminated compute instances across their entire multicloud infrastructure. Like a skilled sous chef organizing ingredients in a professional kitchen, these tools help you maintain clean, cost-effective cloud environments by providing detailed visibility into your instance lifecycle across all major cloud providers.

This repository contains four specialized scripts, each optimized for their respective cloud platforms:

- **🟠 AWS Stopped Instances Lister** - PowerShell script for AWS stopped EC2 instances
- **🔵 Azure VM Deallocation Detective** - PowerShell script for Azure deallocated VMs
- **🟢 GCP Stopped Instances Lister** - PowerShell script for GCP terminated instances  
- **🔴 OCI Stopped Instances Detective** - Python script for OCI stopped instances

### 🌟 Key Benefits

- **💰 Cost Optimization**: Identify stopped instances that may no longer be needed, reducing unnecessary storage costs
- **📊 Comprehensive Reporting**: Generate both CSV and HTML reports for technical analysis and executive presentation
- **⚡ High Performance**: Parallel processing across accounts, subscriptions, projects, and compartments
- **🔍 Deep Analysis**: Age-based filtering, owner detection, and detailed instance metadata
- **🌍 Multicloud Support**: Unified approach across AWS, Azure, GCP, and OCI platforms
- **🎨 Executive Dashboards**: Rich HTML reports with visual analytics and priority levels

## 🚀 Quick Start

### Choose Your Cloud Platform

| Cloud Provider | Script | Language | Use Case |
|----------------|--------|----------|----------|
| **AWS** | `AWS-StoppedInstances.ps1` | PowerShell | Stopped EC2 instances with AWS CLI integration |
| **Azure** | `Azure-VM-Deallocation-Detective.ps1` | PowerShell | Deallocated VMs with KQL-powered discovery |
| **GCP** | `GCP-StoppedInstances.ps1` | PowerShell | Terminated instances with gcloud CLI integration |
| **OCI** | `OCI-StoppedInstances.py` | Python | Stopped instances with OCI SDK |

### Universal Prerequisites

1. **Administrative Access** to your cloud environment
2. **Appropriate CLI Tools** installed and configured
3. **Proper IAM Permissions** for compute resource access
4. **PowerShell 5.1+** (for AWS/Azure/GCP scripts) or **Python 3.6+** (for OCI script)

## 📋 Platform-Specific Guides

---

## 🟠 AWS Stopped Instances Lister

### Overview
Professional PowerShell script that discovers stopped AWS EC2 instances using native AWS CLI integration with parallel processing across regions and accounts.

### Prerequisites
- **PowerShell 5.1+** with parallel job support
- **AWS CLI v2** installed and configured
- **Valid AWS credentials** configured via AWS CLI, environment variables, or IAM roles
- **EC2 read permissions** (ec2:DescribeInstances, ec2:DescribeRegions) across target regions

### Quick Start
```powershell
# Basic scan across all accessible regions
.\AWS-StoppedInstances.ps1

# Filter instances older than 30 days
.\AWS-StoppedInstances.ps1 -MinDays 30

# Scan specific regions only
.\AWS-StoppedInstances.ps1 -Regions "us-east-1,us-west-2"

# Use specific AWS profile
.\AWS-StoppedInstances.ps1 -Profile "production" -IncludeTerminated

# Adjust performance settings
.\AWS-StoppedInstances.ps1 -MaxConcurrent 15 -OutputPath "./reports"
```

### Key Features
- **🖥️ Native AWS CLI Integration**: Authenticated access and reliable data retrieval across accounts
- **🌍 Multi-Region Discovery**: Automatic region discovery or targeted regional analysis
- **🛡️ Profile Management**: Support for multiple AWS profiles with authentication verification
- **⚡ Parallel Processing**: High-performance scanning with configurable concurrency limits
- **🖥️ Instance State Analysis**: Comprehensive analysis of stopped and optionally terminated instances
- **👤 Owner Detection**: Extracts owner information from EC2 tags for accountability
- **📅 Age Analysis**: Intelligent filtering with configurable age-based lifecycle decisions
- **📊 Dual Report Formats**: CSV for analysis and HTML for executive presentation

### Parameters
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `Regions` | String | `""` | Comma-separated list of AWS regions to scan |
| `MinDays` | Integer | `0` | Minimum days since launch to include instances |
| `OutputPath` | String | `"."` | Output directory for reports |
| `MaxConcurrent` | Integer | `10` | Maximum number of concurrent operations |
| `SkipRegions` | String | `""` | Comma-separated list of regions to skip |
| `Profile` | String | `""` | AWS CLI profile to use |
| `IncludeTerminated` | Switch | `False` | Include terminated instances in addition to stopped ones |

---

## 🔵 Azure VM Deallocation Detective

### Overview
Professional PowerShell script that discovers deallocated Azure VMs using KQL-powered Azure Resource Graph queries with intelligent aging analysis and owner detection.

### Prerequisites
- **PowerShell 5.1+** with Azure PowerShell modules
- **Azure CLI** or **Azure PowerShell** authentication
- **Reader** role on target subscriptions
- **Resource Graph Reader** role for KQL queries

### Quick Start
```powershell
# Basic scan across all accessible subscriptions
.\Azure-VM-Deallocation-Detective.ps1

# Filter VMs deallocated for 30+ days
.\Azure-VM-Deallocation-Detective.ps1 -DaysThreshold 30

# Fast mode for large environments
.\Azure-VM-Deallocation-Detective.ps1 -FastMode

# Target specific subscriptions
.\Azure-VM-Deallocation-Detective.ps1 -SubscriptionIds "sub1,sub2,sub3"
```

### Key Features
- **🔍 KQL-Powered Discovery**: Azure Resource Graph queries for fast, accurate VM identification
- **📅 Intelligent Aging Analysis**: Activity Log tracking with smart estimates for historical VMs
- **👤 Owner Detection**: IDSApplicationOwner-Symphony tag priority with fallback patterns
- **📊 Dual Report Formats**: CSV for analysis and HTML for executive presentation
- **⚡ Performance Modes**: Fast Mode for large environments or Detailed Mode for comprehensive analysis
- **🔄 Multi-Subscription Support**: Parallel processing across entire Azure estate
- **💾 Storage Analysis**: OS and data disk size calculations with VM size-based estimates
- **🛡️ Enterprise Error Handling**: Comprehensive retry logic and graceful failure recovery

### Parameters
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `DaysThreshold` | Integer | `30` | Minimum days since deallocation to include VMs |
| `SubscriptionIds` | String | `""` | Comma-separated subscription IDs to scan |
| `FastMode` | Switch | `False` | Enable fast mode (skips detailed analysis) |
| `OutputPath` | String | `"."` | Output directory for reports |
| `MaxRetries` | Integer | `3` | Maximum retry attempts for failed operations |

---

## 🟢 GCP Stopped Instances Lister

### Overview
Professional PowerShell script that discovers stopped (TERMINATED) GCP compute instances using native gcloud CLI integration with parallel processing across projects and zones.

### Prerequisites
- **PowerShell 5.1+** with parallel job support
- **Google Cloud SDK** (gcloud CLI) installed and configured
- **Active gcloud authentication** with appropriate permissions
- **Compute Engine Viewer** role across target projects

### Quick Start
```powershell
# Scan all accessible projects for stopped instances
.\GCP-StoppedInstances.ps1

# Filter instances older than 30 days
.\GCP-StoppedInstances.ps1 -MinDays 30

# Scan specific projects only
.\GCP-StoppedInstances.ps1 -ProjectIds "project1,project2,project3"

# Target specific zones
.\GCP-StoppedInstances.ps1 -Zones "us-central1-a,us-east1-b"

# Adjust performance settings
.\GCP-StoppedInstances.ps1 -MaxConcurrent 15 -OutputPath "./reports"
```

### Key Features
- **🖥️ Native gcloud CLI Integration**: Authenticated access and reliable data retrieval
- **⚡ Parallel Processing**: High-performance scanning with configurable concurrency limits
- **📁 Multi-Project Discovery**: Automatic project discovery or targeted analysis
- **🌍 Zone Intelligence**: Smart zone discovery with filtering capabilities
- **👤 Owner Detection**: Comprehensive label analysis for accountability
- **📅 Age Analysis**: Intelligent filtering for lifecycle decisions
- **📊 Dual Report Formats**: CSV for analysis and HTML for executive presentation
- **📈 Performance Tracking**: Real-time progress monitoring and API statistics

### Parameters
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ProjectIds` | String | `""` | Comma-separated list of GCP project IDs to scan |
| `Zones` | String | `""` | Comma-separated list of specific zones to scan |
| `MinDays` | Integer | `0` | Minimum days since creation to include instances |
| `MaxConcurrent` | Integer | `10` | Maximum number of concurrent operations |
| `SkipZones` | String | `""` | Comma-separated list of zones to skip |
| `OutputPath` | String | `"."` | Output directory for reports |

---

## 🔴 OCI Stopped Instances Detective

### Overview
Professional Python script that discovers stopped OCI compute instances using the OCI SDK with high-performance parallel processing across regions and compartments.

### Prerequisites
- **Python 3.6+** with concurrent.futures and asyncio support
- **OCI Python SDK** installed (`pip install oci`)
- **Valid OCI config file** (~/.oci/config) with proper authentication
- **IAM permissions** for read access to compute instances and compartments

### Quick Start
```bash
# List all stopped instances across tenancy
python stopped_instances.py

# Filter instances stopped for 30+ days
python stopped_instances.py --min-days 30

# Scan specific compartments
python stopped_instances.py --compartments "ocid1.comp.oc1..xxx,ocid1.comp.oc1..yyy"

# Target specific regions
python stopped_instances.py --regions "us-ashburn-1,us-phoenix-1"

# Adjust performance settings
python stopped_instances.py --max-workers 15 --profile PROD
```

### Key Features
- **⚡ High-Performance Parallel Processing**: Configurable worker threads for optimal speed
- **🌍 Multi-Region Discovery**: Automatic region discovery or targeted analysis
- **🏢 Compartment Intelligence**: Smart compartment discovery with caching
- **👤 Owner Detection**: Comprehensive tag analysis for both freeform and defined tags
- **📅 Intelligent Age Calculation**: Timezone handling and configurable filtering
- **📊 Dual Report Formats**: Structured CSV and rich HTML with visual analytics
- **🛡️ Robust Error Handling**: Retry logic, timeout management, and graceful recovery
- **📈 Performance Tracking**: Real-time monitoring with API call statistics

### Parameters
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `--min-days` | Integer | `0` | Minimum days since creation to include instances |
| `--compartments` | String | `None` | Comma-separated compartment OCIDs |
| `--regions` | String | `None` | Comma-separated region names |
| `--profile` | String | `DEFAULT` | OCI config profile to use |
| `--max-workers` | Integer | `20` | Maximum parallel workers |
| `--output-path` | String | `"."` | Output directory for reports |

---

## 📊 Report Formats

All scripts generate two types of comprehensive reports:

### CSV Reports
- **Purpose**: Data analysis and integration with BI tools
- **Format**: Structured CSV with all instance details
- **Use Cases**: Filtering, sorting, pivot tables, automated processing
- **Fields**: Instance name/ID, age, owner, region/zone, machine type, disk sizes, timestamps

### HTML Reports
- **Purpose**: Executive presentation and visual analysis
- **Features**: 
  - Executive summary with key metrics
  - Age distribution analysis with priority levels (🔴 Critical, 🟠 High, 🟡 Medium, 🟢 Low)
  - Regional/project/compartment breakdowns
  - Top oldest instances highlighting
  - Performance metrics and API statistics
  - Interactive tables with hover effects
  - Professional styling with cloud provider branding

## 🏗️ Architecture Overview

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   PowerShell/   │    │   Cloud CLI/SDK  │    │   Cloud APIs    │
│   Python        │───▶│   Integration    │───▶│   (Compute)     │
│   Scripts       │    │                  │    │                 │
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

### AWS Requirements
- **EC2 read permissions** (`ec2:DescribeInstances`, `ec2:DescribeRegions`)
- **Valid AWS credentials** via AWS CLI, environment variables, or IAM roles
- Active AWS CLI authentication (`aws configure` or `aws sso login`)

### Azure Requirements
- **Reader** role on target subscriptions
- **Resource Graph Reader** role for KQL queries
- Azure PowerShell modules or Azure CLI authentication

### GCP Requirements
- **Compute Engine Viewer** role (`roles/compute.viewer`)
- **Project Viewer** role (`roles/viewer`) for broader access
- Active gcloud authentication (`gcloud auth login`)

### OCI Requirements
- **Compute Instance Inspector** or equivalent permissions
- Valid OCI config file with proper authentication
- Read access to compute instances and compartments

### Security Best Practices
1. **Principle of Least Privilege**: Grant only necessary permissions
2. **Service Account Usage**: Consider using service accounts for automation
3. **Audit Logging**: Enable cloud audit logs for compliance
4. **Network Security**: Run from trusted networks or secure environments
5. **Credential Management**: Use secure credential storage and rotation

## 🎨 Customization

### Owner Detection Logic
Each script includes customizable owner detection patterns:

**AWS**: Tag-based owner extraction
```powershell
# Priority order: Owner, CreatedBy, Contact, Team tags
```

**Azure**: IDSApplicationOwner-Symphony tag priority with fallback patterns
```powershell
# Priority order: IDSApplicationOwner-Symphony, Owner, CreatedBy, Contact
```

**GCP**: Label-based owner extraction
```powershell
# Priority order: owner, created-by, contact, team labels
```

**OCI**: Tag-based owner detection
```python
# Priority order: Owner, CreatedBy, Contact, ApplicationOwner tags
```

### Performance Tuning Guidelines

| Environment Size | AWS | Azure | GCP | OCI |
|------------------|-----|-------|-----|-----|
| **Small** (1-10 accounts/subscriptions/projects) | MaxConcurrent: 5-10 | Default | MaxConcurrent: 5-10 | MaxWorkers: 10-15 |
| **Medium** (10-50 accounts/subscriptions/projects) | MaxConcurrent: 10-15 | FastMode | MaxConcurrent: 10-15 | MaxWorkers: 15-20 |
| **Large** (50+ accounts/subscriptions/projects) | MaxConcurrent: 5-10 | FastMode + Filtering | MaxConcurrent: 5-10 | MaxWorkers: 10-15 |

## 🚨 Troubleshooting

### Common Issues Across All Platforms

#### Authentication Errors
**Symptoms**: Permission denied, authentication failed
**Solutions**: 
- Verify CLI authentication status
- Check IAM permissions and role assignments
- Ensure proper credential configuration

#### Rate Limiting
**Symptoms**: Timeout errors, API throttling
**Solutions**:
- Reduce concurrency parameters
- Implement delays between requests
- Use filtering to reduce API calls

#### Large Dataset Performance
**Symptoms**: Slow execution, memory issues
**Solutions**:
- Use resource filtering (accounts, subscriptions, projects, compartments)
- Increase concurrency gradually
- Process in smaller batches

### Platform-Specific Troubleshooting

#### AWS
```powershell
# Check AWS CLI configuration
aws configure list
aws sts get-caller-identity

# Test EC2 access
aws ec2 describe-instances --max-items 1
```

#### Azure
```powershell
# Check Azure PowerShell connection
Get-AzContext

# Verify Resource Graph access
Get-AzResourceGraphQuery -Query "Resources | limit 1"
```

#### GCP
```bash
# Verify gcloud authentication
gcloud auth list
gcloud projects list

# Test compute access
gcloud compute instances list --limit=1
```

#### OCI
```bash
# Test OCI configuration
oci iam user get --user-id $(oci iam user list --query 'data[0].id' --raw-output)

# Verify compute access
oci compute instance list --compartment-id <root-compartment-id> --limit 1
```

## 📈 Performance Benchmarks

### Typical Performance Metrics

| Platform | Small Environment | Medium Environment | Large Environment |
|----------|-------------------|-------------------|-------------------|
| **AWS** | 25-50 seconds | 2-4 minutes | 5-12 minutes |
| **Azure** | 30-60 seconds | 2-5 minutes | 5-15 minutes |
| **GCP** | 45-90 seconds | 3-7 minutes | 8-20 minutes |
| **OCI** | 20-45 seconds | 1-4 minutes | 4-12 minutes |

**Processing Speed**: 50-200 instances/second (depending on platform and concurrency)

### Optimization Strategies
1. **Resource Filtering**: Target specific accounts/subscriptions/projects/compartments
2. **Regional Filtering**: Focus on specific regions for faster results
3. **Concurrent Processing**: Adjust based on environment size and API limits
4. **Network Proximity**: Run from same region as cloud resources when possible

## 🤝 Contributing

We welcome contributions to improve the Multicloud VM Snooze SousChef! Here's how you can help:

### Development Setup
1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Make your changes and test thoroughly across platforms
4. Commit your changes: `git commit -m 'Add amazing feature'`
5. Push to the branch: `git push origin feature/amazing-feature`
6. Open a Pull Request

### Contribution Guidelines
- Follow language-specific best practices (PowerShell/Python)
- Include comprehensive error handling
- Add appropriate comments and documentation
- Test with multiple cloud environments
- Update README.md for new features
- Maintain consistent CloudCostChefs branding

### Areas for Contribution
- Additional cloud provider support (Alibaba Cloud, IBM Cloud)
- Enhanced reporting features and visualizations
- Performance optimizations and caching
- Additional filtering and analysis options
- Integration with ITSM tools (ServiceNow, Jira)
- Automated remediation capabilities

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **Amazon Web Services** for comprehensive AWS CLI and robust EC2 APIs
- **Microsoft Azure** for comprehensive PowerShell integration and Resource Graph
- **Google Cloud Platform** for excellent gcloud CLI and APIs
- **Oracle Cloud Infrastructure** for robust Python SDK and documentation
- **PowerShell Community** for parallel processing capabilities
- **Python Community** for concurrent programming libraries
- **CloudCostChefs Community** for feedback and feature requests
- **Contributors** who help improve these tools


**Made with ❤️ by the CloudCostChefs team**

*Helping organizations optimize their multicloud costs, one instance at a time.*

