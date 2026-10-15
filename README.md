# AppReaper

A native macOS app that finds and removes everything an app leaves behind —
not just the `.app` bundle, but its caches, preferences, containers, logs,
and launch agents too. Think AppCleaner / PearCleaner, built from scratch
in SwiftUI.

## Why it's unsandboxed

AppReaper needs to read and delete files across `~/Library` and
`/Applications` that belong to *other* apps. The App Sandbox exists to
prevent exactly that kind of cross-app file access, so this app ships
without it — and without an entitlements file at all, since even an
entitlement explicitly set to "off" is a stray setting that could silently
re-enable a restriction later.

## How it works

1. **`AppDiscoveryService`** scans `/Applications` and `~/Applications`
   (plus one level into subfolders) for `.app` bundles, reads their
   `Info.plist` metadata and code-signing team ID, and flags Apple/
   SIP-protected apps as non-removable. It also cross-references Homebrew's
   `Caskroom` to tag apps installed via `brew install --cask`.
2. **`LeftoverFinder`** conservatively matches related files across
   `Application Support`, `Caches`, `Preferences`, `Containers`,
   `Group Containers`, `Logs`, `LaunchAgents`, `Saved Application State`,
   `HTTPStorages`, `WebKit`, and `Cookies`. Bundle-ID matches require a
   dot boundary (so `com.foo.app` never claims `com.foo.app.beta`'s
   files), name matches are restricted to a few folders and blocked for
   generic names (`cache`, `data`, `support`, ...), and every candidate
   path is re-validated as a safe descendant of `~/Library` before it's
   ever shown in the UI.
3. **`Uninstaller`** moves everything to the Trash via
   `FileManager.trashItem` — never a permanent delete. It re-validates
   that the app is removable and that each path passes the safety check
   again at execution time, removes leftovers before the app bundle, and
   reports per-item success/failure.

Each leftover carries a `MatchConfidence`:

| Tier | Meaning | Selected by default? |
|---|---|---|
| `.exact` | Bundle-ID filename match | Yes |
| `.probable` | Group Container shared by team ID | Yes, flagged with a caution icon (other apps on the same team may use it too) |
| `.possible` | App-name-only match, no bundle ID involved | **No** — review before including it |

## What's not here yet

This is an early, actively-developed build. Known gaps against the full
design:

- No permission-gate onboarding for Full Disk Access.
- No vendor-uninstaller warnings (Adobe/Microsoft/Docker/etc.) yet.
- No admin-scoped removal of `/Library/LaunchDaemons` or
  `/Library/PrivilegedHelperTools` (would need a privileged helper —
  out of scope for now; those stay read-only).

## Building

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project AppReaper.xcodeproj -scheme AppReaper build
```

The `.xcodeproj` is generated from `project.yml` and isn't hand-edited —
run `xcodegen generate` again after adding or removing source files.

## Testing

```sh
xcodebuild -project AppReaper.xcodeproj -scheme AppReaper -destination 'platform=macOS' test
```

**Do not test real deletion against apps you care about.** Use a
throwaway app, a spare user account, or a VM until `Uninstaller` has been
verified safe for your workflow.

## Safety rules this project holds itself to

- All deletions go through `FileManager.trashItem` — nothing is ever
  permanently removed by this app.
- `com.apple.*` bundle IDs and anything under `/System/Applications` are
  hard-excluded from removal.
- No App Sandbox entitlement, ever — removing cross-app files requires
  broad filesystem access, and a sandboxed build would silently fail at
  that.

## License

MIT — see [LICENSE](LICENSE).
