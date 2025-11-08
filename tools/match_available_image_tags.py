#!/usr/bin/env python3
"""
Match missing helmhubio images to available tags in the Docker Hub repo.
Instead of using missing tags, update charts to use available tags.
"""

import os
import re
import sys
import json
import subprocess
from pathlib import Path
import requests

def get_available_tags_from_dockerhub(image_name, max_tags=100):
    """Get available tags for an image from Docker Hub."""
    url = f"https://hub.docker.com/v2/repositories/helmhubio/{image_name}/tags"
    params = {"page_size": max_tags}
    
    try:
        response = requests.get(url, params=params, timeout=10)
        if response.status_code == 200:
            data = response.json()
            tags = [result["name"] for result in data.get("results", [])]
            return tags
        else:
            return []
    except Exception as e:
        print(f"   Error fetching tags for {image_name}: {e}", file=sys.stderr)
        return []

def find_best_matching_tag(missing_tag, available_tags):
    """Find the best matching tag from available tags."""
    # Extract version number from missing tag
    # Example: "12.1.1-debian-12-r1" -> "12.1.1"
    missing_version = missing_tag.split('-')[0]
    
    # Try exact match first
    if missing_tag in available_tags:
        return missing_tag
    
    # Try to find same major.minor version
    major_minor = '.'.join(missing_version.split('.')[:2])
    
    # Find tags with same major.minor
    candidates = []
    for tag in available_tags:
        if tag.startswith(major_minor):
            candidates.append(tag)
    
    if candidates:
        # Return the latest (first in list from Docker Hub)
        return candidates[0]
    
    # Try same major version
    major = missing_version.split('.')[0]
    for tag in available_tags:
        if tag.startswith(f"{major}."):
            return tag
    
    # Return latest tag if nothing matches
    if available_tags:
        return available_tags[0]
    
    return None

def update_chart_image_tag(chart_path, image_name, old_tag, new_tag):
    """Update image tag in Chart.yaml and values.yaml."""
    updated_files = []
    
    # Update Chart.yaml annotations
    chart_yaml = chart_path / "Chart.yaml"
    if chart_yaml.exists():
        with open(chart_yaml, 'r') as f:
            content = f.read()
        
        old_ref = f"docker.io/helmhubio/{image_name}:{old_tag}"
        new_ref = f"docker.io/helmhubio/{image_name}:{new_tag}"
        
        if old_ref in content:
            content = content.replace(old_ref, new_ref)
            with open(chart_yaml, 'w') as f:
                f.write(content)
            updated_files.append("Chart.yaml")
    
    # Update values.yaml
    values_yaml = chart_path / "values.yaml"
    if values_yaml.exists():
        with open(values_yaml, 'r') as f:
            lines = f.readlines()
        
        new_lines = []
        in_image_section = False
        found_repo = False
        
        for i, line in enumerate(lines):
            # Check if we're in the right image section
            if f"repository: helmhubio/{image_name}" in line:
                found_repo = True
                new_lines.append(line)
                continue
            
            # If we found the repo, look for tag within next 5 lines
            if found_repo and "tag:" in line and old_tag in line:
                # Replace the tag
                new_line = line.replace(old_tag, new_tag)
                new_lines.append(new_line)
                updated_files.append("values.yaml")
                found_repo = False
                continue
            
            # Reset if we've gone too far
            if found_repo and i > 5:
                found_repo = False
            
            new_lines.append(line)
        
        if "values.yaml" in updated_files:
            with open(values_yaml, 'w') as f:
                f.writelines(new_lines)
    
    return updated_files

def main():
    print("╔════════════════════════════════════════════════════════════════╗")
    print("║  Match Missing Images to Available Tags                       ║")
    print("╚════════════════════════════════════════════════════════════════╝")
    print()
    
    # Load missing images from previous verification
    missing_file = Path("/tmp/helmhubio_images_missing.txt")
    
    if not missing_file.exists():
        print("❌ Missing images file not found: /tmp/helmhubio_images_missing.txt")
        print("   Run the image verification script first.")
        sys.exit(1)
    
    # Parse missing images
    missing_images = {}
    with open(missing_file, 'r') as f:
        for line in f:
            if '404' in line:
                match = re.search(r'docker\.io/helmhubio/([^:]+):([^,]+)', line)
                if match:
                    image_name = match.group(1)
                    tag = match.group(2)
                    if image_name not in missing_images:
                        missing_images[image_name] = set()
                    missing_images[image_name].add(tag)
    
    print(f"Found {len(missing_images)} unique images with missing tags")
    print()
    
    # Get charts directory
    charts_dir = Path("/home/freeman/helmchart/charts/helmhubio")
    
    total_fixed = 0
    total_checked = 0
    
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("Processing Images...")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print()
    
    for image_name, missing_tags in missing_images.items():
        total_checked += 1
        print(f"[{total_checked}/{len(missing_images)}] {image_name}")
        
        # Get available tags from Docker Hub
        print(f"   Fetching available tags...", end=" ", flush=True)
        available_tags = get_available_tags_from_dockerhub(image_name)
        
        if not available_tags:
            print(f"❌ No tags found")
            continue
        
        print(f"✅ {len(available_tags)} tags found")
        
        # For each missing tag, find a replacement
        for missing_tag in missing_tags:
            best_match = find_best_matching_tag(missing_tag, available_tags)
            
            if best_match and best_match != missing_tag:
                print(f"   {missing_tag} → {best_match}")
                
                # Find charts using this image:tag
                for chart_dir in charts_dir.iterdir():
                    if not chart_dir.is_dir() or chart_dir.name == "common":
                        continue
                    
                    # Check if chart uses this image
                    values_file = chart_dir / "values.yaml"
                    if values_file.exists():
                        with open(values_file, 'r') as f:
                            content = f.read()
                        
                        if f"helmhubio/{image_name}" in content and missing_tag in content:
                            # Update the chart
                            updated = update_chart_image_tag(chart_dir, image_name, missing_tag, best_match)
                            if updated:
                                print(f"      ✅ Updated {chart_dir.name}: {', '.join(updated)}")
                                total_fixed += 1
            elif best_match:
                print(f"   {missing_tag} ✅ (exact match available)")
            else:
                print(f"   {missing_tag} ⚠️  No suitable replacement found")
        
        print()
    
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("Summary")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print()
    print(f"   Images checked: {total_checked}")
    print(f"   Charts updated: {total_fixed}")
    print()
    
    if total_fixed > 0:
        print("✅ Successfully updated charts to use available image tags")
        print()
        print("   Next steps:")
        print("   ──────────")
        print("   1. Review changes: git diff")
        print("   2. Test charts: ./tools/quick_lint_all.sh")
        print("   3. Commit: git add -A && git commit -m 'Use available image tags'")
    else:
        print("ℹ️  No charts needed tag updates")
    
    print()
    print("════════════════════════════════════════════════════════════════")

if __name__ == "__main__":
    main()
