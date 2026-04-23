# Pull-Up Tracker

A Flutter app that uses your phone's front camera and Google ML Kit pose detection to automatically count pull-ups in real time — no wearable, no manual tapping required.

---

## Problem Statement

Performing pull-ups usually requires both hands to remain engaged, which makes it difficult to interact with a phone during exercise. As a result, manual counting is inconvenient and can interrupt the flow of a workout. Dedicated gym equipment is often expensive and not portable, while wearable fitness devices may be forgotten when rushing out or preparing for training. By contrast, a phone is almost always with the user. Pull-Up Tracker is designed for this situation: it turns a smartphone into a hands-free AI workout assistant, allowing the user to mount the device, start exercising, and let computer vision automatically count each pull-up in real time.

---

## What the App Does

| Feature | Description |
|---|---|
| **Auto rep counting** | Front camera + ML Kit detects nose, wrists, and shoulders to recognize each full pull-up in real time |
| **Phase-based detection** | State machine tracks idle → hanging → ascending → atTop → descending to avoid false counts |
| **Manual adjustment** | Tap +1 / −1 to correct the count at any time |
| **Set tracking** | Record multiple sets per session; tap "Next Set" to start a new one |
| **GPS location tagging** | Reverse-geocodes your position to city/district; stored with each session |
| **Session history** | Every workout saved locally — date, duration, total reps, per-set breakdown, location |
| **Stats dashboard** | Weekly totals, average per session, cumulative reps, 7-day bar chart, 30-session trend line |
| **Pause / Resume** | Pause mid-session without losing data |

---

## Screenshots

<p float="left">
  <img src="assets/screenshots/home.png" width="200"/>
  <img src="assets/screenshots/training.png" width="200"/>
  <img src="assets/screenshots/history.png" width="200"/>
  <img src="assets/screenshots/stats.png" width="200"/>
</p>

---

## Demo

> **TODO — add a screen recording or GIF here.**
> Record a ~30-second clip showing the camera counting a set of pull-ups, then the session summary screen.

<!-- Example:
![Demo](assets/demo.gif)
-->

---

## Tech Stack

| Layer | Technology | Version | Purpose |
|---|---|---|---|
| Framework | Flutter / Dart | SDK ^3.10.7 | Cross-platform mobile UI |
| AI / Pose Detection | Google ML Kit Pose Detection | ^0.12.0 | Real-time body landmark detection (17 keypoints) |
| Camera | camera | ^0.10.5+9 | Continuous front-camera stream for ML processing |
| Local Storage | sqflite (SQLite) | ^2.3.3 | Persist sessions, sets, reps, duration, location |
| Charts | fl_chart | ^0.68.0 | Bar chart (7-day) and line chart (30-session trend) |
| State Management | provider | ^6.1.1 | App-wide state |
| GPS | geolocator | ^13.0.0 | Fetch device latitude/longitude |
| Reverse Geocoding | geocoding | ^3.0.0 | Convert GPS coordinates to city/district name |
| Haptics | Flutter HapticFeedback | built-in | Vibration feedback on each counted rep |

**Pose detection algorithm highlights:**
- Requires nose confidence > 65%, wrists > 60% to process a frame
- Uses "hang distance" (nose-to-wrist baseline) to auto-scale thresholds for different body sizes
- 800 ms anti-bounce window prevents double-counting a single rep

---

## How to Run

### Requirements

- Flutter 3.x (tested on SDK ^3.10.7)
- Android or iOS device with a front-facing camera
- Camera permission granted
- Location permission granted (optional — sessions are saved without location if denied)

### Steps

```bash
# 1. Clone the repo
git clone https://github.com/<your-username>/sylapp1.git
cd sylapp1

# 2. Install dependencies
flutter pub get

# 3. Run on a connected device or emulator
flutter run
```

> Pose detection requires a real device. The emulator camera does not supply a live body pose.

### Android notes
- Minimum SDK: 21
- Tested on Android 11+

### iOS notes
- Minimum deployment target: iOS 12
- Add camera and location usage descriptions to `Info.plist` (already included in this repo)

---

## Development Iterations

This project was built incrementally across multiple commits:

| Commit | Change |
|---|---|
| `1d5fe0a` | Initial project setup and README |
| `fe4721f` | Added camera module and UI layout |
| `bc5b04a` | Improved UI and camera integration |
| `6fe7c14` | Fixed ML Kit image input; improved pull-up detection accuracy |
| `75ef15b` | Added GPS location tagging to sessions |

---
