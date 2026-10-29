# MyKIDS Android

[English overview](../README.md) · [Описание на русском](../README.ru.md)

The Android client uses Flutter. The SDK version is pinned in `.fvmrc`, and dependencies are locked in `pubspec.lock`.

For the Android build, emulator setup, and client checks, see the [development guide](../docs/DEVELOPMENT.md). Server implementation and deployment tools are not part of this repository.

The minimum Android version is 8 (API 26). The app starts with a choice of child, parent, or relative; the authenticated account's permissions determine access after sign-in.

Firebase configuration and release signing keys are local inputs. Use your own `android/app/google-services.json` for notifications and your own `android/key.properties` for a signed release. Keep both out of Git.
