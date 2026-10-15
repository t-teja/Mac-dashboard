# Mac Space Saver

Mac Space Saver is a native macOS menu-bar desk for storage and performance. It lives in the menu bar, opens into a full window, and shows free space, a folder map, CPU and memory, OS images, duplicate files, installed apps, and the local footprint of cloud folders. It can also keep the Mac from idle-sleep while an agent or another background job is running.

It does not have an account, a network call, or telemetry. Maps, settings, and the cleanup log stay on the Mac.

## Install

You need macOS 14 or later and the Swift command-line tools (`xcode-select --install` if `swift` is missing). Xcode itself is optional.

```bash
git clone https://github.com/t-teja/Mac-dashboard.git
cd Mac-dashboard
swift test
zsh scripts/bundle.sh
open "build/Mac Space Saver.app"
```

`scripts/bundle.sh` builds a release binary, wraps it as `build/Mac Space Saver.app`, and ad-hoc signs it. The app is an agent (`LSUIElement`), so it does not take a Dock icon until you open the desk. The menu-bar mark is a planet with a ring. A dot on that icon means stay-awake is on.

Click the menu-bar item, then **Open the desk**. To open the window on launch:

```bash
open "build/Mac Space Saver.app" --args --desk
```

In Settings you can turn on launch at login. The global shortcut stays off until you enable it, so it does not take a key while you are in another app. Notification permission is requested only after you press **Allow alerts**.

Full Disk Access is not required. If macOS asks for Documents, Photos, or another protected folder, denying the prompt leaves that folder out of the map. The overview then says the map was partial.

## What you can do

| Page | What it shows | What it changes |
| --- | --- | --- |
| Overview | Free space, volumes, and how the map changed | Nothing |
| Disk | An icicle of a folder you choose | Nothing until you add items to the bin |
| Performance | Cores, memory, CPU, disk, network, your processes | Quit, pause, or lower priority of your own apps |
| Images | Android system images, macOS installers, simulator runtimes, Docker | Only after you add them and confirm |
| Duplicates | Files that hash the same, inside folders you pick | Extra copies only, and only after confirm |
| Apps | Third-party apps in `/Applications` and `~/Applications` | The app, plus leftovers you check |
| Cloud | Local iCloud, CloudStorage, and Google Drive cache size | Nothing. There is no delete control |
| Settings | Menu-bar metric, stay awake, alert levels, login item, shortcut | Preferences on this Mac |

## Stay awake

The menu-bar panel and Settings both have **Stay awake**. While it is on, Mac Space Saver holds a `PreventUserIdleSystemSleep` assertion, so the Mac does not idle-sleep and agents or other background work keep running. The display can still turn off. **Keep the display on** switches to `PreventUserIdleDisplaySleep`, which also holds the system awake and leaves the screen lit.

Durations are 30 minutes, 1 hour, 2 hours, until 7:00 in the morning, or until you turn it off. The assertion is released when the time ends, when you turn it off, or when the app quits. It is off until you enable it. It does not change the Energy Saver schedule permanently.

Mapping a folder is read-only. It does not follow symlinks, does not read file contents, and does not download iCloud placeholders. Docker is queried only after **Look at Docker**, so opening Images does not start the daemon.

## Cleanup safety

Nothing is removed from a page button. You add items to the bin, review the list, and confirm.

- Files go to the Trash with `FileManager.trashItem`. The exported script uses Finder’s delete command, which is also the Trash. It asks you to type `DELETE` before it runs.
- The safety gate runs again at removal time. Personal folders (Documents, Desktop, Pictures, Movies, Music), Mail, Messages, Photos, keychains, containers, cloud storage, `.git`, and system roots are refused even if they were staged.
- Duplicate removal keeps at least one copy and re-hashes the file immediately before it is trashed.
- Simulator runtimes (`simctl`) and Docker images are not recoverable from the Trash. They need a second confirmation, and the identifier is checked before the command runs.
- Process controls apply only to your user. Finder, Dock, WindowServer, `launchd`, and Mac Space Saver itself are refused. There is no per-app CPU percent cap. Low priority is a nice value.

**Export script** writes a zsh file you can read. It is not executed by the export. The script contains the real paths you confirmed, because that is what it has to delete. It is a local file. It is not uploaded.

## Tech stack

- Swift 5 language mode, Swift tools 6.1, macOS 14+
- SwiftUI for the menu bar and the desk, AppKit for the window, status item, and panels
- Charts for the performance sparklines
- No third-party packages
- The Swift package modules are `HeadroomCore` (logic) and `Headroom` (the app). The product you launch is `Mac Space Saver.app`, executable `MacSpaceSaver`. `HeadroomTests` uses Swift Testing (`import Testing`), which is what the command-line tools provide
- IOKit for disk counters, Mach host statistics for CPU and memory, `proc_pidinfo` for processes, CryptoKit for SHA-256, Carbon for the optional hotkey, ServiceManagement for the login item, UserNotifications for alerts

The release app is produced by Swift Package Manager and a small bundling script. There is no Xcode project. `xcodebuild` is not required.

## Architecture

```
Menu bar item  →  glance panel  →  desk window
                      │                  │
                      └──────── AppModel ┘
                                    │
                             HeadroomCore
                    ┌───────────┬───┴────┬───────────┐
               SystemSampler  Walker  SecurityGate  Scanners
               (1 Hz, read)   (on demand) (denylist) (images, apps,
                                                      duplicates, cloud)
```

`AppModel` owns the latest sample, the open map, the bin, and settings. Sampling runs about once a second and never walks the disk. A folder map starts only when you ask for one.

`SystemSampler` reads host CPU counters, memory pressure, disk IO, network totals, battery, thermal state, and a short process list (busiest CPUs plus the largest resident processes).

`DirectoryWalker` builds the icicle. It collapses `node_modules`, `.git`, DerivedData, and similar trees into one node, stays on the same volume, and skips Trash and Spotlight folders. Depth and child count are capped.

`Classifier` tags known caches (Xcode, package managers, Android images, local model folders). A tag is not permission to delete. `SecurityGate` has to agree, and `CleanupPlan` checks a third time when you confirm or export a script.

`ScanStore` keeps the latest map and the previous one under `~/Library/Application Support/Mac Space Saver`, plus a log of bytes you actually freed. Settings live in UserDefaults. Alerts (low free space, memory pressure, sustained CPU, heat, a large jump in reviewable bytes) notify only after you allow them, and the same alert waits 30 minutes before it can notify again.

Paths drawn in the desk are passed through `SecurityGate.displayPath`. A path inside your home folder is shown as `~/…`, and the home folder itself is labeled Home. The account name is not part of the source and is not shown on those rows. Removal still uses the real path, which never leaves the Mac except into a script you export yourself.

## Development

```bash
swift test
swift build
zsh scripts/bundle.sh
```

`swift test` runs the safety gate, the icicle layout, alert cooldown, the Monday postcard rule, duplicate grouping, the export script (it must not contain `rm`), and the path display. Tests use fixture paths under `/Users/ada`. They do not read your home folder, except one hash test that creates a file in the temp directory and deletes that file.

Do not point a cleanup, `simctl delete`, or `docker image rm` at a machine just to try the runner. The unit tests never call `CleanupRunner.perform`.

## Privacy

- No network. No analytics. No account.
- File contents are not read during a map. Duplicate search hashes bytes only inside folders you choose, and it skips files that are not downloaded from iCloud.
- Cloud sizes are local allocated bytes, not the account quota.
- Saved maps can contain folder paths. They stay in Application Support on this Mac. This repository does not contain a map, a log, or a home-folder listing.
