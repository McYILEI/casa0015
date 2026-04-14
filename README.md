# Pull-Up Tracker

A Flutter app that uses your phone's front camera and Google ML Kit pose detection to automatically count pull-ups in real time.

## Features

- **Auto counting** — The camera detects your body position (nose, wrists, shoulders) to recognize each full pull-up rep without you touching the phone
- **Manual adjustment** — Tap +1 / −1 buttons to correct the count if needed
- **Set tracking** — Record multiple sets per session with a "Next Set" button
- **Session history** — Every workout is saved locally with date, duration, total reps, and per-set breakdown
- **Stats dashboard** — View weekly totals, average per session, cumulative reps, a 7-day bar chart, and a 30-session trend line
- **Pause / Resume** — Pause mid-session without losing data

## Tech Stack

- Flutter / Dart
- Google ML Kit Pose Detection
- SQLite (local storage)
- fl_chart

## Getting Started

### Requirements

- Flutter 3.x
- Android device with camera
- Camera permission enabled

### Run

```bash
flutter pub get
flutter run
```
