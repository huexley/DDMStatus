# DDMStatusApp

A lightweight macOS menu bar app that displays **Apple DDM (Declarative Device Management)** update enforcement status at a glance.

Built for Mac admins who deploy OS updates via DDM through Jamf Pro, Mosyle, Fleet, or any MDM that supports Apple's DDM framework.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![License MIT](https://img.shields.io/badge/License-MIT-green)

## What it does

DDMStatusApp sits in the menu bar and shows:

- **Colored status icon** — green checkmark (up to date), or a countdown in days with color coding (blue → yellow → orange → red)
- **Update details** — required version, enforcement deadline, days remaining, staged update detection
- **System health** — free disk space and uptime (days since last reboot)
- **Quick actions** — open Software Update, contact IT support (phone/email/web), refresh

## Screenshot

<img width="335" height="429" alt="Capture d’écran 2026-02-16 à 16 19 44" src="https://github.com/user-attachments/assets/b846e87a-1812-488d-878c-98feda3378fb" />



```

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode Command Line Tools (`xcode-select --install`)
- A DDM-capable MDM sending OS update enforcement commands

## Build

```bash
# Clone the repo
git clone https://github.com/YOUR_USERNAME/DDMStatusApp.git
cd DDMStatusApp

# Build for current architecture
chmod +x build.sh
./build.sh

# Or build a universal binary (Apple Silicon + Intel)
./build.sh universal
```

The compiled `.app` bundle will be in `build/DDMStatusApp.app`.

### Manual build (no script)

```bash
swiftc -o DDMStatusApp DDMStatusApp.swift \
    -framework Cocoa \
    -framework SwiftUI \
    -target arm64-apple-macos13.0 \
    -parse-as-library -O
```

## Install

Copy the app to `/Applications` or deploy via your MDM:

```bash
cp -R build/DDMStatusApp.app /Applications/
```

To auto-launch at login, add it to **System Settings → General → Login Items**, or deploy a LaunchAgent:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.github.ddmstatusapp</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/DDMStatusApp.app/Contents/MacOS/DDMStatusApp</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
```

Save as `~/Library/LaunchAgents/com.github.ddmstatusapp.plist`.

## Configuration

DDMStatusApp reads its settings from a preference plist. Managed Preferences (deployed via MDM configuration profile) take priority over the local file.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `MinimumDiskFreePercentage` | Integer | `10` | Warn when free space drops below this % |
| `DaysOfExcessiveUptimeWarning` | Integer | `7` | Warn after this many days without reboot (0 = disabled) |
| `SupportTeamName` | String | `IT Support` | Displayed in the footer |
| `SupportTeamPhone` | String | – | Shows a phone button if set |
| `SupportTeamEmail` | String | – | Shows an email button if set |
| `SupportTeamWebsite` | String | – | Shows a web button if set |

### Preference domain

`com.github.ddmstatusapp`

**Paths searched (in order):**
1. `/Library/Managed Preferences/com.github.ddmstatusapp.plist` (MDM)
2. `/Library/Preferences/com.github.ddmstatusapp.plist` (local)

### Example: local plist

```bash
sudo defaults write /Library/Preferences/com.github.ddmstatusapp \
    SupportTeamName "IT Helpdesk" \
    SupportTeamEmail "support@example.com" \
    SupportTeamPhone "+1 555 0123" \
    SupportTeamWebsite "https://support.example.com" \
    MinimumDiskFreePercentage -int 15 \
    DaysOfExcessiveUptimeWarning -int 14
```

### Example: Jamf Pro configuration profile

Deploy a custom settings payload targeting `com.github.ddmstatusapp` with the keys above.

## How DDM enforcement detection works

The app reads `/var/log/install.log` and searches for the latest line containing `EnforcedInstallDate`. When Apple DDM pushes an OS update enforcement via MDM, macOS logs entries in this format:

```
... |EnforcedInstallDate:2026-03-13T12:00:00|VersionString:26.3| ...
```

The app extracts the deadline date and required version, then compares against the currently installed version to determine status.

> **Note:** The staged update check looks for `/System/Volumes/Update/Prepared` to determine if the update has already been downloaded and is ready to install.

## Status icon color coding

| Color | Meaning |
|-------|---------|
| 🟢 Green (✓) | macOS is up to date |
| 🔵 Blue | More than 7 days remaining |
| 🟡 Yellow | 4–7 days remaining |
| 🟠 Orange | 2–3 days remaining |
| 🔴 Red | 0–1 days remaining |
| ⚪ Gray (–) | Unable to determine status |

## License

MIT — see [LICENSE](LICENSE).

## Credits

Built with SwiftUI for the Mac admin community.
