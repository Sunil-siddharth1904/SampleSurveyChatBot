# voicebased_chatbot

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Notes — Windows plugin fix

- The Windows speech plugin (`speech_to_text_windows`) was updated locally to send structured
	data to Flutter (an `EncodableMap`) instead of a JSON string. This avoids a Dart-side
	type-cast error when handling recognition results.
- The change lives in the ephemeral plugin symlink used for Windows builds:
	`windows/flutter/ephemeral/.plugin_symlinks/speech_to_text_windows/windows/speech_to_text_windows_plugin.cpp`
- The app now checks speech availability at startup and disables the mic button when
	speech is unavailable to avoid runtime failures: see `lib/main.dart`.

If you want this fix upstreamed, consider creating a PR against the `speech_to_text_windows`
plugin repository with the change shown here.
