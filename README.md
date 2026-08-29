<div align="center">

# 🎬 MPEPE Studio

**A unified creator platform designed to manage multiple YouTube channels, video/audio production workflows, and social hubs all in one app.**

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter Badge" />
  <img src="https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart Badge" />
  <img src="https://img.shields.io/badge/Firebase-FFCA28?style=for-the-badge&logo=firebase&logoColor=black" alt="Firebase Badge" />
  <img src="https://img.shields.io/badge/YouTube_API-FF0000?style=for-the-badge&logo=youtube&logoColor=white" alt="YouTube API Badge" />
</p>

</div>

---

## 🌟 Overview

MPEPE Studio is a next-generation platform for content creators. Whether you are managing your personal vlog or a network of ten different channels, MPEPE Studio centralizes your workflow.

With built-in tools for **Video Production**, **Audio Production**, and direct **YouTube Integrations**, this app streamlines everything from shooting, editing, uploading, and analyzing content, straight from your device.

---

## 🛠️ Project Structure

This project follows a feature-first architecture using **Riverpod** for robust state management and **GoRouter** for seamless navigation.

<details>
<summary><b>📂 View Folder Architecture</b></summary>
<br>

| Directory | Description |
|-----------|-------------|
| 🔒 `lib/auth/` | Authentication logic (Firebase Auth, Google Sign-In) and beautiful login UI. |
| 🎛️ `lib/hub/` | Main dashboard for activity, team management, and AI interactions. |
| 📺 `lib/youtube_manager/`| YouTube-specific features, including channel dashboards and direct video uploads via the YouTube Data API v3. |
| 🎬 `lib/video_production/`| Video production workflow management, tracking projects, crew, and equipment. |
| 🎵 `lib/audio_production/`| Audio production workflow, music library, and artist management. |
| 💬 `lib/social_hub/` | Social interactions and cross-platform communication hub. |
| 🧩 `lib/shared/` | Shared components, cohesive themes, and navigation configurations. |

</details>

---

## 🚀 Recent Updates

✨ **YouTube Video Upload Integrated**
- Added robust video upload functionality (`YtUploadScreen` & `YouTubeUploadService`).
- Implemented file picking with `file_picker` for seamless device access.
- Integrated Google Auth flows to request specific `youtube.upload` scopes for secure API access.

---

## ⚙️ Setup Instructions

### 1. Install Dependencies
Get all the required Flutter packages:
```bash
flutter pub get
```

### 2. Configure Firebase
- Ensure you have configured Firebase for your target platforms (Windows, iOS, Android, macOS).
- Place `firebase_options.dart` in the `lib/` directory if you haven't already.

### 3. Google API Credentials
This project uses the **YouTube Data API v3** for video uploads.
- Navigate to your [Google Cloud Console](https://console.cloud.google.com/).
- Enable the **YouTube Data API v3**.
- Configure OAuth 2.0 Client IDs for your application platforms.

### 4. Run the App
Launch the studio on your preferred device:
```bash
flutter run
```

---

## 💻 Continuing Development

To continue development on a different machine (e.g., your MacBook), clone this repository, run `flutter pub get`, and pick up where you left off. The architecture is highly modular, so you can expand individual sections—like the AI hubs or production screens—independently.

<br>

<div align="center">
  <i>Built with passion to empower creators.</i>
</div>
