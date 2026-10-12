#!/usr/bin/env python3
"""Structural check of VisionFont.xcodeproj (no Xcode needed).
Parses project.pbxproj (OpenStep plist) and verifies: every reference resolves, every file on disk is in the
right build phase, the extension is embedded in PlugIns, settings point at files that exist, and the shared
scheme references real targets. Exit code 1 on any failure."""
import os, re, sys, glob
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PBX = os.path.join(ROOT, "VisionFont.xcodeproj", "project.pbxproj")

# ---------- minimal OpenStep plist parser ----------
TOK = re.compile(r'\s*(//[^\n]*\n|/\*.*?\*/|"(?:\\.|[^"\\])*"|[{}();=,]|[^\s{}();=,"]+)', re.S)
def tokens(s):
    pos = 0
    while pos < len(s):
        m = TOK.match(s, pos)
        if not m:
            if s[pos:].strip() == "": return
            raise ValueError("bad token at %d: %r" % (pos, s[pos:pos+40]))
        pos = m.end(); t = m.group(1)
        if t.startswith("//") or t.startswith("/*"): continue
        yield t
def parse(s):
    it = tokens(s); stack = []
    def val(t):
        if t == "{":
            d = {}
            while True:
                k = next(it)
                if k == "}": return d
                eq = next(it); assert eq == "=", eq
                d[unq(k)] = val(next(it))
                sc = next(it); assert sc == ";", sc
        if t == "(":
            a = []
            while True:
                x = next(it)
                if x == ")": return a
                a.append(val(x))
                sep = next(it)
                if sep == ")": return a
                assert sep == ",", sep
        return unq(t)
    return val(next(it))
def unq(t):
    if t.startswith('"'): return bytes(t[1:-1], "utf-8").decode("unicode_escape")
    return t

errors, notes = [], []
def err(m): errors.append(m)
def ok(m): notes.append(m)

text = open(PBX, encoding="utf-8").read()
if not text.startswith("// !$*UTF8*$!"): err("pbxproj missing UTF8 header")
proj = parse(text)
objs = proj["objects"]
root = objs[proj["rootObject"]]
assert root["isa"] == "PBXProject"

# every referenced id exists
ids = set(objs)
def refs(o):
    if isinstance(o, dict):
        for v in o.values(): yield from refs(v)
    elif isinstance(o, list):
        for v in o: yield from refs(v)
    elif isinstance(o, str) and re.fullmatch(r"[0-9A-F]{24}", o):
        yield o
dangling = {r for o in objs.values() for r in refs(o) if r not in ids}
if dangling: err("dangling object ids: %s" % sorted(dangling))
else: ok("all %d object ids resolve" % len(objs))

# resolve file paths through the group tree
parent = {}
for oid, o in objs.items():
    for c in o.get("children", []): parent[c] = oid
def full_path(oid):
    o = objs[oid]; tree = o.get("sourceTree"); p = o.get("path", "")
    if tree == "SOURCE_ROOT": return os.path.join(ROOT, p)
    if tree in ("BUILT_PRODUCTS_DIR", "SDKROOT"): return None
    if tree == "<group>":
        par = parent.get(oid)
        base = ROOT if par is None or par == root["mainGroup"] else full_path(par)
        return os.path.join(base, p) if base is not None else None
    return None
filerefs = {k: v for k, v in objs.items() if v["isa"] == "PBXFileReference"}
missing = [v.get("path") for k, v in filerefs.items() if full_path(k) and not os.path.exists(full_path(k))]
if missing: err("file references missing on disk: %s" % missing)
else: ok("all %d file references exist on disk" % len(filerefs))

# targets + phases
targets = {objs[t]["name"]: objs[t] for t in root["targets"]}
for name in ("Vision Font", "Vision Font Extension"):
    if name not in targets: err("missing target %r" % name)
app, ext = targets.get("Vision Font"), targets.get("Vision Font Extension")
def phases(t):
    out = {}
    for p in t["buildPhases"]:
        o = objs[p]; out.setdefault(o["isa"], []).append(o)
    return out
def phase_files(ph):
    out = set()
    for bf in ph["files"]:
        fr = objs[bf]["fileRef"]; out.add(os.path.relpath(full_path(fr), ROOT) if full_path(fr) else objs[fr]["path"])
    return out
if app["productType"] != "com.apple.product-type.application": err("app productType")
if ext["productType"] != "com.apple.product-type.app-extension": err("extension productType")
ap, ep = phases(app), phases(ext)
for nm, ph in (("app", ap), ("extension", ep)):
    for isa in ("PBXSourcesBuildPhase", "PBXResourcesBuildPhase"):
        if isa not in ph: err("%s target lacks %s" % (nm, isa))
app_src = phase_files(ap["PBXSourcesBuildPhase"][0]); ext_src = phase_files(ep["PBXSourcesBuildPhase"][0])
app_res = phase_files(ap["PBXResourcesBuildPhase"][0]); ext_res = phase_files(ep["PBXResourcesBuildPhase"][0])
for f in glob.glob(os.path.join(ROOT, "App", "*.swift")):
    r = os.path.relpath(f, ROOT)
    if r not in app_src: err("%s not compiled in app" % r)
for f in glob.glob(os.path.join(ROOT, "Shared", "*.swift")):
    r = os.path.relpath(f, ROOT)
    if r not in app_src: err("%s not compiled in app" % r)
    if r not in ext_src: err("%s not compiled in extension" % r)
if "Extension/SafariWebExtensionHandler.swift" not in ext_src: err("handler not in extension Sources")
if any(s.startswith("App/") for s in ext_src): err("app sources leaked into extension")
if "App/Assets.xcassets" not in app_res: err("Assets.xcassets not in app resources")
for f in os.listdir(os.path.join(ROOT, "Extension", "Resources")):
    r = "Extension/Resources/" + f
    if r not in ext_res: err("%s not in extension Copy Bundle Resources" % r)
imgref = [v for v in filerefs.values() if v.get("path", "").endswith("images")]
if not imgref or imgref[0].get("lastKnownFileType") != "folder": err("images must be a folder reference (keeps images/ path in the bundle)")
for bad in ("Info.plist", ".entitlements", ".xcconfig"):
    if any(x.endswith(bad) for x in app_res | ext_res): err("%s copied as a resource" % bad)
ok("sources: app %d files, extension %d files; extension resources %d entries" % (len(app_src), len(ext_src), len(ext_res)))

# embedding
copy = ap.get("PBXCopyFilesBuildPhase", [])
emb = [c for c in copy if str(c.get("dstSubfolderSpec")) == "13" and any(objs[objs[b]["fileRef"]].get("path") == "Vision Font Extension.appex" for b in c["files"])]
if not emb: err("extension .appex not embedded in the app's PlugIns (dstSubfolderSpec 13)")
else:
    attrs = [objs[b].get("settings", {}).get("ATTRIBUTES", []) for b in emb[0]["files"]]
    if not any("RemoveHeadersOnCopy" in a for a in attrs): err("embed phase missing RemoveHeadersOnCopy")
    ok("Vision Font Extension.appex embedded into Contents/PlugIns")
deps = [objs[d]["target"] for d in app.get("dependencies", [])]
if not deps or objs[deps[0]].get("name") != "Vision Font Extension": err("app does not depend on the extension target")
else: ok("app target depends on the extension target")

# build settings
xcc = {}
for line in open(os.path.join(ROOT, "Config", "Shared.xcconfig")):
    m = re.match(r"\s*([A-Z_][A-Z0-9_]*)\s*=\s*(.*?)\s*$", line)
    if m: xcc[m.group(1)] = m.group(2)
def expand(v, depth=0):
    while "$(" in v and depth < 10:
        v = re.sub(r"\$\(([A-Z0-9_]+)\)", lambda m: xcc.get(m.group(1), m.group(0)), v); depth += 1
    return v
for t, bid, plist in ((app, "com.bahacinar.VisionFont", "App/Info.plist"), (ext, "com.bahacinar.VisionFont.Extension", "Extension/Info.plist")):
    for cfg in objs[t["buildConfigurationList"]]["buildConfigurations"]:
        c = objs[cfg]; bs = c["buildSettings"]
        if bs.get("PRODUCT_BUNDLE_IDENTIFIER") != bid: err("%s %s bundle id %s" % (t["name"], c["name"], bs.get("PRODUCT_BUNDLE_IDENTIFIER")))
        if bs.get("INFOPLIST_FILE") != plist or not os.path.exists(os.path.join(ROOT, plist)): err("%s INFOPLIST_FILE" % t["name"])
        for flag in ("YES", "NO"):
            xcc_saved = xcc.get("VF_USE_APP_GROUP"); xcc["VF_USE_APP_GROUP"] = flag
            ent = expand(bs.get("CODE_SIGN_ENTITLEMENTS", ""))
            xcc["VF_USE_APP_GROUP"] = xcc_saved
            if not os.path.exists(os.path.join(ROOT, ent)): err("%s %s: entitlements %r (VF_USE_APP_GROUP=%s) missing" % (t["name"], c["name"], ent, flag))
ok("bundle ids, Info.plists and entitlements (App Group on and off) resolve for Debug and Release")
pcfgs = [objs[c] for c in objs[root["buildConfigurationList"]]["buildConfigurations"]]
if not all(c.get("baseConfigurationReference") for c in pcfgs): err("project configs not based on Config/Shared.xcconfig")
if xcc.get("MACOSX_DEPLOYMENT_TARGET") != "14.0": err("deployment target")
ok("deployment target macOS %s, Swift %s (from Config/Shared.xcconfig)" % (xcc.get("MACOSX_DEPLOYMENT_TARGET"), xcc.get("SWIFT_VERSION")))

# scheme
sch = os.path.join(ROOT, "VisionFont.xcodeproj", "xcshareddata", "xcschemes", "Vision Font.xcscheme")
if not os.path.exists(sch): err("shared scheme 'Vision Font' missing")
else:
    tree = ET.parse(sch)
    bps = {e.get("BlueprintIdentifier"): e.get("BlueprintName") for e in tree.iter("BuildableReference")}
    for bid_, name in bps.items():
        if bid_ not in objs or objs[bid_].get("name") != name: err("scheme references unknown target %s (%s)" % (name, bid_))
    if "Vision Font" not in bps.values(): err("scheme doesn't build the app")
    ok("shared scheme 'Vision Font' references %s" % sorted(set(bps.values())))
ws = os.path.join(ROOT, "VisionFont.xcodeproj", "project.xcworkspace", "contents.xcworkspacedata")
ET.parse(ws)

for n in notes: print("✓ " + n)
for e in errors: print("✗ " + e)
print(("pbxproj check FAILED (%d)" % len(errors)) if errors else "pbxproj structural check passed.")
sys.exit(1 if errors else 0)
