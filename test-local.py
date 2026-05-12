#!/usr/bin/env python3
"""
Local test script for the publish-marketplace action.
Usage:
  python test-local.py <path-to.vsix> <vs-publish.json> <PAT>

Example:
  python test-local.py bin\Release\MyExt.vsix vs-publish.json YOUR_PAT_HERE
"""

import os, sys, json, zipfile, base64, xml.etree.ElementTree as ET
import urllib.request, urllib.error, urllib.parse

if len(sys.argv) != 4:
	print(f"Usage: {sys.argv[0]} <path-to.vsix> <vs-publish.json> <PAT>")
	sys.exit(1)

vsix_file    = sys.argv[1]
manifest_file = sys.argv[2]
token        = sys.argv[3]

if not os.path.isfile(vsix_file):
	print(f"Error: VSIX file not found: {vsix_file}")
	sys.exit(1)

if not os.path.isfile(manifest_file):
	print(f"Error: Manifest file not found: {manifest_file}")
	sys.exit(1)

with open(manifest_file) as f:
	manifest = json.load(f)
publisher    = manifest["publisher"]
extension_id = manifest["identity"]["internalName"]

with zipfile.ZipFile(vsix_file) as z:
	vsix_manifests = [n for n in z.namelist() if n.endswith(".vsixmanifest")]
	if not vsix_manifests:
		print("Error: No .vsixmanifest found in VSIX")
		sys.exit(1)
	with z.open(vsix_manifests[0]) as f:
		root = ET.parse(f).getroot()

ns = {"vs": "http://schemas.microsoft.com/developer/vsx-schema/2011"}
version = root.find("vs:Metadata/vs:Identity", ns).get("Version")

print(f"Publishing {publisher}.{extension_id} v{version}...")

with open(vsix_file, "rb") as f:
	data = f.read()

pub_enc = urllib.parse.quote(publisher, safe="")
ext_enc = urllib.parse.quote(extension_id, safe="")
url = (
	f"https://marketplace.visualstudio.com/_apis/gallery/publishers/{pub_enc}"
	f"/extensions/{ext_enc}?api-version=7.2-preview.2"
)

pat = base64.b64encode(f"OAuth:{token}".encode()).decode()

req = urllib.request.Request(url, data=data, method="PUT")
req.add_header("Authorization", f"Basic {pat}")
req.add_header("Content-Type", "application/octet-stream")
req.add_header("Content-Length", str(len(data)))

print(f"PUT {url}")

try:
	with urllib.request.urlopen(req) as resp:
		print(f"Success ({resp.status}): Published {publisher}.{extension_id} v{version}")
except urllib.error.HTTPError as e:
	body = e.read().decode("utf-8", errors="replace")
	print(f"Error ({e.code} {e.reason}):\n{body}")
	sys.exit(1)
