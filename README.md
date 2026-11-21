# Snap It!

A pose game for iPhone. Snap It! shows a pose, you strike it in front of the camera, and it scores in real time how well you copied it: arms, torso, head, facial expression and finger positions. It has two modes:

- **Picture mode:** you pick a category (Party, Couple, Family, Casual) and get a random pose with a 10 s countdown. The app saves a photo of your best moment, stamped with your accuracy %.
- **Play mode:** you copy famous memes against a shrinking timer while the minimum score keeps rising. 1–6 players play head-to-head, the app announces the winner, and you can share a "Beat me if you can!" photo.

Other features: hands-free navigation with a head-controlled cursor, portrait and landscape support, and stand-up reminder notifications.

## How to run

**Requirements**
- macOS with **Xcode 26+** (Liquid Glass needs the iOS 26 SDK)
- **Flutter 3.44+** (Dart 3.12+)
- **CocoaPods**
- A **physical iPhone** running iOS 15.5 or later. The camera and Vision do not work in the simulator. Liquid Glass styling appears on iOS 26+.

**Steps**
```bash
flutter pub get
cd ios && pod install && cd ..
flutter run --release        # with the iPhone connected and selected
```
On first launch, allow access to the **camera**, **notifications** and, when you save a photo, **Photos**.

**Tests**
```bash
flutter test
```

**Pitch deck** (regenerates `pitch/SnapIt_pitch.pdf`)
```bash
swift pitch/make_deck.swift
```

## Tools and APIs

| Area | What we used |
|---|---|
| App | **Flutter** (Dart) for the UI and game logic, **Swift** for the native iOS parts (`ios/Runner/AppDelegate.swift`) |
| Pose detection | **Apple Vision**: `VNDetectHumanBodyPoseRequest` (multi-person body pose), `VNDetectFaceLandmarksRequest` (facial expression and head direction), `VNDetectHumanHandPoseRequest` (21 hand points per hand) |
| Signal processing | Our own One-Euro filter smoothing, per-player tracking, and optimistic inference of limbs outside the frame |
| Camera | `camera` Flutter plugin (AVFoundation) |
| UI | Apple **Liquid Glass** (`UIButton.Configuration.glass` / `.prominentGlass`, SwiftUI `glassEffect` for the glass lettering), `cupertino_native` (native segmented controls) |
| System | **Photos** (`PHPhotoLibrary`) for saving photos, `UIActivityViewController` for sharing, **UserNotifications** for stand-up reminders |
| Pitch deck | Swift + CoreGraphics/AppKit (PDF) |

## AI assistants

- **Claude Code** (Anthropic, Claude models): pair-programming assistant for the code, native iOS integration, tests and the pitch deck.
- **Generative image AI:** the reference photos for Picture mode (`media/ai_kepek`) were generated from prompts we wrote.

The meme templates in Play mode (`media/play_memes`) are well-known internet memes.

## Project structure

```
lib/
  main.dart, home_page.dart     app shell, home screen (intro animation)
  pose/                         camera, Vision bridge, smoothing, multi-person tracking
  game/                         poses, memes, scoring (pose, expression, hands), modes
  gaze/                         head-controlled cursor
  ui/                           Liquid Glass widgets, theme
ios/Runner/AppDelegate.swift    Vision, Liquid Glass, photos, share sheet, notifications
assets/                         pose photos and memes (downscaled)
pitch/                          pitch deck generator and PDF
```
