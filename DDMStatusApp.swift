// DDMStatusApp.swift
// A macOS menu bar app that displays Apple DDM (Declarative Device Management)
// update enforcement status, disk space, and system uptime.
//
// Copyright (c) 2026 HEP Vaud – IT Department
// Licensed under the MIT License. See LICENSE file for details.

import SwiftUI
import Cocoa

// MARK: - App Entry Point

@main
struct DDMStatusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var ddmManager = DDMManager()
    var refreshTimer: Timer?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // Configure the popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: DDMStatusView(ddmManager: ddmManager)
        )
        
        // Set up the status bar button
        if let button = statusItem.button {
            updateStatusButton()
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        // Refresh every hour
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.ddmManager.refresh()
            self?.updateStatusButton()
        }
        
        // Hide the dock icon (menu bar app only)
        NSApp.setActivationPolicy(.accessory)
    }
    
    // MARK: Status Icon
    
    func updateStatusButton() {
        guard let button = statusItem.button else { return }
        button.image = createStatusIcon()
        button.title = ""
    }
    
    /// Draws a 22×22 status icon with a colored circle and contextual label:
    /// - Green checkmark when up to date
    /// - Colored number showing days remaining until forced update
    /// - Gray dash when status is unknown
    func createStatusIcon() -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size, flipped: false) { rect in
            
            let color: NSColor
            let text: String
            
            if self.ddmManager.isUpToDate {
                color = .systemGreen
                text = "✓"
            } else if let days = self.ddmManager.daysRemaining {
                text = "\(days)"
                switch days {
                case ...1:   color = .systemRed
                case ...3:   color = .systemOrange
                case ...7:   color = .systemYellow
                default:     color = .systemBlue
                }
            } else {
                color = .systemGray
                text = "–"
            }
            
            // Background circle
            let circlePath = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            color.setFill()
            circlePath.fill()
            
            // Circular arrow hint (when update is pending)
            if !self.ddmManager.isUpToDate {
                NSColor.white.withAlphaComponent(0.3).setStroke()
                let arrowPath = NSBezierPath()
                arrowPath.appendArc(
                    withCenter: NSPoint(x: rect.midX, y: rect.midY),
                    radius: 9,
                    startAngle: 90,
                    endAngle: -135,
                    clockwise: true
                )
                arrowPath.lineWidth = 1.5
                arrowPath.stroke()
            }
            
            // Center label
            let fontSize: CGFloat = self.ddmManager.isUpToDate ? 14 : 12
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: fontSize),
                .foregroundColor: NSColor.white
            ]
            let attributed = NSAttributedString(string: text, attributes: attributes)
            let textSize = attributed.size()
            attributed.draw(in: NSRect(
                x: (rect.width - textSize.width) / 2,
                y: (rect.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            ))
            
            return true
        }
        
        image.isTemplate = false
        return image
    }
    
    // MARK: Popover Toggle
    
    @objc func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                ddmManager.refresh()
                updateStatusButton()
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

// MARK: - DDM Manager

class DDMManager: ObservableObject {
    
    // OS version
    @Published var installedVersion: String = "–"
    @Published var requiredVersion: String?
    @Published var isUpToDate: Bool = true
    
    // Enforcement deadline
    @Published var deadlineDate: Date?
    @Published var daysRemaining: Int?
    
    // Disk space
    @Published var freeSpaceGB: Double = 0
    @Published var freeSpacePercent: Double = 0
    @Published var minimumFreePercent: Int = 10
    
    // Uptime
    @Published var lastRebootDays: Int = 0
    @Published var excessiveUptimeDays: Int = 7
    
    // Staged update
    @Published var updateStaged: Bool = false
    
    // Support info (configurable via plist)
    @Published var supportTeamName: String = "IT Support"
    @Published var supportTeamPhone: String = ""
    @Published var supportTeamEmail: String = ""
    @Published var supportTeamWebsite: String = ""
    
    /// Preference domain used for configuration.
    /// Override via Managed Preferences (MDM) or a local plist.
    static let preferenceDomain = "com.github.ddmstatusapp"
    
    init() {
        refresh()
    }
    
    func refresh() {
        loadInstalledVersion()
        loadDDMEnforcement()
        loadDiskSpace()
        loadUptime()
        loadPreferences()
        checkStagedUpdate()
    }
    
    // MARK: Data Loaders
    
    private func loadInstalledVersion() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sw_vers")
        process.arguments = ["-productVersion"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        installedVersion = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "–"
    }
    
    /// Parses `/var/log/install.log` to find the latest DDM enforcement entry.
    /// Expected format: `|EnforcedInstallDate:2026-03-13T12:00:00|VersionString:26.3|`
    private func loadDDMEnforcement() {
        let logPath = "/var/log/install.log"
        guard let logContent = try? String(contentsOfFile: logPath, encoding: .utf8) else {
            isUpToDate = true
            return
        }
        
        // Find the last EnforcedInstallDate entry (most recent)
        let lines = logContent.components(separatedBy: .newlines)
        var lastEnforcedLine: String?
        
        for line in lines.reversed() {
            if line.contains("EnforcedInstallDate") {
                lastEnforcedLine = line
                break
            }
        }
        
        guard let enforcedLine = lastEnforcedLine else {
            isUpToDate = true
            return
        }
        
        // Extract deadline date and required version
        if let dateRange = enforcedLine.range(of: "EnforcedInstallDate:"),
           let versionRange = enforcedLine.range(of: "VersionString:") {
            
            // Parse deadline date
            let afterDate = enforcedLine[dateRange.upperBound...]
            if let pipeIndex = afterDate.firstIndex(of: "|") {
                let dateString = String(afterDate[..<pipeIndex])
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [
                    .withFullDate, .withTime,
                    .withDashSeparatorInDate, .withColonSeparatorInTime
                ]
                if let date = formatter.date(from: dateString) {
                    deadlineDate = date
                    daysRemaining = Calendar.current
                        .dateComponents([.day], from: Date(), to: date).day
                }
            }
            
            // Parse required version
            let afterVersion = enforcedLine[versionRange.upperBound...]
            if let pipeIndex = afterVersion.firstIndex(of: "|") {
                requiredVersion = String(afterVersion[..<pipeIndex])
            } else {
                requiredVersion = String(afterVersion)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Compare installed vs required
        if let required = requiredVersion {
            isUpToDate = compareVersions(installedVersion, required) >= 0
        }
    }
    
    /// Semantic version comparison. Returns -1, 0, or 1.
    private func compareVersions(_ v1: String, _ v2: String) -> Int {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }
        
        for i in 0..<max(parts1.count, parts2.count) {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 < p2 { return -1 }
            if p1 > p2 { return 1 }
        }
        return 0
    }
    
    private func loadDiskSpace() {
        let fileURL = URL(fileURLWithPath: "/")
        if let values = try? fileURL.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]),
           let total = values.volumeTotalCapacity,
           let available = values.volumeAvailableCapacityForImportantUsage {
            freeSpaceGB = Double(available) / 1_000_000_000
            freeSpacePercent = (Double(available) / Double(total)) * 100
        }
    }
    
    private func loadUptime() {
        var boottime = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        
        if sysctl(&mib, 2, &boottime, &size, nil, 0) != -1 {
            let bootDate = Date(timeIntervalSince1970: Double(boottime.tv_sec))
            lastRebootDays = Calendar.current
                .dateComponents([.day], from: bootDate, to: Date()).day ?? 0
        }
    }
    
    /// Loads preferences from Managed Preferences (MDM) or local plist.
    /// Managed path takes priority over local path.
    ///
    /// Configurable keys:
    /// - `MinimumDiskFreePercentage` (Int, default: 10)
    /// - `DaysOfExcessiveUptimeWarning` (Int, default: 7, 0 = disabled)
    /// - `SupportTeamName` (String)
    /// - `SupportTeamPhone` (String)
    /// - `SupportTeamEmail` (String)
    /// - `SupportTeamWebsite` (String)
    private func loadPreferences() {
        let domain = DDMManager.preferenceDomain
        let managedPath = "/Library/Managed Preferences/\(domain).plist"
        let localPath = "/Library/Preferences/\(domain).plist"
        
        var prefs: NSDictionary?
        if FileManager.default.fileExists(atPath: managedPath) {
            prefs = NSDictionary(contentsOfFile: managedPath)
        } else if FileManager.default.fileExists(atPath: localPath) {
            prefs = NSDictionary(contentsOfFile: localPath)
        }
        
        if let prefs = prefs {
            minimumFreePercent = prefs["MinimumDiskFreePercentage"] as? Int ?? 10
            excessiveUptimeDays = prefs["DaysOfExcessiveUptimeWarning"] as? Int ?? 7
            supportTeamName = prefs["SupportTeamName"] as? String ?? "IT Support"
            supportTeamPhone = prefs["SupportTeamPhone"] as? String ?? ""
            supportTeamEmail = prefs["SupportTeamEmail"] as? String ?? ""
            supportTeamWebsite = prefs["SupportTeamWebsite"] as? String ?? ""
        }
    }
    
    private func checkStagedUpdate() {
        updateStaged = FileManager.default
            .fileExists(atPath: "/System/Volumes/Update/Prepared")
    }
    
    // MARK: Computed Properties
    
    var diskSpaceOK: Bool {
        freeSpacePercent >= Double(minimumFreePercent)
    }
    
    var uptimeOK: Bool {
        excessiveUptimeDays == 0 || lastRebootDays < excessiveUptimeDays
    }
    
    var deadlineFormatted: String {
        guard let date = deadlineDate else { return "–" }
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Status View

struct DDMStatusView: View {
    @ObservedObject var ddmManager: DDMManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            // Header
            HStack {
                Image(systemName: ddmManager.isUpToDate
                      ? "checkmark.circle.fill"
                      : "arrow.down.circle.fill")
                    .font(.title)
                    .foregroundColor(ddmManager.isUpToDate ? .green : statusColor)
                
                VStack(alignment: .leading) {
                    Text(ddmManager.isUpToDate ? "macOS is up to date" : "Update required")
                        .font(.headline)
                    Text("Installed: \(ddmManager.installedVersion)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.bottom, 4)
            
            Divider()
            
            // Update details (only shown when an update is pending)
            if !ddmManager.isUpToDate {
                GroupBox(label: Label("Update", systemImage: "arrow.triangle.2.circlepath")) {
                    VStack(alignment: .leading, spacing: 6) {
                        InfoRow(label: "Required version",
                                value: ddmManager.requiredVersion ?? "–")
                        InfoRow(label: "Deadline",
                                value: ddmManager.deadlineFormatted)
                        
                        HStack {
                            Text("Days remaining")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(ddmManager.daysRemaining ?? 0)")
                                .fontWeight(.bold)
                                .foregroundColor(statusColor)
                        }
                        
                        if ddmManager.updateStaged {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Update downloaded")
                                    .font(.caption)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            
            // System health
            GroupBox(label: Label("System", systemImage: "desktopcomputer")) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: ddmManager.diskSpaceOK
                              ? "checkmark.circle.fill"
                              : "xmark.circle.fill")
                            .foregroundColor(ddmManager.diskSpaceOK ? .green : .red)
                        Text("Disk space")
                        Spacer()
                        Text(String(format: "%.1f GB (%.0f%%)",
                                    ddmManager.freeSpaceGB,
                                    ddmManager.freeSpacePercent))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Image(systemName: ddmManager.uptimeOK
                              ? "checkmark.circle.fill"
                              : "exclamationmark.triangle.fill")
                            .foregroundColor(ddmManager.uptimeOK ? .green : .orange)
                        Text("Last reboot")
                        Spacer()
                        Text(ddmManager.lastRebootDays == 0
                             ? "Today"
                             : "\(ddmManager.lastRebootDays) day(s) ago")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            
            Divider()
            
            // Actions
            if !ddmManager.isUpToDate {
                Button(action: openSoftwareUpdate) {
                    HStack {
                        Image(systemName: "gear")
                        Text("Open Software Update")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            
            // Support & refresh
            HStack(spacing: 12) {
                if !ddmManager.supportTeamPhone.isEmpty {
                    Button(action: callSupport) {
                        Image(systemName: "phone")
                    }
                    .buttonStyle(.bordered)
                    .help("Call \(ddmManager.supportTeamPhone)")
                }
                
                if !ddmManager.supportTeamEmail.isEmpty {
                    Button(action: emailSupport) {
                        Image(systemName: "envelope")
                    }
                    .buttonStyle(.bordered)
                    .help("Send email")
                }
                
                if !ddmManager.supportTeamWebsite.isEmpty {
                    Button(action: openWebsite) {
                        Image(systemName: "globe")
                    }
                    .buttonStyle(.bordered)
                    .help("Open website")
                }
                
                Spacer()
                
                Button(action: { ddmManager.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help("Refresh")
            }
            
            // Footer
            Text(ddmManager.supportTeamName)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding()
        .frame(width: 320)
    }
    
    // MARK: Helpers
    
    var statusColor: Color {
        guard let days = ddmManager.daysRemaining else { return .gray }
        switch days {
        case ...1:   return .red
        case ...3:   return .orange
        case ...7:   return .yellow
        default:     return .blue
        }
    }
    
    func openSoftwareUpdate() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preferences.softwareupdate")!
        )
    }
    
    func callSupport() {
        let phone = ddmManager.supportTeamPhone.replacingOccurrences(of: " ", with: "")
        if let url = URL(string: "tel:\(phone)") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func emailSupport() {
        if let url = URL(string: "mailto:\(ddmManager.supportTeamEmail)") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func openWebsite() {
        if let url = URL(string: ddmManager.supportTeamWebsite) {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}
