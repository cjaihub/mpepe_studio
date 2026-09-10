# Getting Started

Welcome to MPEPE STUDIO! Follow these steps to set up your local development environment.

## Prerequisites
- Flutter SDK (stable channel)
- Dart SDK
- Firebase CLI (`firebase-tools`)

## Installation
1. Clone the repository and navigate to the root directory.
2. Run `flutter pub get` to install dependencies.
3. Configure your Firebase project using the `flutterfire configure` command.
4. (Optional) Run `dart fix --apply` and `flutter analyze` to ensure the codebase is clean before making commits.

## Running the App
Start the application on your preferred platform:
```bash
flutter run
```
On Desktop (Windows/macOS/Linux), a developer login bypass is available in debug mode to speed up UI testing.

## Documentation
For architecture details, refer to `docs/architecture.md`. For security requirements, see `docs/security.md`.
