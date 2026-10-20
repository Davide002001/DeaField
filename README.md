# 🦻 DeaField

**Sound awareness for deaf and hard-of-hearing people.**

DeaField is an iOS app that continuously listens to the surrounding environment, recognises meaningful sounds (alarms, doorbells, voices, a baby crying…) and notifies the user through **haptic feedback** and on-screen alerts — so important sounds are never missed.

## ✨ Features

- **On-device sound recognition** using Apple's built-in classifier (`SNClassifySoundRequest`, SoundAnalysis) — no audio leaves the phone.
- **Choose what to detect** — the user selects which sound categories to monitor.
- **Haptic alerts** with Core Haptics when a monitored sound is detected.
- **Recording & frequency analysis** — records audio and estimates dominant frequencies with Accelerate (FFT).
- Live detection screen with confidence levels and pause/resume.

## 🛠️ Tech stack

| | |
|---|---|
| Language | Swift |
| UI | SwiftUI, Combine |
| Frameworks | SoundAnalysis, AVFoundation, Accelerate, Core Haptics |
| Testing | XCTest (unit & UI tests) |
| Platform | iOS |

## 🚀 Getting started

1. Clone the repo and open `Deafield/Deafield.xcodeproj` in Xcode 15+.
2. Run on a **physical iPhone** (microphone and haptics are not available in the simulator).
3. Allow microphone access when prompted.
