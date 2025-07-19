# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

This is an iOS/macOS project using Xcode. Common development commands:

- Build: Open `.xcodeproj` files in Xcode and use Cmd+B to build
- Run: Use Cmd+R in Xcode to run the app
- Test: Use Cmd+U in Xcode to run tests
- Clean: Use Cmd+Shift+K in Xcode to clean build folder

## Project Structure

This repository contains two main iOS/macOS applications:

### CratebitsDemo
- **Main App**: `CratebitsDemo/CratebitsDemoApp.swift` - Standard SwiftUI app entry point
- **Content**: `CratebitsDemo/ContentView.swift` - Simple "Hello, world!" view
- **Tests**: `CratebitsDemoTests/` and `CratebitsDemoUITests/` directories
- **Project**: `CratebitsDemo.xcodeproj`

### UsingMusicKitToIntegrateWithAppleMusic
- **Purpose**: Apple Music integration demo using MusicKit (WWDC21 sample)
- **Main App**: `UsingMusicKitToIntegrateWithAppleMusic/App/MusicAlbumsApp.swift`
- **Architecture**: 
  - `Screens/` - SwiftUI views (ContentView, AlbumDetailView, WelcomeView, etc.)
  - `Cells/` - Reusable UI components (AlbumCell, TrackCell, MusicItemCell)
  - `Components/` - UI styling (ProminentButtonStyle)
  - `Storage/` - Data persistence (RecentAlbumsStorage)
  - `BarcodeScanning/` - Barcode scanning functionality
- **Project**: `UsingMusicKitToIntegrateWithAppleMusic/MusicAlbums.xcodeproj`

## Key Technical Details

- **Platform**: iOS/macOS SwiftUI applications
- **Framework**: Uses MusicKit for Apple Music integration in the sample app
- **Device Requirements**: MusicKit sample must run on physical device, not simulator
- **Configuration**: Requires developer team setup and App ID with MusicKit service enabled
- **UI Framework**: SwiftUI with custom styling and appearance adjustments

## Development Notes

- The MusicKit sample requires proper Apple Developer account setup with MusicKit App Service enabled
- Both projects follow standard iOS app architecture patterns
- Test files are included for both unit tests and UI tests