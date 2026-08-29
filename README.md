# MPEPE Studio

MPEPE Studio is a unified creator platform designed to manage multiple YouTube channels, video/audio production workflows, and social hubs all in one app.

## Project Structure

This project follows a feature-first architecture using Riverpod for state management and GoRouter for navigation.

- `lib/auth/`: Contains authentication logic (Firebase Auth, Google Sign-In) and login UI.
- `lib/hub/`: Main dashboard for activity, team management, and AI interactions.
- `lib/youtube_manager/`: YouTube-specific features, including channel dashboard and video uploads via the YouTube Data API v3.
- `lib/video_production/`: Video production workflow management, projects, and equipment.
- `lib/audio_production/`: Audio production workflow, library, and artists.
- `lib/social_hub/`: Social interactions and cross-platform hub.
- `lib/shared/`: Shared components, themes, and navigation configurations.

## Setup Instructions

1. **Install Dependencies**:
   ```bash
   flutter pub get
   ```

2. **Configure Firebase**:
   - Ensure you have configured Firebase for your target platforms (Windows, iOS, Android, Web).
   - Place `firebase_options.dart` in the `lib/` directory if you haven't already.

3. **Google API Credentials**:
   - This project uses the YouTube Data API v3 for video uploads.
   - You need to configure OAuth 2.0 Client IDs in your Google Cloud Console for the platforms you intend to build for.

4. **Run the App**:
   ```bash
   flutter run
   ```

## Recent Updates
- Implemented **YouTube Video Upload** functionality (`YtUploadScreen` & `YouTubeUploadService`).
- Added `google_sign_in`, `googleapis`, `googleapis_auth`, `http`, and `file_picker` dependencies.
- Updated authentication logic to request YouTube Data API scopes.

## Continuing Development

To continue development on a different machine (e.g., your MacBook), clone this repository and run `flutter pub get`. The architecture is modular, so you can expand individual sections (like the AI hubs or production screens) independently.
