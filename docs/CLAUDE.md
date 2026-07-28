# HeliosConsole v0.2 (a00201 ALPHA)

## Project Overview
Native macOS MDM console for Jamf Pro environments. Provides fleet health dashboards, device inventory management, unified search, and compliance monitoring. Two targets: main app and menu bar companion.

## Build & Run
- Open `HeliosConsole.xcodeproj` in Xcode
- Two schemes: `HeliosConsole` (main app) and `HeliosMenuBar` (companion)
- Requires macOS deployment target (native Mac app, not Catalyst)
- Managed configuration needed for API connectivity — for development, `defaults write` the
  suite domains (e.g. `com.herojoneslabs.helios.console.core`, `com.herojoneslabs.helios.console.credentials`) or use mock auth

## Architecture
- **UI Framework:** SwiftUI with selective AppKit bridging (NSImage, NSApp appearance)
- **Data Flow:** Services → Caches (disk+memory) → ObservableObject → Views
- **Auth:** Master API credentials (from MDM config) create per-user Jamf API clients
- **APIs:** Jamf Pro V1 (computers), V2 (mobile devices), ABM (AppleCare via ES256 JWT)
- **State:** Singleton services + @Published properties + Combine observers

## Key Conventions
- Async/await for all networking (no completion handlers)
- Session-based cache invalidation (UUID rotates on app launch)
- Site-based compliance rules (Enterprise vs GroundControl)
- ThemeColors utility for all adaptive colors
- DeviceListItem as lightweight list representation (avoid passing full models to list views)
- PlatformType enum for all platform-specific logic (colors, icons, gradients)

## Important Gotchas
- Jamf sometimes reports iPads as iOS — detection uses model identifier fallback
- Computer model (Computer.swift) has ~30 nested types — read carefully before modifying
- Master credentials = inventory access; User credentials = search access (separate auth flows)
- MDMConfiguration is composed from 5 managed preference domains (com.herojoneslabs.helios.console.core /
  .credentials / .access / .features / .ui), each read via `UserDefaults(suiteName:)` — NEVER
  `persistentDomain(forName:)` — by ManagedDomainLoader (Managers/Configuration/). No legacy
  flat-key fallback; profile changes take effect at relaunch; missing access profile fails
  closed to role=User (see docs/ConfigProfileMigration.md)
- The dead legacy config layer (ConfigurationManager, AppConfiguration,
  AnnouncementConfiguration) was removed — MDMConfigurationManager is the only config manager
- HealthMetricsCalculator uses Combine debouncing — changes to cache structure require updating observers

## File Organization
```
Models/          — Data models (Computer, MobileDevice, User, etc.)
Services/        — API services, caches, search, health metrics
ViewModels/      — AuthViewModel (primary view model)
Managers/        — Keychain, biometric auth, MDM config
Utilities/       — Device icon provider
Views/           — All SwiftUI views organized by feature
  Authentication/  — Welcome, login, biometric flows
  Dashboard/       — Health scorecard, device counts, search
  Device/          — Device lists and detail views
  MyDevices/       — Read-only self-service view of the signed-in user's own devices
  Sidebar/         — Navigation sidebar
  Components/      — Shared UI components
  Announcement/    — Announcement feed
  Reports/         — Report builder
  Settings/        — App preferences
  Enrollments/     — DEP enrollment tracking
MenuBarApp/      — Menu bar companion target
Data/            — Mock data for previews
```
