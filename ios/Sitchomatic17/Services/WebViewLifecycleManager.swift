import Foundation
@preconcurrency import WebKit
import UIKit

@MainActor
final class WebViewLifecycleManager {
    static let shared = WebViewLifecycleManager()

    private let logger = DebugLogger.shared

    private let trackedWebViews = NSHashTable<WKWebView>.weakObjects()

    private struct TrackedEntry {
        let mountedAt: Date
        let label: String
    }
    private var trackingMetadata: [ObjectIdentifier: TrackedEntry] = [:]

    private var zombieSweeperTask: Task<Void, Never>?
    private var isPaused: Bool = false

    private static let zombieThreshold: TimeInterval = 600
    private static let heartbeatInterval: Duration = .seconds(300)

    private var backgroundObserver: (any NSObjectProtocol)?
    private var foregroundObserver: (any NSObjectProtocol)?

    private init() {
        startZombieSweeper()
        registerLifecycleObservers()
    }

    deinit {
        zombieSweeperTask?.cancel()
        if let bg = backgroundObserver { NotificationCenter.default.removeObserver(bg) }
        if let fg = foregroundObserver { NotificationCenter.default.removeObserver(fg) }
    }

    // MARK: - Deep Clean

    func performDeepClean(on webView: WKWebView, label: String = "unknown") {
        let id = ObjectIdentifier(webView)
        logger.log("Janitor: performDeepClean START — \(label)", category: .webView, level: .warning)

        webView.stopLoading()

        webView.navigationDelegate = nil
        webView.uiDelegate = nil

        let ucc = webView.configuration.userContentController
        ucc.removeAllUserScripts()
        ucc.removeAllScriptMessageHandlers()

        webView.removeFromSuperview()

        webView.loadHTMLString("", baseURL: nil)

        trackedWebViews.remove(webView)
        trackingMetadata.removeValue(forKey: id)

        Task {
            let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
            await WKWebsiteDataStore.default().removeData(ofTypes: allTypes, modifiedSince: .distantPast)
            logger.log("Janitor: XPC data purge complete — \(label)", category: .webView, level: .warning)
        }

        logger.log("Janitor: performDeepClean DONE — \(label)", category: .webView, level: .success)
    }

    // MARK: - Tracking

    func track(_ webView: WKWebView, label: String = "session") {
        let id = ObjectIdentifier(webView)
        trackedWebViews.add(webView)
        trackingMetadata[id] = TrackedEntry(mountedAt: Date(), label: label)
        logger.log("Janitor: tracking webView — \(label) (total: \(trackedWebViews.count))", category: .webView, level: .debug)
    }

    func untrack(_ webView: WKWebView) {
        let id = ObjectIdentifier(webView)
        trackedWebViews.remove(webView)
        trackingMetadata.removeValue(forKey: id)
    }

    var trackedCount: Int { trackedWebViews.count }

    // MARK: - Zombie Sweeper

    private func startZombieSweeper() {
        zombieSweeperTask?.cancel()
        zombieSweeperTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.heartbeatInterval)
                guard !Task.isCancelled else { break }
                guard let self, !self.isPaused else { continue }
                self.sweepZombies()
            }
        }
    }

    private func sweepZombies() {
        let now = Date()
        var zombiesFound = 0

        let allViews = trackedWebViews.allObjects

        for webView in allViews {
            let id = ObjectIdentifier(webView)
            guard let entry = trackingMetadata[id] else {
                logger.log("Janitor: untracked orphan found — deep cleaning", category: .webView, level: .warning)
                performDeepClean(on: webView, label: "orphan")
                zombiesFound += 1
                continue
            }

            let age = now.timeIntervalSince(entry.mountedAt)
            if age > Self.zombieThreshold {
                logger.log("Janitor: zombie detected — \(entry.label) alive \(Int(age))s (threshold: \(Int(Self.zombieThreshold))s)", category: .webView, level: .warning)
                performDeepClean(on: webView, label: "zombie:\(entry.label)")
                zombiesFound += 1
            }
        }

        if zombiesFound > 0 {
            logger.log("Janitor: sweep complete — \(zombiesFound) zombie(s) obliterated, \(trackedWebViews.count) remaining", category: .webView, level: .warning)
        } else {
            logger.log("Janitor: sweep complete — all \(trackedWebViews.count) tracked views healthy", category: .webView, level: .trace)
        }
    }

    // MARK: - App Lifecycle

    private func registerLifecycleObservers() {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPaused = true
                self?.logger.log("Janitor: paused (app backgrounded)", category: .webView, level: .debug)
            }
        }

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPaused = false
                self?.logger.log("Janitor: resumed (app foregrounded)", category: .webView, level: .debug)
            }
        }
    }

    // MARK: - Manual Nuke All

    func nukeAll() {
        let allViews = trackedWebViews.allObjects
        logger.log("Janitor: NUKE ALL — obliterating \(allViews.count) tracked WebViews", category: .webView, level: .critical)

        for webView in allViews {
            let id = ObjectIdentifier(webView)
            let label = trackingMetadata[id]?.label ?? "unknown"
            performDeepClean(on: webView, label: "nuke:\(label)")
        }

        trackingMetadata.removeAll()
    }

    // MARK: - Diagnostics

    var diagnosticSummary: String {
        let count = trackedWebViews.count
        let paused = isPaused ? " (PAUSED)" : ""
        let oldest = trackingMetadata.values.map(\.mountedAt).min()
        let oldestAge: String
        if let oldest {
            oldestAge = " oldest=\(Int(Date().timeIntervalSince(oldest)))s"
        } else {
            oldestAge = ""
        }
        return "Janitor: \(count) tracked\(oldestAge)\(paused)"
    }
}
