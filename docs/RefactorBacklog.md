# Refactor Backlog (post-publish)

Findings from the pre-publish engineering review (2026-09-27). Not blockers for
going public — tracked here to work through after the initial GitHub release.

## Priority order

1. `DeviceView` decomposition
2. Shared component/state extraction (pagination/filter/search)
3. Efficiency fixes (N+1 search, redundant health-metric passes)
4. `AbmAPIService` auth/business-logic split
5. Concurrency modernization sweep

## 1. Modularity

- ~~**`Views/Device/DeviceView.swift` (5,297 lines)**~~ — **Done**
  (`refactor/device-view-decomposition`). Now a ~490-line shell over
  `DeviceCommandExecutor`, `DeviceActionFlow`/`DeviceActionsMenu`,
  `DeviceActionOverlays`, `DeviceOverviewView`, `DeviceDetailSectionsView`,
  `DeviceInventoryTabsView` (+ `DeviceInventoryState` on
  `PaginatedListState<Row>`), and `DeviceLogsSectionView`.
- **`Views/Reports/ReportsView.swift` (2,291 lines)** — same class of problem
  at smaller scale; extract per-report-type view models + a shared
  `ReportExportService`.
- **`Services/AbmAPIService.swift` (1,608 lines)** — mixes JWT/ES256 signing +
  OAuth token caching (security-sensitive) with generic paged-HTTP plumbing
  and ~15 model structs. Split into `AppleBusinessManagerAuthClient`,
  `ABMHTTPClient`, and dedicated model files; leave `ABMAPIService` as a thin
  façade.
- ~~**Duplicated UI components**~~ — **Done.** `SectionHeader`,
  `DetailCard`, `DetailRow`, `SearchBar`, `FilterToggle`,
  `PaginationControls`, `EmptyStateView`, `StatusBadge` live in
  `Views/Shared/` (DeviceView's styling), adopted by `DeviceView`,
  `MobileDeviceView`, and `ABMLookupView`. The private `statusBadge` copies in
  `ComputerResultCard` and `DeviceListRow` now use `StatusBadge(size: .compact)`
  (same 9pt list-row look).
  - `ReportsView` deliberately NOT migrated: its `sectionHeader(_:icon:color:)`
    is a light/dark-aware 16pt card subheading and `statusBadge(Bool)` is a
    Yes/No pill — different components, not drifted copies. Swapping in the
    shared white 24pt header would break Reports in light mode.
- ~~**Duplicated pagination/filter state**~~ — **Done.**
  `PaginatedListState<Row>` + `PaginatedRows` (`Views/Shared/`) back
  DeviceView's 7 inventory tabs (`DeviceInventoryState`) and MobileDeviceView's
  5 searchable sections (`MobileDeviceInventoryState`).
- **`Managers/Configuration/FeaturesConfiguration.swift` (941 lines)** —
  secondary candidate; worth a follow-up look for business logic that crept
  into what should be a settings/data layer.

## 2. Efficiency (fleet scale)

- **N+1 API calls** — `Services/UnifiedSearchService.swift:304-310,369-375`:
  `searchMobileDevices` hydrates each search match with a sequential awaited
  per-device API call instead of batching. 500 matches in a 20k-device fleet
  ≈ 75–150s for one search.
- **5x redundant health-metric evaluation** —
  `Services/HealthMetricsCalculator.swift:228-238,391-416`: `recalculateMetrics()`
  runs 5 independent full-fleet passes (one per metric), computing
  `scopeFacts` twice per device each time. On a 25k-device fleet that's
  250k+ redundant evaluations, synchronous on the calling thread.
- **Uncached filter/sort** — `Views/Device/DeviceListView.swift:106-126`:
  `filteredDevices` re-runs a full filter+sort over the entire array on every
  access (referenced 8x in `body`), with no search debounce.
- **Redundant heavy decode** — `Services/ComputerSearchService.swift:272-337`
  (`fetchComputerById`): fetches/decodes all 23 inventory sections just to
  return one record by ID; duplicates `performSearch`'s decode path.

## 3. Concurrency / syntax modernization

(Deployment target confirmed: macOS 14.0 / Swift 5 language mode — `@Observable`,
async `LAContext`, and structured concurrency are all available.)

- **Duplicate biometric-auth implementations** —
  `Managers/BiometricAuthManager.swift:72-89` and
  `Models/AppSettings.swift:272-284` both independently wrap `LAContext`'s
  completion-handler API with a manual `DispatchQueue.main.async` hop, despite
  a native `async throws evaluatePolicy` being available since macOS 12.
  Consolidate into one implementation using the async API.
- **`ViewModels/AuthViewModel.swift:190-249`** — `authenticateWithBiometrics`
  is the only sign-in path still using completion-handler style while
  `loginWithEmail`/`loginWithEntra` already use `async`/`await`. Convert to
  `func authenticateWithBiometrics() async -> Bool`.
- **`Views/Components/InventoryLoadingView.swift:262,275,280`** — nested
  `DispatchQueue.main.asyncAfter` timers for progress animation aren't
  cancellable; a dismissed view still gets mutated later. Replace with a
  `.task { }`-scoped `Task.sleep(for:)` loop.
- **`Services/ComputerInventoryCache.swift:68-151`** — synchronous disk read +
  JSON decode of the full inventory cache runs on the main actor during
  `init()`, while the save path already correctly runs off-main via
  `Task.detached`. Likely launch-time stutter that scales with fleet size.
- **`ObservableObject`/`@Published` → `@Observable`** — ~20+ files
  (including app-wide `AuthViewModel`) could move to `@Observable` now that
  macOS 14 is the deployment target, avoiding unrelated-property re-renders
  on widely-injected objects.

## Confirmed clean (no action needed)

- Org-portability: Cleanup, My Devices, Device History, Site Move, and Health
  Scorecard modules were audited specifically for hardcoded org assumptions
  and came back clean — role/site checks are profile-driven, no hardcoded
  naming conventions.
