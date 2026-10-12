# Vision Font for Safari

Vision Font makes text on **every website** in Safari bigger or smaller based on your **eye prescription** and how **far you are from the screen right now**.

It has two parts that work together:

- **The Vision Font app.** It lives in the menu bar (it shows something like `Eye 52 cm`). It uses the Mac's camera to measure how far your eyes are from the screen, and it holds your prescription and settings.
- **The Vision Font Safari extension.** It reads that distance and resizes each page you visit.

> **Not a medical device.** Vision Font picks text sizes using rules of thumb. It doesn't diagnose anything or replace an eye exam or the right glasses.

Out of the box it uses a neutral example prescription (no correction: sphere 0, cylinder 0, ADD 0, age 45, single-vision, PD 66 / near PD 63 mm). Enter your own values on the **Prescription** tab of the app's Settings. Only lens values are stored, never personal details.

---

## Setting it up (one time, about 20 minutes)

You need a free Apple ID. You don't need a paid developer account.

### 1. Install Xcode (free)
1. Open the **App Store** on your Mac, search for **Xcode**, and click **Get** / **Install**. It's a large download (several GB).
2. Open **Xcode** once. Agree to the license and let it install its extra components. Then you can close the welcome window.

### 2. Open the project and choose your signing team
1. In Finder, open the `vision-font-safari` folder and double-click **`VisionFont.xcodeproj`**. Xcode opens.
2. Add your Apple ID if you haven't already: **Xcode ▸ Settings… ▸ Accounts**, click **+**, choose **Apple ID**, and sign in.
3. In the left sidebar, click the blue **VisionFont** icon at the very top.
4. In the middle column under **TARGETS**, click **Vision Font**.
5. Click the **Signing & Capabilities** tab.
6. Leave **Automatically manage signing** ticked. Open the **Team** menu and pick **your name (Personal Team)**.
7. Under **TARGETS**, click **Vision Font Extension** and choose the **same Personal Team** there.
8. If Xcode shows a red error that a bundle identifier "is not available", change `com.bahacinar` to something unique in **both** targets, for example `com.bahacinar2`. The extension's identifier must stay the app's identifier plus `.Extension`.

### 3. Run the app and allow the camera
1. At the top of the Xcode window, make sure the scheme reads **Vision Font** and the destination reads **My Mac**.
2. Press **⌘R** (Product ▸ Run). The first build takes a minute or two.
3. When macOS asks whether **Vision Font** may use the camera, click **Allow**.
4. Look at the right side of the **menu bar**. You'll see **`Eye 52 cm`** (your distance). The app has no Dock icon. The settings window opens the first time it runs.

> The app stops when you stop it in Xcode. To keep it, choose **Product ▸ Show Build Folder in Finder**, open `Products/Debug`, and drag **Vision Font.app** into your **Applications** folder. Open it from there from now on. You can then turn on **General ▸ Open Vision Font at login**.

### 4. Turn on the extension in Safari
Safari only loads extensions you build yourself after you allow unsigned extensions.

1. Open **Safari**, then choose **Safari ▸ Settings…** and click **Advanced**.
2. Tick **Show features for web developers**. A **Developer** tab appears in Settings.
3. Click the **Developer** tab and tick **Allow unsigned extensions**. Enter your Mac password if asked.
   **Safari turns this off every time it quits.** After each Safari restart, come back here and tick it again, or Vision Font won't run.
4. Click the **Extensions** tab and tick **Vision Font**.
5. With Vision Font selected, click **Edit Websites…** and set **When visiting other websites** to **Allow**. (Or click the Vision Font toolbar button on any web page and choose to always allow it on every website.)

The Vision Font eye button now appears in Safari's toolbar. Click it to see your distance, blur and scale.

### 5. Calibrate (2 minutes)
Open the menu-bar eye ▸ **Open Settings…** ▸ **Calibrate**.

1. **Camera distance.** Sit so your eyes are **50 cm (about 20 in)** from the screen. Measure it with a tape measure. Look at the camera and click **Measure at 50 cm**. Hold still for the 3-second countdown.
2. **Screen size.** On a MacBook this is detected automatically. To double-check, hold a bank or ID card against the screen and drag the slider until the blue card is the same width.

Then check the **Prescription** tab. Use **I'm wearing my glasses right now** to match what's on your face. The menu-bar menu has a quick toggle for this too.

---

## Everyday use

- Lean in or back and pages resize after a short moment. Small movements (changes under 5%) are ignored so pages don't jiggle.
- **Toolbar popup:**
  - shows distance, blur (D) and scale
  - **On for this site** switch
  - **Pause everywhere**
  - **Mode:** *Zoom page* (default: zooms the whole page, like ⌘+) or *Text only* (enlarges only the text, so layouts stay put)
  - **Comfort** (70–160%)
  - **Maximum scale** (default 2.5× for zoom, 3.0× for text only)
  - what to do when there's no live distance: keep the last measured distance, or use a manual distance
- **Menu-bar menu:** Tracking on/off, Wearing my glasses, Pause resizing, Calibrate, Open Settings, Quit.
- When the camera can't see you, or the app is closed, the extension keeps the last size (or uses the manual distance you set in the popup). It never jumps back to tiny text.

### How big is "right"?
The model from the Vision Font web app sizes body text so that it covers the same angle in your eye at any distance. It then adds extra size for the blur your prescription causes at that distance. Web pages are designed for about 16 px text, so the page scale is the model's suggested size ÷ 16. It's never below 1× (pages are never shrunk) and never above the maximum scale.

What that means for an example presbyope (made-up values: OD +0.50 −0.50 × 90, OS +0.75, ADD +2.00, age 60) on a MacBook screen, at Comfort 100%:

| Distance | Glasses off | Progressives on |
|---|---|---|
| 30 cm | 2.50× (cap; 3.3 D blur) | 1.24× |
| 50 cm | 2.50× (cap; 2.0 D blur) | 1.28× |
| 70 cm | 2.50× (cap; 1.5 D blur) | 1.79× |
| 100 cm | 2.50× (cap; 1.0 D blur) | 2.50× (cap) |

With glasses on, text still gets bigger as you lean back, because it keeps the same apparent size. If pages feel too big overall, set **Comfort** to about 80%.

---

## Troubleshooting

| What you see | What to do |
|---|---|
| Vision Font isn't in Safari ▸ Settings ▸ Extensions, or its button does nothing | Safari probably restarted. Tick **Developer ▸ Allow unsigned extensions** again (step 4.3). Make sure the app has run at least once. |
| Popup says **Companion app not running** | Open **Vision Font** (from Applications, or ⌘R in Xcode). Until then the extension keeps the last size or uses the manual distance. |
| Popup says **Camera tracking is off** / menu bar shows `Eye off` | Click the menu-bar eye and turn on **Tracking**. |
| Menu bar shows `Eye –` | The camera can't see your face. Check the light, face the screen, and make sure the camera isn't covered or in use by another app. |
| Camera access was denied | **System Settings ▸ Privacy & Security ▸ Camera**, turn on **Vision Font**, then turn Tracking off and on. |
| Xcode shows a signing error mentioning **App Groups** | Open `Config/Shared.xcconfig` in Xcode, change `VF_USE_APP_GROUP = YES` to `NO`, and press ⌘R again. Sharing then uses only the shared folder (see *How it works*). |
| Xcode says "No account for team" / "Signing requires a development team" | Redo step 2 for **both** targets. |
| Settings ▸ Status ▸ Data sharing shows "Couldn't write" | Tell me the message. As a quick test, switch `VF_USE_APP_GROUP` to `NO` as above. |
| Distance is clearly wrong | Redo **Measure at 50 cm**. Check that **PD, near** on the Prescription tab is right (63 mm by default). Strong head turns, glare on glasses and dim light all reduce accuracy. |
| A site's layout breaks when zoomed | Switch the popup to **Text only**, lower **Maximum scale**, or turn Vision Font off for that site. |
| I changed the extension's code | In Xcode, press ⌘B (Product ▸ Build). In Safari, untick and re-tick Vision Font in Settings ▸ Extensions, then reload the page. |

## Privacy

- The camera is on **only while Tracking is on** (the green camera light shows it). The app captures about 10 low-resolution frames a second. Each frame is analysed in memory by Apple's on-device Vision framework to find your pupils, then thrown away. **Frames are never saved, shown or sent anywhere**, and the app makes no network connections.
- What the extension gets: a distance number, a timestamp, whether a face was found, and your settings. They're stored in a small file on this Mac (see below). Nothing leaves the Mac.
- Stored values: lens values (SPH, CYL, AXIS, ADD), age, lens type, PD, comfort, calibration. Never names, dates of birth, addresses or clinic details. **Settings ▸ General ▸ Reset all settings** returns everything to the defaults.

## Limits

- Distance comes from the space between your pupils as the camera sees it, using your near PD. Uncalibrated cameras can be 10–20% off. After calibration, expect about ±5%. It measures to the camera, not to the exact line you're reading.
- The prescription model is the same rule-of-thumb model as the web app: population-average focusing ability by age, a fixed blur-to-size rule, and progressive lenses modelled as giving the full ADD up close (optimistic in the 50–70 cm intermediate zone). Bigger text helps legibility, but it can't make blurry text sharp.
- **Zoom page** can break some layouts. **Text only** leaves layouts alone but can't enlarge text drawn as images or on a canvas, or text inside embedded frames (the extension only runs in each page's main frame).
- Safari's own page zoom (⌘+) multiplies with Vision Font's.
- Locally built extensions need **Allow unsigned extensions** re-ticked after every Safari restart. That's Safari's rule for extensions that aren't distributed through the App Store or notarized with a paid developer account.

---

## How it works (for the curious)

```
 Vision Font.app (menu bar, sandboxed)                      Safari
 ┌──────────────────────────────────────┐   state.json   ┌──────────────────────────────────────────┐
 │ AVFoundation camera ~10 fps          │ ─────────────▶ │ Vision Font Extension.appex (sandboxed)  │
 │ Vision face landmarks → pupils       │  4×/s + 1 s    │  SafariWebExtensionHandler.swift          │
 │ distance = f × PD ÷ pupil px         │  heartbeat     │   answers sendNativeMessage with          │
 │ median(5) + EMA smoothing            │                │   distance + settings + app-running flag  │
 │ settings window (Rx, comfort, PPI…)  │ ◀───────────── │                ▲                          │
 └──────────────────────────────────────┘ ext-prefs.json └────────────────┼──────────────────────────┘
                                          (comfort/pause)                 │ native message ~every 500 ms
                                                          background.js (service worker): model.js + scale.js
                                                                          │ scale
                                                          content.js in each visible tab: CSS zoom or text-only
```

**How the app and the extension share data, and why it's done this way.** Safari extensions can't use the camera, so the app does the measuring. The app and the extension's native part are both sandboxed, so neither can see the other's private storage. The app writes a small JSON file (`state.json`: distance, timestamp, face found, a heartbeat, and settings) to **two places**, and the extension reads whichever copy is newer:

1. **App Group container**: `~/Library/Group Containers/<TeamID>.com.bahacinar.visionfont/`. This is Apple's standard way for an app and its extension to share data. The group name starts with your Team ID (`$(TeamIdentifierPrefix)`), the macOS-style form. macOS checks that prefix against the app's signature, so it needs no provisioning profile or paid account and works with a free Personal Team. It also avoids the "would like to access data from other apps" prompt on macOS 15 and later.
2. **Shared folder**: `~/Library/Application Support/VisionFontShared/`. Both sides can reach it through a sandbox "temporary exception" file entitlement. This copy works even if App Groups ever cause signing trouble, so switching `VF_USE_APP_GROUP` to `NO` drops channel 1 and everything keeps working. (Mac App Store review would reject this exception, but that doesn't matter for an app you build for yourself.)

Each file has exactly one writer. The app writes `state.json`. The extension writes `ext-prefs.json`, which holds Comfort and Pause changed from the Safari popup; the app picks those up if they're newer. Writes go to a temporary file that is then renamed, so a reader never sees half-written data. If the heartbeat is older than 3 s, the extension treats the app as not running. If the distance is older than 3 s, it treats the data as stale and holds the last size.

**Why the native message isn't sent to the app directly.** Safari's native messaging goes to the extension's own handler process, not to the running app. That handler also starts when the app is closed, so it reads the shared file instead. It can always answer, even if it's only to say the app isn't running.

**The model.** `Extension/Resources/model.js` is a byte-for-byte copy of the web app's `model.js`. `scale.js` adds the page-scale step (model px ÷ 16, clamped from 1× to the cap). `Shared/VisionModel.swift` ports both to Swift for the menu-bar readout and settings preview. `Tests/vectors.json` holds 96 shared test cases (8 profiles × 3 screen/comfort settings × 30/50/70/100 cm), including your prescription with and without glasses. Both languages must match them to within 1e-9.

## Files

```
VisionFont.xcodeproj      Xcode project: targets "Vision Font" (app) + "Vision Font Extension" (embedded)
project.yml               XcodeGen spec the project is generated from; ./generate-xcodeproj.sh regenerates it
Config/Shared.xcconfig    shared settings (deployment target, VF_USE_APP_GROUP switch)
App/                      SwiftUI menu-bar app: VisionFontApp, AppModel, DistanceTracker (AVFoundation + Vision),
                          ScreenInfo, LoginItem, SettingsView, Info.plist, entitlements, Assets.xcassets
Extension/                SafariWebExtensionHandler.swift, Info.plist, entitlements
Extension/Resources/      manifest.json (MV3), background.js, content.js, popup.html/js/css, model.js, scale.js, images/
Shared/                   VisionModel.swift (model port), DistanceEstimator.swift, SharedStore.swift (used by both targets)
Tests/                    vectors.json, test-model.js, test-extension.js, ModelCheck/ (Swift), harness/ + screenshots.py
tools/                    validate.py (all non-Mac checks), check_project.py, make_icons.py
BUILD_ON_MAC.sh           command-line build once Xcode is installed
```

### Developer checks
- `python3 tools/validate.py` checks JSON, the manifest and icons, runs `node --check` on all JS, validates the plists and entitlements, checks the pbxproj structure, and runs the JS vector and background tests, plus the Swift model check when `swiftc` is available.
- `bash Tests/run-swift-check.sh` compiles `Shared/*.swift` and checks them against the vectors. It works on a Mac with only the Command Line Tools installed.
- `./BUILD_ON_MAC.sh` (needs Xcode) builds the Debug app and prints where `Vision Font.app` is. You can pass `TEAM_ID=XXXXXXXXXX` to set the team.
