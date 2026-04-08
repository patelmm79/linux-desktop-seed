#!/usr/bin/env python3
"""
OpenCLAW CVE Checker
Fetches CVE data from OpenClawCVEs feed and checks for new vulnerabilities.
Can be run standalone or as part of CVE monitoring.
"""

import json
import os
import sys
from datetime import datetime
from pathlib import Path
from urllib.request import urlopen, Request
from urllib.error import URLError

# Configuration
CVE_FEEDS = [
    ("cves.json", "https://raw.githubusercontent.com/jgamblin/OpenClawCVEs/main/cves.json"),
    ("ghsa.json", "https://raw.githubusercontent.com/jgamblin/OpenClawCVEs/main/ghsa-advisories.json"),
]

CACHE_FILE = Path.home() / ".openclaw" / "seen-cves.txt"
DISCORD_WEBHOOK_URL = os.getenv("DISCORD_CVE_WEBHOOK_URL")

def load_cache():
    """Load previously seen CVEs from cache file."""
    if not CACHE_FILE.exists():
        return set()

    with open(CACHE_FILE, "r") as f:
        return set(line.strip() for line in f if line.strip())

def save_cache(seen_cves):
    """Save seen CVEs to cache file."""
    CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(CACHE_FILE, "w") as f:
        for cve in sorted(seen_cves):
            f.write(f"{cve}\n")

def fetch_cve_feed(url):
    """Fetch CVE data from a GitHub raw URL."""
    try:
        req = Request(url, headers={"User-Agent": "OpenCLAW-CVE-Checker/1.0"})
        with urlopen(req, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except (URLError, json.JSONDecodeError) as e:
        print(f"Warning: Failed to fetch {url}: {e}")
        return []

def extract_cve_ids(feed_data, id_field="id", fallback_field="cve_id"):
    """Extract CVE IDs from feed data."""
    cve_ids = []
    for entry in feed_data:
        cve_id = entry.get(id_field) or entry.get(fallback_field)
        if cve_id and cve_id.startswith("CVE-"):
            cve_ids.append(cve_id)
    return cve_ids

def get_cve_details(cve_id, feed_data):
    """Get details for a specific CVE from feed data."""
    for entry in feed_data:
        if entry.get("id") == cve_id or entry.get("cve_id") == cve_id:
            return {
                "cvss": entry.get("cvss") or entry.get("score", "N/A"),
                "description": entry.get("description") or entry.get("title", "No description")[:500],
                "reference": (entry.get("references") or [None])[0] if entry.get("references") else f"https://nvd.nist.gov/vuln/detail/{cve_id}"
            }
    return {"cvss": "N/A", "description": "No description available", "reference": f"https://nvd.nist.gov/vuln/detail/{cve_id}"}

def determine_severity_color(cvss):
    """Determine Discord embed color based on CVSS score."""
    try:
        cvss_float = float(cvss)
        if cvss_float >= 9.0:
            return 16711680  # Red
        elif cvss_float >= 7.0:
            return 16744448  # Orange
        elif cvss_float >= 4.0:
            return 16776960  # Yellow
        else:
            return 65280  # Green
    except (ValueError, TypeError):
        return 16777215  # White

def post_to_discord(cve_id, cvss, description, reference):
    """Post CVE alert to Discord webhook."""
    if not DISCORD_WEBHOOK_URL:
        print("ERROR: DISCORD_CVE_WEBHOOK_URL not set")
        return False

    import urllib.request
    import urllib.parse

    color = determine_severity_color(cvss)
    payload = {
        "embeds": [{
            "title": "🚨 New OpenCLAW CVE Detected",
            "color": color,
            "fields": [
                {"name": "CVE ID", "value": cve_id, "inline": True},
                {"name": "CVSS Score", "value": str(cvss), "inline": True},
                {"name": "Description", "value": description[:500]},
                {"name": "Reference", "value": reference}
            ],
            "footer": {"text": "OpenCLAW CVE Monitor"},
            "timestamp": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
        }]
    }

    try:
        req = Request(
            DISCORD_WEBHOOK_URL,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST"
        )
        with urlopen(req, timeout=10) as response:
            return response.status == 204
    except URLError as e:
        print(f"ERROR: Failed to post to Discord: {e}")
        return False

def check_for_new_cves():
    """Main function to check for new CVEs."""
    print(f"[{datetime.now().isoformat()}] Checking for new OpenCLAW CVEs...")

    seen_cves = load_cache()
    all_new_cves = []

    # Fetch all feeds
    for filename, url in CVE_FEEDS:
        print(f"  Fetching {filename}...")
        feed_data = fetch_cve_feed(url)
        if feed_data:
            cve_ids = extract_cve_ids(feed_data)
            for cve_id in cve_ids:
                if cve_id not in seen_cves:
                    all_new_cves.append((cve_id, feed_data))

    if not all_new_cves:
        print("  No new CVEs found.")
        return 0

    print(f"  Found {len(all_new_cves)} new CVE(s)!")

    # Process each new CVE
    for cve_id, feed_data in all_new_cves:
        details = get_cve_details(cve_id, feed_data)

        print(f"  Processing {cve_id} (CVSS: {details['cvss']})")

        # Post to Discord
        if DISCORD_WEBHOOK_URL:
            post_to_discord(cve_id, details['cvss'], details['description'], details['reference'])

        # Add to cache
        seen_cves.add(cve_id)

    # Save updated cache
    save_cache(seen_cves)
    print(f"  Updated cache with {len(all_new_cves)} new CVE(s)")

    return len(all_new_cves)

if __name__ == "__main__":
    # Can be run standalone or imported as module
    if len(sys.argv) > 1 and sys.argv[1] == "--check":
        count = check_for_new_cves()
        sys.exit(0 if count == 0 else 1)
    else:
        # Default: just check and exit with appropriate code
        count = check_for_new_cves()
        sys.exit(0)