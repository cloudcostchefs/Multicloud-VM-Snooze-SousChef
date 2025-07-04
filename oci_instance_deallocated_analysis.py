#!/usr/bin/env python3
"""
================================================================================
🛑 Simple OCI Stopped Instances Lister
================================================================================
🎯 Purpose: List all stopped compute instances across your OCI tenancy
📊 Output: Clean CSV report of stopped instances
⚡ Simple and fast - no complex analysis, just the facts
================================================================================
"""

import argparse
import csv
import logging
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from typing import List, Dict, Optional

try:
    import oci
    from oci.config import from_file, validate_config
    from oci.identity import IdentityClient
    from oci.core import ComputeClient
    from oci.exceptions import ServiceError, ConfigFileNotFound
except ImportError:
    print("❌ OCI SDK not installed. Install with: pip install oci")
    sys.exit(1)


@dataclass
class StoppedInstance:
    """Simple data class for stopped instances"""
    instance_name: str
    instance_id: str
    shape: str
    region: str
    availability_domain: str
    compartment_name: str
    compartment_id: str
    time_created: str
    days_since_created: int
    instance_owner: str
    fault_domain: str
    image_id: str


class SimpleStoppedInstanceLister:
    """Simple OCI stopped instance lister"""
    
    def __init__(self, config_profile: str = "DEFAULT", tenancy_id: Optional[str] = None, max_workers: int = 20):
        self.config_profile = config_profile
        self.tenancy_id = tenancy_id
        self.max_workers = max_workers
        
        # Performance tracking
        self.start_time = time.time()
        self.stats = {
            'regions_scanned': 0,
            'compartments_scanned': 0,
            'stopped_instances_found': 0,
            'api_calls_made': 0
        }
        
        # Setup logging
        logging.basicConfig(
            level=logging.INFO,
            format='[%(asctime)s] %(levelname)s: %(message)s',
            datefmt='%H:%M:%S'
        )
        self.logger = logging.getLogger(__name__)
        
        # Initialize OCI config
        self._setup_oci_config()
        
        # Cache for compartments and regions
        self.compartment_cache: Dict[str, str] = {}
        self.region_cache: List[str] = []

    def _setup_oci_config(self):
        """Setup and validate OCI configuration"""
        try:
            self.config = from_file(profile_name=self.config_profile)
            validate_config(self.config)
            
            # Add reasonable timeouts
            self.config['timeout'] = (30, 300)  # 30s connect, 300s read
            self.config['retry_strategy'] = oci.retry.DEFAULT_RETRY_STRATEGY
            
            if not self.tenancy_id:
                self.tenancy_id = self.config.get('tenancy')
                
            if not self.tenancy_id:
                raise ValueError("Tenancy ID not found in config or provided")
                
            self.logger.info(f"✅ OCI config validated for profile: {self.config_profile}")
            self.logger.info(f"🏢 Using tenancy: {self.tenancy_id}")
            
        except ConfigFileNotFound:
            self.logger.error("❌ OCI config file not found. Run 'oci setup config'")
            sys.exit(1)
        except Exception as e:
            self.logger.error(f"❌ OCI config error: {e}")
            sys.exit(1)
    
    def log_progress(self, message: str):
        """Progress logging"""
        elapsed = time.time() - self.start_time
        self.logger.info(f"⚡ [{elapsed:.1f}s] {message}")
    
    def get_subscribed_regions(self) -> List[str]:
        """Get all subscribed regions"""
        if self.region_cache:
            return self.region_cache
            
        try:
            identity_client = IdentityClient(self.config)
            self.stats['api_calls_made'] += 1
            
            region_subscriptions = identity_client.list_region_subscriptions(
                tenancy_id=self.tenancy_id
            ).data
            
            self.region_cache = [
                region.region_name 
                for region in region_subscriptions 
                if region.status == "READY"
            ]
            
            self.log_progress(f"Found {len(self.region_cache)} subscribed regions")
            return self.region_cache
            
        except Exception as e:
            self.logger.warning(f"⚠️ Error getting regions: {e}")
            # Fallback to common regions
            self.region_cache = ["us-ashburn-1", "us-phoenix-1"]
            return self.region_cache
    
    def get_all_compartments(self, compartment_ids: Optional[List[str]] = None) -> Dict[str, str]:
        """Get all compartments"""
        if self.compartment_cache:
            return self.compartment_cache
            
        try:
            identity_client = IdentityClient(self.config)
            
            if compartment_ids:
                # Get specific compartments
                for comp_id in compartment_ids:
                    try:
                        self.stats['api_calls_made'] += 1
                        comp = identity_client.get_compartment(compartment_id=comp_id).data
                        self.compartment_cache[comp_id] = comp.name
                    except:
                        self.compartment_cache[comp_id] = "Unknown"
            else:
                # Get all accessible compartments
                self.stats['api_calls_made'] += 1
                compartments = identity_client.list_compartments(
                    compartment_id=self.tenancy_id,
                    compartment_id_in_subtree=True,
                    access_level="ACCESSIBLE"
                ).data
                
                for comp in compartments:
                    if comp.lifecycle_state == "ACTIVE":
                        self.compartment_cache[comp.id] = comp.name
                
                # Add root compartment
                try:
                    self.stats['api_calls_made'] += 1
                    tenancy = identity_client.get_tenancy(tenancy_id=self.tenancy_id).data
                    self.compartment_cache[self.tenancy_id] = f"{tenancy.name} (Root)"
                except:
                    self.compartment_cache[self.tenancy_id] = "Root Compartment"
            
            self.log_progress(f"Found {len(self.compartment_cache)} compartments")
            return self.compartment_cache
            
        except Exception as e:
            self.logger.warning(f"⚠️ Error getting compartments: {e}")
            self.compartment_cache = {self.tenancy_id: "Root Compartment"}
            return self.compartment_cache
    
    def get_stopped_instances_in_region_compartment(self, region: str, compartment_id: str) -> List[dict]:
        """Get stopped instances in specific region/compartment with retry logic"""
        max_retries = 3
        retry_delay = 5
        
        for attempt in range(max_retries):
            try:
                # Create region-specific config with longer timeout
                region_config = self.config.copy()
                region_config['region'] = region
                region_config['timeout'] = (30, 300)  # Extended timeout
                
                compute_client = ComputeClient(region_config)
                
                # Get only STOPPED instances
                self.stats['api_calls_made'] += 1
                instances = compute_client.list_instances(
                    compartment_id=compartment_id,
                    lifecycle_state="STOPPED"
                ).data
                
                return instances
                
            except Exception as e:
                comp_name = self.compartment_cache.get(compartment_id, "Unknown")
                
                if attempt < max_retries - 1:
                    if any(keyword in str(e).lower() for keyword in ['timeout', 'connection', 'max retries']):
                        self.logger.warning(f"⚠️ Timeout in {region}/{comp_name}, retrying in {retry_delay}s (attempt {attempt + 1}/{max_retries})")
                        time.sleep(retry_delay)
                        retry_delay *= 2  # Exponential backoff
                        continue
                
                self.logger.warning(f"⚠️ Failed to get instances in {region}/{comp_name}: {e}")
                return []
        
        return []
    
    def get_owner_from_tags(self, defined_tags: dict, freeform_tags: dict) -> str:
        """Extract owner from tags"""
        # Check freeform tags first
        if freeform_tags:
            for key in ['Owner', 'CreatedBy', 'Contact', 'Maintainer', 'Team']:
                if key in freeform_tags:
                    return freeform_tags[key]
        
        # Check defined tags
        if defined_tags:
            for namespace, tags in defined_tags.items():
                if isinstance(tags, dict):
                    for key in ['Owner', 'CreatedBy', 'Contact', 'ApplicationOwner']:
                        if key in tags:
                            return tags[key]
        
        return "Unknown"
    
    def calculate_days_since_created(self, time_created: str) -> int:
        """Calculate days since instance creation"""
        try:
            if not time_created:
                return 0
            
            # Handle different datetime formats
            if isinstance(time_created, str):
                # Remove timezone info if present and parse
                time_str = time_created.replace('+00:00', '').replace('Z', '')
                if '.' in time_str:
                    # Handle microseconds
                    created_dt = datetime.fromisoformat(time_str).replace(tzinfo=timezone.utc)
                else:
                    created_dt = datetime.fromisoformat(time_str + '+00:00')
            else:
                # Already a datetime object
                created_dt = time_created
                if created_dt.tzinfo is None:
                    created_dt = created_dt.replace(tzinfo=timezone.utc)
            
            now = datetime.now(timezone.utc)
            days = (now - created_dt).days
            
            return max(0, days)
            
        except Exception as e:
            # Debug the issue
            print(f"DEBUG: Error calculating days for {time_created}: {e}")
            return 0
    
    def test_date_calculation(self):
        """Test date calculation with your example"""
        test_date = "2025-04-15 08:24:12.086000+00:00"
        days = self.calculate_days_since_created(test_date)
        print(f"DEBUG: Date {test_date} -> {days} days ago")
        
        # Expected result should be around 80 days
        expected = (datetime.now(timezone.utc) - datetime(2025, 4, 15, tzinfo=timezone.utc)).days
        print(f"DEBUG: Expected approximately {expected} days")
    
    def process_stopped_instance(self, instance: dict, region: str) -> StoppedInstance:
        """Process a single stopped instance"""
        # Get compartment name
        compartment_name = self.compartment_cache.get(instance.compartment_id, "Unknown")
        
        # Get owner from tags
        owner = self.get_owner_from_tags(
            getattr(instance, 'defined_tags', {}),
            getattr(instance, 'freeform_tags', {})
        )
        
        # Calculate days since creation
        days_since_created = self.calculate_days_since_created(instance.time_created)
        
        # Create result
        result = StoppedInstance(
            instance_name=instance.display_name,
            instance_id=instance.id,
            shape=instance.shape,
            region=region,
            availability_domain=getattr(instance, 'availability_domain', 'Unknown'),
            compartment_name=compartment_name,
            compartment_id=instance.compartment_id,
            time_created=instance.time_created,
            days_since_created=days_since_created,
            instance_owner=owner,
            fault_domain=getattr(instance, 'fault_domain', 'Unknown'),
            image_id=getattr(instance, 'image_id', 'Unknown')
        )
        
        return result
    
    def discover_stopped_instances(self, regions: List[str], compartment_ids: List[str]) -> List[dict]:
        """Discover stopped instances across regions/compartments"""
        all_instances = []
        
        # Create tasks for parallel execution
        tasks = []
        for region in regions:
            for compartment_id in compartment_ids:
                tasks.append((region, compartment_id))
        
        self.log_progress(f"Scanning {len(tasks)} region/compartment combinations for STOPPED instances")
        
        # Execute in parallel
        with ThreadPoolExecutor(max_workers=self.max_workers) as executor:
            # Submit all tasks
            future_to_task = {
                executor.submit(self.get_stopped_instances_in_region_compartment, region, compartment_id): (region, compartment_id)
                for region, compartment_id in tasks
            }
            
            # Collect results
            completed_tasks = 0
            for future in as_completed(future_to_task):
                region, compartment_id = future_to_task[future]
                try:
                    instances = future.result()
                    if instances:
                        # Add region info to instances
                        for instance in instances:
                            instance.region = region
                        all_instances.extend(instances)
                        
                        comp_name = self.compartment_cache.get(compartment_id, "Unknown")
                        self.logger.info(f"📍 Found {len(instances)} stopped instances in {region}/{comp_name}")
                        
                    completed_tasks += 1
                    if completed_tasks % 10 == 0:
                        self.log_progress(f"Completed {completed_tasks}/{len(tasks)} scans")
                        
                except Exception as e:
                    comp_name = self.compartment_cache.get(compartment_id, "Unknown")
                    self.logger.warning(f"⚠️ Scan failed for {region}/{comp_name}: {e}")
        
        self.stats['stopped_instances_found'] = len(all_instances)
        self.log_progress(f"Discovery complete: {len(all_instances)} stopped instances found")
        
        return all_instances
    
    def process_instances(self, instances: List[dict], min_days: int = 0) -> List[StoppedInstance]:
        """Process stopped instances"""
        results = []
        
        self.log_progress(f"Processing {len(instances)} stopped instances")
        
        for instance in instances:
            try:
                result = self.process_stopped_instance(instance, getattr(instance, 'region', 'unknown'))
                
                # Filter by minimum days if specified
                if result.days_since_created >= min_days:
                    results.append(result)
                    
            except Exception as e:
                self.logger.warning(f"⚠️ Error processing instance {instance.id}: {e}")
                continue
        
        # Sort by days since created (oldest first)
        results.sort(key=lambda x: x.days_since_created, reverse=True)
        
        self.log_progress(f"Processing complete: {len(results)} instances over {min_days} day threshold")
        return results
    
    def generate_csv_report(self, results: List[StoppedInstance], output_path: str) -> str:
        """Generate CSV report"""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        csv_file = f"{output_path}/Stopped_Instances_{timestamp}.csv"
        
        with open(csv_file, 'w', newline='', encoding='utf-8') as f:
            if results:
                writer = csv.DictWriter(f, fieldnames=asdict(results[0]).keys())
                writer.writeheader()
                for result in results:
                    writer.writerow(asdict(result))
        
        self.log_progress(f"CSV report saved: {csv_file}")
        return csv_file
    
    def generate_html_report(self, results: List[StoppedInstance], output_path: str) -> str:
        """Generate HTML report for stopped instances"""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        html_file = f"{output_path}/Stopped_Instances_{timestamp}.html"
        
        # Calculate statistics
        total_instances = len(results)
        if total_instances == 0:
            return ""
        
        avg_days = sum(r.days_since_created for r in results) / total_instances
        oldest_instance = max(results, key=lambda x: x.days_since_created)
        
        # Breakdowns
        region_breakdown = {}
        compartment_breakdown = {}
        shape_breakdown = {}
        owner_breakdown = {}
        
        for result in results:
            region_breakdown[result.region] = region_breakdown.get(result.region, 0) + 1
            compartment_breakdown[result.compartment_name] = compartment_breakdown.get(result.compartment_name, 0) + 1
            shape_breakdown[result.shape] = shape_breakdown.get(result.shape, 0) + 1
            owner_breakdown[result.instance_owner] = owner_breakdown.get(result.instance_owner, 0) + 1
        
        # Age distribution
        age_ranges = {"0-29 days": 0, "30-89 days": 0, "90-179 days": 0, "180-364 days": 0, "365+ days": 0}
        for result in results:
            if result.days_since_created < 30:
                age_ranges["0-29 days"] += 1
            elif result.days_since_created < 90:
                age_ranges["30-89 days"] += 1
            elif result.days_since_created < 180:
                age_ranges["90-179 days"] += 1
            elif result.days_since_created < 365:
                age_ranges["180-364 days"] += 1
            else:
                age_ranges["365+ days"] += 1
        
        # Generate HTML
        html_content = f"""
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>🛑 OCI Stopped Instances Report</title>
        <style>
            * {{ margin: 0; padding: 0; box-sizing: border-box; }}
            body {{ font-family: 'Segoe UI', sans-serif; background: linear-gradient(135deg, #dc3545, #fd7e14); color: #333; line-height: 1.6; }}
            .container {{ max-width: 1400px; margin: 0 auto; padding: 20px; }}
            .header {{ background: linear-gradient(135deg, #dc3545, #fd7e14); color: white; padding: 30px; border-radius: 15px; text-align: center; margin-bottom: 20px; box-shadow: 0 10px 30px rgba(0,0,0,0.3); }}
            .header h1 {{ font-size: 2.5rem; margin-bottom: 10px; }}
            .stats-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 15px; margin-bottom: 20px; }}
            .stat-card {{ background: white; padding: 20px; border-radius: 10px; text-align: center; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }}
            .stat-number {{ font-size: 1.8rem; font-weight: bold; color: #dc3545; margin-bottom: 5px; }}
            .stat-label {{ color: #666; font-size: 0.85rem; }}
            .section {{ background: white; margin: 20px 0; border-radius: 10px; overflow: hidden; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }}
            .section-header {{ background: linear-gradient(135deg, #dc3545, #fd7e14); color: white; padding: 15px; font-size: 1.2rem; font-weight: bold; }}
            .section-content {{ padding: 15px; }}
            table {{ width: 100%; border-collapse: collapse; }}
            th, td {{ padding: 8px; text-align: left; border-bottom: 1px solid #ddd; font-size: 0.85rem; }}
            th {{ background: #f5f5f5; font-weight: bold; }}
            tr:hover {{ background-color: #fff3e0; }}
            .age-critical {{ color: #dc3545; font-weight: bold; }}
            .age-high {{ color: #fd7e14; font-weight: bold; }}
            .age-medium {{ color: #ffc107; font-weight: bold; }}
            .age-low {{ color: #28a745; font-weight: bold; }}
            .breakdown-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }}
            .perf-note {{ background: #e3f2fd; border: 1px solid #2196f3; color: #1976d2; padding: 15px; border-radius: 5px; margin: 15px 0; }}
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1>🛑 OCI <span style="color: #FFE0B2;">Stopped</span> Instances Report</h1>
                <div>⚡ Simple & Fast Analysis - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</div>
                <div>🎯 Profile: {self.config_profile} | ⏱️ Analysis Time: {time.time() - self.start_time:.1f}s</div>
            </div>
            
            <div class="perf-note">
                <strong>📊 Analysis Summary:</strong> 
                Found {total_instances} stopped instances across {self.stats['regions_scanned']} regions and {self.stats['compartments_scanned']} compartments | 
                API calls: {self.stats['api_calls_made']} | 
                Processing speed: {total_instances / (time.time() - self.start_time):.1f} instances/sec
            </div>
            
            <div class="stats-grid">
                <div class="stat-card">
                    <div class="stat-number">{total_instances}</div>
                    <div class="stat-label">🛑 Stopped Instances</div>
                </div>
                <div class="stat-card">
                    <div class="stat-number">{avg_days:.1f}</div>
                    <div class="stat-label">📅 Avg Days Old</div>
                </div>
                <div class="stat-card">
                    <div class="stat-number">{oldest_instance.days_since_created}</div>
                    <div class="stat-label">🕰️ Oldest Instance</div>
                </div>
                <div class="stat-card">
                    <div class="stat-number">{len(set(r.region for r in results))}</div>
                    <div class="stat-label">🌍 Regions</div>
                </div>
                <div class="stat-card">
                    <div class="stat-number">{len(set(r.compartment_name for r in results))}</div>
                    <div class="stat-label">🏢 Compartments</div>
                </div>
                <div class="stat-card">
                    <div class="stat-number">{len(set(r.shape for r in results))}</div>
                    <div class="stat-label">⚙️ Instance Types</div>
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
                        <tbody>"""
        
        for age_range, count in age_ranges.items():
            percentage = (count / total_instances * 100) if total_instances > 0 else 0
            if "365+" in age_range:
                priority = "🔴 CRITICAL"
                age_class = "age-critical"
            elif "180-364" in age_range:
                priority = "🟠 HIGH"
                age_class = "age-high"
            elif "90-179" in age_range:
                priority = "🟡 MEDIUM"
                age_class = "age-medium"
            else:
                priority = "🟢 LOW"
                age_class = "age-low"
            
            html_content += f"""
                            <tr>
                                <td><strong>{age_range}</strong></td>
                                <td>{count}</td>
                                <td>{percentage:.1f}%</td>
                                <td class="{age_class}">{priority}</td>
                            </tr>"""
        
        html_content += f"""
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
                                <th>Created Date</th>
                                <th>Shape</th>
                                <th>Region</th>
                                <th>Compartment</th>
                                <th>Owner</th>
                                <th>Availability Domain</th>
                            </tr>
                        </thead>
                        <tbody>"""
        
        # Show top 20 oldest instances
        top_instances = sorted(results, key=lambda x: x.days_since_created, reverse=True)[:20]
        for instance in top_instances:
            if instance.days_since_created >= 365:
                age_class = "age-critical"
            elif instance.days_since_created >= 180:
                age_class = "age-high"
            elif instance.days_since_created >= 90:
                age_class = "age-medium"
            else:
                age_class = "age-low"
            
            try:
                created_date = datetime.fromisoformat(instance.time_created.replace('Z', '+00:00')).strftime('%Y-%m-%d')
            except:
                created_date = str(instance.time_created)[:10] if instance.time_created else "Unknown"
            
            html_content += f"""
                            <tr>
                                <td><strong>{instance.instance_name}</strong></td>
                                <td class="{age_class}">{instance.days_since_created}</td>
                                <td>{created_date}</td>
                                <td>{instance.shape}</td>
                                <td>{instance.region}</td>
                                <td>{instance.compartment_name}</td>
                                <td>{instance.instance_owner}</td>
                                <td>{instance.availability_domain}</td>
                            </tr>"""
        
        html_content += f"""
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
                            <tbody>"""
        
        for region, count in sorted(region_breakdown.items(), key=lambda x: x[1], reverse=True):
            percentage = (count / total_instances * 100) if total_instances > 0 else 0
            html_content += f"""
                                <tr>
                                    <td><strong>{region}</strong></td>
                                    <td>{count}</td>
                                    <td>{percentage:.1f}%</td>
                                </tr>"""
        
        html_content += f"""
                            </tbody>
                        </table>
                    </div>
                </div>
                
                <div class="section">
                    <div class="section-header">🏢 Compartment Distribution</div>
                    <div class="section-content">
                        <table>
                            <thead>
                                <tr><th>Compartment</th><th>Count</th><th>%</th></tr>
                            </thead>
                            <tbody>"""
        
        for compartment, count in sorted(compartment_breakdown.items(), key=lambda x: x[1], reverse=True)[:15]:
            percentage = (count / total_instances * 100) if total_instances > 0 else 0
            html_content += f"""
                                <tr>
                                    <td><strong>{compartment}</strong></td>
                                    <td>{count}</td>
                                    <td>{percentage:.1f}%</td>
                                </tr>"""
        
        html_content += f"""
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>
            
            <div class="breakdown-grid">
                <div class="section">
                    <div class="section-header">⚙️ Instance Shape Distribution</div>
                    <div class="section-content">
                        <table>
                            <thead>
                                <tr><th>Shape</th><th>Count</th><th>%</th></tr>
                            </thead>
                            <tbody>"""
        
        for shape, count in sorted(shape_breakdown.items(), key=lambda x: x[1], reverse=True)[:10]:
            percentage = (count / total_instances * 100) if total_instances > 0 else 0
            html_content += f"""
                                <tr>
                                    <td><strong>{shape}</strong></td>
                                    <td>{count}</td>
                                    <td>{percentage:.1f}%</td>
                                </tr>"""
        
        html_content += f"""
                            </tbody>
                        </table>
                    </div>
                </div>
                
                <div class="section">
                    <div class="section-header">👤 Instance Owner Distribution</div>
                    <div class="section-content">
                        <table>
                            <thead>
                                <tr><th>Owner</th><th>Count</th><th>%</th></tr>
                            </thead>
                            <tbody>"""
        
        for owner, count in sorted(owner_breakdown.items(), key=lambda x: x[1], reverse=True)[:10]:
            percentage = (count / total_instances * 100) if total_instances > 0 else 0
            html_content += f"""
                                <tr>
                                    <td><strong>{owner}</strong></td>
                                    <td>{count}</td>
                                    <td>{percentage:.1f}%</td>
                                </tr>"""
        
        html_content += f"""
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>
            
            <div class="section">
                <div class="section-header">📋 Complete Stopped Instances Inventory</div>
                <div class="section-content">
                    <p style="margin-bottom: 15px;">Showing all {total_instances} stopped instances (sorted by age, oldest first):</p>
                    <table>
                        <thead>
                            <tr>
                                <th>Instance Name</th>
                                <th>Days Old</th>
                                <th>Created</th>
                                <th>Shape</th>
                                <th>Region</th>
                                <th>Compartment</th>
                                <th>Owner</th>
                                <th>Instance ID</th>
                            </tr>
                        </thead>
                        <tbody>"""
        
        # Show all instances
        for instance in results:
            if instance.days_since_created >= 365:
                age_class = "age-critical"
            elif instance.days_since_created >= 180:
                age_class = "age-high"
            elif instance.days_since_created >= 90:
                age_class = "age-medium"
            else:
                age_class = "age-low"
            
            try:
                created_date = datetime.fromisoformat(instance.time_created.replace('Z', '+00:00')).strftime('%Y-%m-%d')
            except:
                created_date = str(instance.time_created)[:10] if instance.time_created else "Unknown"
            
            html_content += f"""
                            <tr>
                                <td><strong>{instance.instance_name}</strong></td>
                                <td class="{age_class}">{instance.days_since_created}</td>
                                <td>{created_date}</td>
                                <td>{instance.shape}</td>
                                <td>{instance.region}</td>
                                <td>{instance.compartment_name}</td>
                                <td>{instance.instance_owner}</td>
                                <td style="font-family: monospace; font-size: 0.75rem;">{instance.instance_id}</td>
                            </tr>"""
        
        html_content += f"""
                        </tbody>
                    </table>
                </div>
            </div>
            
            <div style="background: linear-gradient(135deg, #dc3545, #fd7e14); color: white; padding: 30px; border-radius: 15px; text-align: center; margin-top: 30px;">
                <h3>🛑 Stopped Instances Analysis Complete</h3>
                <p>⚡ Analysis completed in {time.time() - self.start_time:.1f} seconds</p>
                <p>📊 Found {total_instances} stopped instances across {self.stats['regions_scanned']} regions</p>
                <p>🎯 Performance: {total_instances / (time.time() - self.start_time):.1f} instances/second</p>
                <br>
                <p><strong>💡 Next Steps:</strong></p>
                <p>• Review instances over 365 days old for potential deletion</p>
                <p>• Contact owners of long-running stopped instances</p>
                <p>• Consider cost optimization for unused resources</p>
            </div>
        </div>
    </body>
    </html>"""
        
        with open(html_file, 'w', encoding='utf-8') as f:
            f.write(html_content)
        
        self.log_progress(f"HTML report saved: {html_file}")
        return html_file
    
    def generate_summary_report(self, results: List[StoppedInstance]) -> str:
        """Generate simple text summary"""
        if not results:
            return "No stopped instances found."
        
        # Calculate stats
        total_instances = len(results)
        avg_days = sum(r.days_since_created for r in results) / total_instances
        oldest_instance = max(results, key=lambda x: x.days_since_created)
        
        # Count by region
        region_counts = {}
        for result in results:
            region_counts[result.region] = region_counts.get(result.region, 0) + 1
        
        # Count by compartment
        compartment_counts = {}
        for result in results:
            compartment_counts[result.compartment_name] = compartment_counts.get(result.compartment_name, 0) + 1
        
        summary = f"""
🛑 STOPPED INSTANCES SUMMARY
===========================
📊 Total stopped instances: {total_instances}
📅 Average days since created: {avg_days:.1f}
🕰️ Oldest instance: {oldest_instance.instance_name} ({oldest_instance.days_since_created} days)

🌍 By Region:
{chr(10).join(f"   {region}: {count}" for region, count in sorted(region_counts.items()))}

🏢 By Compartment (Top 10):
{chr(10).join(f"   {comp}: {count}" for comp, count in sorted(compartment_counts.items(), key=lambda x: x[1], reverse=True)[:10])}

⏱️ Analysis completed in {time.time() - self.start_time:.1f} seconds
📡 Total API calls made: {self.stats['api_calls_made']}
        """
        
        return summary
    
    def list_stopped_instances(self, regions: List[str] = None, compartment_ids: List[str] = None,
                             min_days: int = 0, output_path: str = ".") -> tuple:
        """Main method to list stopped instances"""
        
        # Get regions and compartments
        if not regions:
            regions = self.get_subscribed_regions()
        
        self.stats['regions_scanned'] = len(regions)
        
        compartments = self.get_all_compartments(compartment_ids)
        compartment_list = list(compartments.keys())
        self.stats['compartments_scanned'] = len(compartment_list)
        
        self.log_progress(f"Starting scan: {len(regions)} regions, {len(compartment_list)} compartments")
        
        # Discover stopped instances
        stopped_instances = self.discover_stopped_instances(regions, compartment_list)
        
        if not stopped_instances:
            self.logger.info("🎉 No stopped instances found!")
            return [], "", ""
        
        # Process instances
        results = self.process_instances(stopped_instances, min_days)
        
        if not results:
            self.logger.info(f"🎉 No stopped instances found over {min_days} day threshold!")
            return [], "", ""
        
        # Generate reports
        csv_file = self.generate_csv_report(results, output_path)
        html_file = self.generate_html_report(results, output_path)
        summary = self.generate_summary_report(results)
        
        return results, csv_file, html_file, summary


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description="🛑 Simple OCI Stopped Instances Lister",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # List all stopped instances
  python stopped_instances.py
  
  # Only instances stopped for 30+ days
  python stopped_instances.py --min-days 30
  
  # Specific compartments and regions
  python stopped_instances.py --compartments ocid1.comp.oc1..xxx --regions us-ashburn-1
  
  # Use different OCI profile
  python stopped_instances.py --profile PROD
        """
    )
    
    parser.add_argument('--min-days', type=int, default=0,
                        help='Minimum days since creation (default: 0)')
    parser.add_argument('--compartments', type=str,
                        help='Comma-separated compartment OCIDs')
    parser.add_argument('--regions', type=str,
                        help='Comma-separated region names')
    parser.add_argument('--tenancy-id', type=str,
                        help='Tenancy OCID (auto-detected if not provided)')
    parser.add_argument('--profile', type=str, default='DEFAULT',
                        help='OCI config profile (default: DEFAULT)')
    parser.add_argument('--output-path', type=str, default='.',
                        help='Output directory for reports (default: current)')
    parser.add_argument('--max-workers', type=int, default=20,
                        help='Maximum parallel workers (default: 20)')
    parser.add_argument('--skip-regions', type=str,
                        help='Comma-separated regions to skip (e.g., uk-london-1,eu-frankfurt-1)')
    parser.add_argument('--timeout', type=int, default=300,
                        help='API timeout in seconds (default: 300)')
    
    args = parser.parse_args()
    
    # Filter out skipped regions
    if args.skip_regions:
        skip_regions = args.skip_regions.split(',')
        regions = [r for r in regions if r not in skip_regions]
        lister.logger.info(f"⚠️ Skipping regions: {', '.join(skip_regions)}")

    # Parse lists
    compartment_ids = args.compartments.split(',') if args.compartments else None
    regions = args.regions.split(',') if args.regions else None
    
    # Create output directory
    os.makedirs(args.output_path, exist_ok=True)
    
    print("🛑 Simple OCI Stopped Instances Lister")
    print("⚡ Fast and focused - just the stopped instances")
    print(f"📅 Minimum days filter: {args.min_days}")
    print("")
    
    try:
        # Initialize lister
        lister = SimpleStoppedInstanceLister(
            config_profile=args.profile,
            tenancy_id=args.tenancy_id,
            max_workers=args.max_workers
        )
        
        # List stopped instances
        results, csv_file, html_file, summary = lister.list_stopped_instances(
            regions=regions,
            compartment_ids=compartment_ids,
            min_days=args.min_days,
            output_path=args.output_path
        )

        # Display results
        print(summary)

        if results:
            print(f"\n📄 CSV report: {csv_file}")
            print(f"🎨 HTML report: {html_file}")
            
            # Open HTML report automatically
            import webbrowser
            webbrowser.open(f"file://{os.path.abspath(html_file)}")
        
    except KeyboardInterrupt:
        print("\n⚠️ Scan interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Scan failed: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
