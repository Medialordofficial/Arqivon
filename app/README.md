# Arqivon — Flutter Client

The Flutter mobile client for **Arqivon — The Living Lens**.

See the [root README](../README.md) for full project documentation, architecture, and setup instructions.

## Quick Start

```bash
cd app
flutter pub get
flutter run
```

## Structure

| Directory | Purpose |
|-----------|---------|
| `lib/screens/` | 9 app screens (Home, Live, Archive, Notes, Memories, Settings, Login, Onboarding, Session Detail) |
| `lib/providers/` | Riverpod state management (live session, auth, settings) |
| `lib/services/` | Audio, notifications, PDF export, FCM, action handlers |
| `lib/models/` | Data models (sessions, messages, notes, reminders) |
| `lib/widgets/` | Reusable UI components (glassmorphic cards, smart action cards, live wave, offline banner) |
| `lib/config/` | Theme, routes, logging configuration |
| `test/` | 7 test files (99 unit tests) |

## Requirements

- Flutter SDK ≥ 3.2.0
- Android 6.0+ (API 23+) or iOS 14+
- Camera and microphone permissions
