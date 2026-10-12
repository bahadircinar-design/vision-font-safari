#!/usr/bin/env python3
"""Browser test + screenshots of the extension's content script and popup, using Chrome via Playwright with
mocked Safari APIs (Tests/harness). Sample data only; this is not Safari. Run from the project root:
    python3 -m http.server 5190 &   then   python3 Tests/screenshots.py"""
import json, os, sys
from playwright.sync_api import sync_playwright

BASE = "http://localhost:5190"
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "screenshots")
INIT = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "harness", "init.js")).read()
failures = []
def check(ok, msg):
    print(("✓ " if ok else "✗ ") + msg)
    if not ok: failures.append(msg)

def page_for(ctx, role, native, url):
    pg = ctx.new_page()
    errs = []
    pg.on("pageerror", lambda e: errs.append(str(e)))
    pg.on("console", lambda m: errs.append(m.text) if m.type == "error" and "favicon" not in m.text and "404" not in m.text else None)
    pg.add_init_script(f"window.__VF_ROLE={json.dumps(role)}; window.__VF_OPTS={json.dumps({'native': native})};\n" + INIT)
    pg.goto(url)
    return pg, errs

def zoom(pg): return float(pg.evaluate("() => document.documentElement.style.zoom || '1'"))
def scale_label(pg):
    pg.evaluate("""() => { const z = document.documentElement.style.zoom || '1', f = document.documentElement.style.getPropertyValue('--vf-scale') || '1';
      document.getElementById('dbg').textContent = 'Vision Font test page · zoom ' + (+z).toFixed(2) + '× · text ' + (+f).toFixed(2) + '× · sample data'; }""")

with sync_playwright() as p:
    b = p.chromium.launch(executable_path="/usr/bin/google-chrome")
    ctx = b.new_context(viewport={"width": 1280, "height": 800}, device_scale_factor=1)
    on = {"distanceCm": 50}
    glasses = {"rx": {"od": {"sph": 0.5, "cyl": -0.5, "axis": 90, "add": 2}, "os": {"sph": 0.75, "cyl": 0, "add": 2}, "age": 60, "wearing": True, "lens": "progressive", "pdFar": 64, "pdNear": 61},
               "comfort": 1, "pxPerMm": 4.87, "pxPerMmSource": "detected", "paused": False, "updatedAt": 1}

    # --- zoom mode, progressives on ---
    pg, errs = page_for(ctx, "content", {**on, "settings": glasses}, BASE + "/Tests/harness/article.html")
    pg.wait_for_timeout(1200)
    z50 = zoom(pg); check(abs(z50 - 1.277) < 0.01, f"zoom mode, live 50 cm, progressives on: html zoom {z50:.3f} (expected 1.277)")
    scale_label(pg); pg.screenshot(path=f"{OUT}/1-zoom-mode-50cm-glasses-on.png")
    pg.evaluate("() => { __vf.native.distanceCm = 51 }"); pg.wait_for_timeout(1300)
    check(abs(zoom(pg) - z50) < 1e-6, f"51 cm (scale change < 5%) ignored by the dead-band: zoom stays {zoom(pg):.3f}")
    pg.evaluate("() => { __vf.native.distanceCm = 75 }"); pg.wait_for_timeout(1300)
    z75 = zoom(pg); check(abs(z75 - 1.916) < 0.01, f"lean back to 75 cm: zoom {z75:.3f} (expected 1.916)")
    scale_label(pg); pg.screenshot(path=f"{OUT}/2-zoom-mode-75cm-glasses-on.png")
    pg.evaluate("() => { __vf.native.faceFound = false }"); pg.wait_for_timeout(1300)
    check(abs(zoom(pg) - z75) < 1e-6, "no face → holds the last size")
    check(not errs, "no page errors (zoom) " + "; ".join(errs))
    pg.close()

    # --- text-only mode, no glasses ---
    pg, errs = page_for(ctx, "content", {**on, "settings": {**glasses, "rx": {**glasses["rx"], "wearing": False}}}, BASE + "/Tests/harness/article.html")
    pg.wait_for_timeout(300)
    pg.evaluate("() => __vf.cs.runtime.sendMessage({type:'vf:setPrefs', mode:'font', fontCap: 2.0, host: location.hostname})")
    pg.wait_for_timeout(1500)
    fs = pg.evaluate("() => [getComputedStyle(document.querySelector('main p:not(.meta)')).fontSize, getComputedStyle(document.querySelector('h1')).fontSize, document.documentElement.style.zoom || '']")
    check(fs[0] == "32px" and fs[1] == "64px" and fs[2] == "", f"text-only mode (cap 2.0×): body 16→{fs[0]}, h1 32→{fs[1]}, no page zoom")
    pg.evaluate("() => { const p = document.createElement('p'); p.id='late'; p.textContent = 'Paragraph added later by the page (sample).'; document.querySelector('main').appendChild(p); }")
    pg.wait_for_timeout(700)
    late = pg.evaluate("() => getComputedStyle(document.getElementById('late')).fontSize")
    check(late == "32px", f"content added later is scaled once (not twice): {late}")
    scale_label(pg); pg.screenshot(path=f"{OUT}/3-text-only-mode-50cm-no-glasses.png")
    pg.evaluate("() => __vf.cs.runtime.sendMessage({type:'vf:setPrefs', site: location.hostname, siteEnabled: false, host: location.hostname})")
    pg.wait_for_timeout(900)
    off = pg.evaluate("() => [getComputedStyle(document.querySelector('main p:not(.meta)')).fontSize, document.querySelectorAll('[data-vf-fs]').length]")
    check(off == ["16px", 0], f"site switched off → original sizes restored {off}")
    check(not errs, "no page errors (text-only) " + "; ".join(errs))
    pg.close()

    # --- popup ---
    pctx = b.new_context(viewport={"width": 320, "height": 560}, device_scale_factor=2)
    pg, errs = page_for(pctx, "popup", {**on, "distanceCm": 62, "settings": glasses}, BASE + "/Extension/Resources/popup.html")
    pg.wait_for_timeout(1200)
    txt = pg.evaluate("() => [...['statusPill','dist','blur','scale','siteName'].map(i => document.getElementById(i).textContent)]")
    check(txt[0] == "Live" and txt[1] == "62" and txt[4] == "example.com", f"popup live readout {txt}")
    pg.locator("body").screenshot(path=f"{OUT}/4-popup-live.png")
    pg.evaluate("() => { __vf.native.appRunning = false; __vf.native.tracking = false; }"); pg.wait_for_timeout(1200)
    warn = pg.evaluate("() => [!document.getElementById('companionWarn').hidden, document.getElementById('warnTitle').textContent, document.getElementById('statusPill').textContent]")
    check(warn[0] and warn[1] == "Companion app not running", f"popup app-not-running state {warn}")
    pg.click("details summary"); pg.wait_for_timeout(200)
    pg.locator("body").screenshot(path=f"{OUT}/5-popup-companion-not-running.png")
    check(not errs, "no page errors (popup) " + "; ".join(errs))
    b.close()

print("\nBrowser checks FAILED: %d" % len(failures) if failures else "\nAll browser checks passed.")
sys.exit(1 if failures else 0)
