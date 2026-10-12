#!/usr/bin/env python3
"""All the checks that can run without a Mac:  python3 tools/validate.py
JSON + manifest, node --check on every JS file, plist/entitlement validation (plutil-equivalent), pbxproj
structure, JS model vectors + background behaviour tests, and (if swiftc is on PATH) the Swift model check."""
import glob, json, os, plistlib, re, shutil, subprocess, sys
import xml.etree.ElementTree as ET
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "Extension", "Resources")
os.chdir(ROOT)
fails = []
def check(ok, msg):
    print(("  ✓ " if ok else "  ✗ ") + msg)
    if not ok: fails.append(msg)
def section(t): print("\n" + t)

section("JSON")
for f in [os.path.join(RES, "manifest.json"), "Tests/vectors.json"] + glob.glob("App/Assets.xcassets/**/Contents.json", recursive=True) + glob.glob("App/Assets.xcassets/Contents.json"):
    try: json.load(open(f)); check(True, f"{os.path.relpath(f, ROOT)} is valid JSON")
    except Exception as e: check(False, f"{f}: {e}")

section("manifest.json")
m = json.load(open(os.path.join(RES, "manifest.json")))
check(m.get("manifest_version") == 3, "manifest_version 3")
for k in ("name", "version", "description", "icons", "background", "content_scripts", "action", "permissions"):
    check(k in m, f"has '{k}'")
check(os.path.exists(os.path.join(RES, m["background"].get("service_worker", ""))), "background service_worker file exists")
cs = m["content_scripts"][0]
check(cs.get("matches") == ["<all_urls>"] and cs.get("all_frames") is False, "content script: all URLs, all_frames false")
check(all(os.path.exists(os.path.join(RES, j)) for j in cs["js"]), "content script files exist")
check("nativeMessaging" in m["permissions"] and "storage" in m["permissions"], "permissions include nativeMessaging + storage")
check(os.path.exists(os.path.join(RES, m["action"]["default_popup"])), "popup exists")
for group in (m["icons"], m["action"]["default_icon"]):
    for size, path in group.items():
        p = os.path.join(RES, path)
        ok = os.path.exists(p) and Image.open(p).size == (int(size), int(size))
        check(ok, f"icon {path} is {size}×{size}")
bg = open(os.path.join(RES, "background.js")).read()
for f in re.findall(r"importScripts\(([^)]*)\)", bg)[0].replace("'", "").split(","):
    check(os.path.exists(os.path.join(RES, f.strip())), f"importScripts('{f.strip()}') exists")
for f in re.findall(r'(?:src|href)="([^"]+)"', open(os.path.join(RES, "popup.html")).read()):
    check(os.path.exists(os.path.join(RES, f)), f"popup.html → {f} exists")

section("JavaScript syntax (node --check)")
for f in sorted(glob.glob(os.path.join(RES, "*.js")) + glob.glob("Tests/*.js") + glob.glob("Tests/harness/*.js")):
    r = subprocess.run(["node", "--check", f], capture_output=True, text=True)
    check(r.returncode == 0, f"{os.path.relpath(f, ROOT)}" + ("" if r.returncode == 0 else ": " + r.stderr.strip()))

section("Property lists and entitlements (plutil -lint equivalent)")
pl = {}
for f in ["App/Info.plist", "Extension/Info.plist"] + glob.glob("App/*.entitlements") + glob.glob("Extension/*.entitlements"):
    try:
        ET.parse(f)
        with open(f, "rb") as fh: pl[f] = plistlib.load(fh, fmt=plistlib.FMT_XML)
        check(True, f"{f} well-formed XML plist")
    except Exception as e: check(False, f"{f}: {e}")
a, e = pl["App/Info.plist"], pl["Extension/Info.plist"]
check(len(a.get("NSCameraUsageDescription", "")) > 40, "app: NSCameraUsageDescription present")
check(a.get("LSUIElement") is True, "app: LSUIElement (menu-bar only, no Dock icon)")
check(a.get("VFAppGroupIdentifier") == e.get("VFAppGroupIdentifier") == "$(TeamIdentifierPrefix)com.bahacinar.visionfont", "app + extension: same team-prefixed App Group id")
ext = e.get("NSExtension", {})
check(ext.get("NSExtensionPointIdentifier") == "com.apple.Safari.web-extension", "extension point com.apple.Safari.web-extension")
check(ext.get("NSExtensionPrincipalClass") == "$(PRODUCT_MODULE_NAME).SafariWebExtensionHandler", "principal class SafariWebExtensionHandler")
ae, ee = pl["App/VisionFont.entitlements"], pl["Extension/VisionFontExtension.entitlements"]
check(ae.get("com.apple.security.app-sandbox") is True and ae.get("com.apple.security.device.camera") is True, "app: sandbox + camera")
check(ee.get("com.apple.security.app-sandbox") is True and "com.apple.security.device.camera" not in ee, "extension: sandbox, no camera")
G = "com.apple.security.application-groups"; T = "com.apple.security.temporary-exception.files.home-relative-path.read-write"
check(ae.get(G) == ee.get(G) == ["$(TeamIdentifierPrefix)com.bahacinar.visionfont"], "both: same App Group")
check(ae.get(T) == ee.get(T) == ["/Library/Application Support/VisionFontShared/"], "both: same shared-folder exception (fallback channel)")
for f in ("App/VisionFont-NoAppGroup.entitlements", "Extension/VisionFontExtension-NoAppGroup.entitlements"):
    check(G not in pl[f] and pl[f].get(T) == ae.get(T), f"{f}: no App Group, keeps shared folder")
restricted = [k for d in (ae, ee) for k in d if k.startswith("com.apple.developer.")]
check(not restricted, "no entitlements that need a paid developer account")
store = open("Shared/SharedStore.swift").read()
check('"Library/Application Support/VisionFontShared"' in store and 'appGroupSuffix = "com.bahacinar.visionfont"' in store, "Swift store paths match the entitlements")

section("Asset catalog")
ic = json.load(open("App/Assets.xcassets/AppIcon.appiconset/Contents.json"))
for im in ic["images"]:
    p = "App/Assets.xcassets/AppIcon.appiconset/" + im["filename"]
    px = int(im["size"].split("x")[0]) * int(im["scale"][0])
    check(os.path.exists(p) and Image.open(p).size == (px, px), f"AppIcon {im['filename']} {px}px")

section("Xcode project structure")
r = subprocess.run([sys.executable, "tools/check_project.py"], capture_output=True, text=True)
print("    " + r.stdout.strip().replace("\n", "\n    "))
check(r.returncode == 0, "tools/check_project.py")

section("Privacy")
bad = []
for f in glob.glob("**/*", recursive=True):
    if os.path.isdir(f) or f.endswith((".png", ".pbxproj")) or "/." in f or f.startswith("screenshots"): continue
    t = open(f, errors="ignore").read()
    for pat in (r"\b(19|20)\d\d-\d\d-\d\d\b", r"(?i)\bD\.?O\.?B\b\s*[:=]", r"(?i)\b(OD|O\.D\.)\s*,?\s*(Dr\.|MD)\b"):
        if re.search(pat, t): bad.append(f"{f}: {pat}")
check(not bad, "no dates of birth / clinic details in the sources" + ("" if not bad else ": " + "; ".join(bad)))

section("Model + extension tests (node)")
for t in ("Tests/test-model.js", "Tests/test-extension.js"):
    r = subprocess.run(["node", t], capture_output=True, text=True)
    print("    " + (r.stdout + r.stderr).strip().replace("\n", "\n    "))
    check(r.returncode == 0, t)

section("Swift (Foundation-only parts)")
if shutil.which("swiftc"):
    for f in sorted(glob.glob("App/*.swift") + glob.glob("Extension/*.swift") + glob.glob("Shared/*.swift")):
        r = subprocess.run(["swiftc", "-parse", f], capture_output=True, text=True)
        check(r.returncode == 0, f"swiftc -parse {f}" + ("" if r.returncode == 0 else ": " + r.stderr.strip()[:300]))
    r = subprocess.run(["bash", "Tests/run-swift-check.sh"], capture_output=True, text=True)
    out = "\n".join(l for l in (r.stdout + r.stderr).splitlines() if "warning" not in l and not l.startswith(("  ", "   |")) and l.strip() and not re.match(r"^\d+ \|", l))
    print("    " + out.replace("\n", "\n    "))
    check(r.returncode == 0, "Tests/run-swift-check.sh (Swift model == JS vectors, store, bridge)")
else:
    print("    (swiftc not on PATH — skipped)")

print("\n" + (f"FAILED: {len(fails)} check(s)" if fails else "ALL CHECKS PASSED"))
sys.exit(1 if fails else 0)
