import SwiftUI

struct DeveloperSettingsView: View {
    @State private var settings: AutomationSettings = AutomationSettingsPersistence.shared.load()
    @State private var showResetConfirm: Bool = false
    @State private var savedToast: Bool = false
    @State private var searchText: String = ""
    @State private var expandedSections: Set<String> = []
    @State private var showJumpMenu: Bool = false

    private let persistence = AutomationSettingsPersistence.shared
    private let defaults = AutomationSettings()

    var body: some View {
        ScrollViewReader { proxy in
            List {
                statusHeader
                if shouldShow("true detection") { collapsibleSection("trueDetection", title: "TRUE DETECTION", icon: "target", color: .red) { trueDetectionContent } }
                if shouldShow("page loading") { collapsibleSection("pageLoading", title: "Page Loading", icon: "globe", color: .blue) { pageLoadingContent } }
                if shouldShow("field detection") { collapsibleSection("fieldDetection", title: "Field Detection", icon: "text.cursor", color: .cyan) { fieldDetectionContent } }
                if shouldShow("cookie consent") { collapsibleSection("cookie", title: "Cookie / Consent", icon: "hand.raised.fill", color: .orange) { cookieContent } }
                if shouldShow("credential entry typing") { collapsibleSection("credential", title: "Credential Entry", icon: "keyboard.fill", color: .indigo) { credentialContent } }
                if shouldShow("pattern strategy") { collapsibleSection("pattern", title: "Pattern Strategy", icon: "list.number", color: .purple) { patternContent } }
                if shouldShow("fallback chain") { collapsibleSection("fallback", title: "Fallback Chain", icon: "arrow.triangle.branch", color: .mint) { fallbackContent } }
                if shouldShow("submit behavior") { collapsibleSection("submit", title: "Submit Behavior", icon: "paperplane.fill", color: .teal) { submitContent } }
                if shouldShow("post submit evaluation") { collapsibleSection("postSubmit", title: "Post-Submit Evaluation", icon: "checkmark.diamond.fill", color: .green) { postSubmitContent } }
                if shouldShow("retry requeue") { collapsibleSection("retry", title: "Retry / Requeue", icon: "arrow.clockwise", color: .orange) { retryContent } }
                if shouldShow("stealth fingerprint") { collapsibleSection("stealth", title: "Stealth / Fingerprinting", icon: "eye.slash.fill", color: .purple) { stealthContent } }
                if shouldShow("screenshot debug") { collapsibleSection("screenshot", title: "Screenshot / Debug", icon: "camera.fill", color: .pink) { screenshotContent } }
                if shouldShow("concurrency") { collapsibleSection("concurrency", title: "Concurrency", icon: "cpu.fill", color: .blue) { concurrencyContent } }
                if shouldShow("network") { collapsibleSection("network", title: "Network Per-Mode", icon: "network", color: .indigo) { networkContent } }
                if shouldShow("url rotation") { collapsibleSection("url", title: "URL Rotation", icon: "arrow.triangle.2.circlepath", color: .cyan) { urlContent } }
                if shouldShow("blacklist") { collapsibleSection("blacklist", title: "Blacklist / Auto-Actions", icon: "xmark.shield.fill", color: .red) { blacklistContent } }
                if shouldShow("human simulation") { collapsibleSection("human", title: "Human Simulation", icon: "person.fill", color: .teal) { humanContent } }
                if shouldShow("login button detection") { collapsibleSection("loginButton", title: "Login Button Detection", icon: "rectangle.and.hand.point.up.left.fill", color: .green) { loginButtonContent } }
                if shouldShow("time delay") { collapsibleSection("delays", title: "Time Delays", icon: "timer", color: .yellow) { timeDelayContent } }
                if shouldShow("mfa two factor") { collapsibleSection("mfa", title: "MFA / Two-Factor", icon: "lock.shield.fill", color: .indigo) { mfaContent } }
                if shouldShow("captcha") { collapsibleSection("captcha", title: "CAPTCHA", icon: "shield.checkered", color: .brown) { captchaContent } }
                if shouldShow("session management") { collapsibleSection("session", title: "Session Management", icon: "rectangle.stack.fill", color: .gray) { sessionContent } }
                if shouldShow("blank page recovery") { collapsibleSection("blankPage", title: "Blank Page Recovery", icon: "doc.questionmark.fill", color: .gray) { blankPageContent } }
                if shouldShow("error classification") { collapsibleSection("errorClass", title: "Error Classification", icon: "exclamationmark.triangle.fill", color: .red) { errorClassContent } }
                if shouldShow("form interaction") { collapsibleSection("formInteraction", title: "Form Interaction", icon: "text.badge.checkmark", color: .mint) { formContent } }
                if shouldShow("viewport window") { collapsibleSection("viewport", title: "Viewport & Window", icon: "rectangle.dashed", color: .blue) { viewportContent } }
                if shouldShow("settlement gate") { collapsibleSection("settlement", title: "V4.2 Settlement Gate", icon: "gauge.with.dots.needle.33percent", color: .orange) { settlementContent } }
                if shouldShow("ai telemetry") { collapsibleSection("ai", title: "AI Telemetry", icon: "brain.head.profile.fill", color: .green) { aiContent } }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Developer Settings")
            .searchable(text: $searchText, prompt: "Search settings...")
            .onChange(of: searchText) { _, newValue in
                if !newValue.isEmpty {
                    expandedSections = Set(allSectionKeys)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        if expandedSections.isEmpty {
                            expandedSections = Set(allSectionKeys)
                        } else {
                            expandedSections.removeAll()
                        }
                    } label: {
                        Image(systemName: expandedSections.isEmpty ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                    }
                    Button { showJumpMenu = true } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                }
            }
            .sheet(isPresented: $showJumpMenu) {
                jumpMenuSheet(proxy: proxy)
            }
            .safeAreaInset(edge: .bottom) { stickyBottomBar }
            .overlay(alignment: .top) { toastOverlay }
            .alert("Reset All Settings?", isPresented: $showResetConfirm) {
                Button("Reset", role: .destructive) {
                    persistence.reset()
                    settings = AutomationSettings().normalizedTimeouts()
                    flashSaved()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will restore all automation settings to their defaults.")
            }
        }
    }

    // MARK: - Section Keys & Labels

    private var allSectionKeys: [String] {
        ["trueDetection","pageLoading","fieldDetection","cookie","credential","pattern","fallback","submit","postSubmit","retry","stealth","screenshot","concurrency","network","url","blacklist","human","loginButton","delays","mfa","captcha","session","blankPage","errorClass","formInteraction","viewport","settlement","ai"]
    }

    private static let sectionLabels: [String: String] = [
        "trueDetection": "TRUE DETECTION", "pageLoading": "Page Loading", "fieldDetection": "Field Detection",
        "cookie": "Cookie", "credential": "Credential Entry", "pattern": "Pattern Strategy",
        "fallback": "Fallback Chain", "submit": "Submit Behavior", "postSubmit": "Post-Submit",
        "retry": "Retry/Requeue", "stealth": "Stealth", "screenshot": "Screenshot",
        "concurrency": "Concurrency", "network": "Network", "url": "URL Rotation",
        "blacklist": "Blacklist", "human": "Human Sim", "loginButton": "Login Button",
        "delays": "Time Delays", "mfa": "MFA", "captcha": "CAPTCHA",
        "session": "Session Mgmt", "blankPage": "Blank Page", "errorClass": "Error Class",
        "formInteraction": "Form Interaction", "viewport": "Viewport", "settlement": "Settlement Gate",
        "ai": "AI Telemetry"
    ]

    // MARK: - Modified Count (Comprehensive)

    private var modifiedCount: Int {
        let d = defaults
        var count = 0
        if settings.trueDetectionEnabled != d.trueDetectionEnabled { count += 1 }
        if settings.trueDetectionPriority != d.trueDetectionPriority { count += 1 }
        if settings.trueDetectionHardPauseMs != d.trueDetectionHardPauseMs { count += 1 }
        if settings.trueDetectionTripleClickCount != d.trueDetectionTripleClickCount { count += 1 }
        if settings.trueDetectionTripleClickDelayMs != d.trueDetectionTripleClickDelayMs { count += 1 }
        if settings.trueDetectionSubmitCycleCount != d.trueDetectionSubmitCycleCount { count += 1 }
        if settings.trueDetectionButtonRecoveryTimeoutMs != d.trueDetectionButtonRecoveryTimeoutMs { count += 1 }
        if settings.trueDetectionMaxAttempts != d.trueDetectionMaxAttempts { count += 1 }
        if settings.trueDetectionPostClickWaitMs != d.trueDetectionPostClickWaitMs { count += 1 }
        if settings.trueDetectionCooldownMinutes != d.trueDetectionCooldownMinutes { count += 1 }
        if settings.trueDetectionStrictWaits != d.trueDetectionStrictWaits { count += 1 }
        if settings.trueDetectionNoProxyRotation != d.trueDetectionNoProxyRotation { count += 1 }
        if settings.pageLoadTimeout != d.pageLoadTimeout { count += 1 }
        if settings.pageLoadRetries != d.pageLoadRetries { count += 1 }
        if settings.retryBackoffMultiplier != d.retryBackoffMultiplier { count += 1 }
        if settings.waitForJSRenderMs != d.waitForJSRenderMs { count += 1 }
        if settings.fullSessionResetOnFinalRetry != d.fullSessionResetOnFinalRetry { count += 1 }
        if settings.fieldVerificationEnabled != d.fieldVerificationEnabled { count += 1 }
        if settings.fieldVerificationTimeout != d.fieldVerificationTimeout { count += 1 }
        if settings.autoCalibrationEnabled != d.autoCalibrationEnabled { count += 1 }
        if settings.calibrationConfidenceThreshold != d.calibrationConfidenceThreshold { count += 1 }
        if settings.dismissCookieNotices != d.dismissCookieNotices { count += 1 }
        if settings.cookieDismissDelayMs != d.cookieDismissDelayMs { count += 1 }
        if settings.typingSpeedMinMs != d.typingSpeedMinMs { count += 1 }
        if settings.typingSpeedMaxMs != d.typingSpeedMaxMs { count += 1 }
        if settings.backspaceProbability != d.backspaceProbability { count += 1 }
        if settings.fieldFocusDelayMs != d.fieldFocusDelayMs { count += 1 }
        if settings.interFieldDelayMs != d.interFieldDelayMs { count += 1 }
        if settings.maxSubmitCycles != d.maxSubmitCycles { count += 1 }
        if settings.patternLearningEnabled != d.patternLearningEnabled { count += 1 }
        if settings.preferCalibratedPatternsFirst != d.preferCalibratedPatternsFirst { count += 1 }
        if settings.fallbackToLegacyFill != d.fallbackToLegacyFill { count += 1 }
        if settings.fallbackToOCRClick != d.fallbackToOCRClick { count += 1 }
        if settings.fallbackToVisionMLClick != d.fallbackToVisionMLClick { count += 1 }
        if settings.fallbackToCoordinateClick != d.fallbackToCoordinateClick { count += 1 }
        if settings.submitRetryCount != d.submitRetryCount { count += 1 }
        if settings.submitRetryDelayMs != d.submitRetryDelayMs { count += 1 }
        if settings.waitForResponseSeconds != d.waitForResponseSeconds { count += 1 }
        if settings.rapidPollEnabled != d.rapidPollEnabled { count += 1 }
        if settings.redirectDetection != d.redirectDetection { count += 1 }
        if settings.errorBannerDetection != d.errorBannerDetection { count += 1 }
        if settings.contentChangeDetection != d.contentChangeDetection { count += 1 }
        if settings.maxConcurrency != d.maxConcurrency { count += 1 }
        if settings.fixedPairCount != d.fixedPairCount { count += 1 }
        if settings.liveUserPairCount != d.liveUserPairCount { count += 1 }
        if settings.stealthJSInjection != d.stealthJSInjection { count += 1 }
        if settings.fingerprintSpoofing != d.fingerprintSpoofing { count += 1 }
        if settings.userAgentRotation != d.userAgentRotation { count += 1 }
        if settings.viewportRandomization != d.viewportRandomization { count += 1 }
        if settings.urlRotationEnabled != d.urlRotationEnabled { count += 1 }
        if settings.reEnableURLAfterSeconds != d.reEnableURLAfterSeconds { count += 1 }
        if settings.smartURLSelection != d.smartURLSelection { count += 1 }
        if settings.proxyRotateOnDisabled != d.proxyRotateOnDisabled { count += 1 }
        if settings.proxyRotateOnFailure != d.proxyRotateOnFailure { count += 1 }
        if settings.v42SettlementGateEnabled != d.v42SettlementGateEnabled { count += 1 }
        if settings.v42SettlementMaxTimeoutMs != d.v42SettlementMaxTimeoutMs { count += 1 }
        if settings.betweenAttemptsDelayMs != d.betweenAttemptsDelayMs { count += 1 }
        if settings.betweenCredentialsDelayMs != d.betweenCredentialsDelayMs { count += 1 }
        if settings.globalPreActionDelayMs != d.globalPreActionDelayMs { count += 1 }
        if settings.globalPostActionDelayMs != d.globalPostActionDelayMs { count += 1 }
        if settings.mfaDetectionEnabled != d.mfaDetectionEnabled { count += 1 }
        if settings.captchaDetectionEnabled != d.captchaDetectionEnabled { count += 1 }
        if settings.blankPageRecoveryEnabled != d.blankPageRecoveryEnabled { count += 1 }
        if settings.sessionIsolation != d.sessionIsolation { count += 1 }
        if settings.freshWebViewPerAttempt != d.freshWebViewPerAttempt { count += 1 }
        if settings.clearCookiesBetweenAttempts != d.clearCookiesBetweenAttempts { count += 1 }
        if settings.aiTelemetryEnabled != d.aiTelemetryEnabled { count += 1 }
        return count
    }

    private var hasValidationIssues: Bool {
        settings.typingSpeedMinMs > settings.typingSpeedMaxMs ||
        settings.preFillPauseMinMs > settings.preFillPauseMaxMs ||
        settings.cyclePauseMinMs > settings.cyclePauseMaxMs ||
        settings.preActionPauseMinMs > settings.preActionPauseMaxMs ||
        settings.v42InterAttemptDelayMinSec > settings.v42InterAttemptDelayMaxSec ||
        settings.v42HumanVarianceMinMs > settings.v42HumanVarianceMaxMs
    }

    private func shouldShow(_ keywords: String) -> Bool {
        guard !searchText.isEmpty else { return true }
        return keywords.localizedStandardContains(searchText)
    }

    private func save() {
        persistence.save(settings)
        UnifiedSessionViewModel.shared.automationSettings = settings.normalizedTimeouts()
        DualFindViewModel.shared.automationSettings = settings.normalizedTimeouts()
        LoginViewModel.shared.automationSettings = settings.normalizedTimeouts()
        flashSaved()
    }

    private func flashSaved() {
        withAnimation(.spring(duration: 0.3)) { savedToast = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { savedToast = false }
        }
    }

    // MARK: - Status Header

    private var statusHeader: some View {
        Section {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(modifiedCount == 0 ? .green : hasValidationIssues ? .red : .orange)
                            .frame(width: 8, height: 8)
                        Text(modifiedCount == 0 ? "All Defaults" : "\(modifiedCount) Modified")
                            .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                            .foregroundStyle(modifiedCount == 0 ? .green : .orange)
                    }
                    if hasValidationIssues {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2).foregroundStyle(.red)
                            Text("Validation issues detected")
                                .font(.caption2).foregroundStyle(.red)
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("28 sections")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Text("180s timeout floor")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        } header: {
            Label("Automation Engine", systemImage: "wrench.and.screwdriver.fill")
        } footer: {
            Text("Changes apply to Unified, DualFind, and Login modes immediately on save.")
        }
    }

    // MARK: - Toast & Bottom Bar

    private var toastOverlay: some View {
        Group {
            if savedToast {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Settings Saved")
                }
                .font(.subheadline.bold()).foregroundStyle(.white)
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(.green.gradient, in: Capsule())
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 8)
            }
        }
    }

    private var stickyBottomBar: some View {
        HStack(spacing: 12) {
            Button {
                save()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down.fill")
                    Text("Save")
                }
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.blue.gradient, in: .rect(cornerRadius: 12))
            }
            .sensoryFeedback(.success, trigger: savedToast)

            Button(role: .destructive) { showResetConfirm = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset")
                }
                .font(.subheadline.bold())
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 12))
            }
            .sensoryFeedback(.warning, trigger: showResetConfirm)

            if modifiedCount > 0 {
                Text("\(modifiedCount)")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.orange, in: Capsule())
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - Jump Menu

    private func jumpMenuSheet(proxy: ScrollViewProxy) -> some View {
        NavigationStack {
            List {
                ForEach(allSectionKeys, id: \.self) { key in
                    Button {
                        expandedSections.insert(key)
                        showJumpMenu = false
                        Task {
                            try? await Task.sleep(for: .milliseconds(200))
                            withAnimation { proxy.scrollTo(key, anchor: .top) }
                        }
                    } label: {
                        Text(Self.sectionLabels[key] ?? key).font(.subheadline)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Jump to Section")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showJumpMenu = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Collapsible Section

    private func collapsibleSection<Content: View>(_ key: String, title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        Section {
            if expandedSections.contains(key) {
                content()
            }
        } header: {
            Button {
                withAnimation(.snappy(duration: 0.25)) {
                    if expandedSections.contains(key) {
                        expandedSections.remove(key)
                    } else {
                        expandedSections.insert(key)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: icon).foregroundStyle(color).font(.caption)
                    Text(title).font(.caption.bold()).foregroundStyle(color)
                    Spacer()
                    Image(systemName: expandedSections.contains(key) ? "chevron.up" : "chevron.down")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .id(key)
        }
    }

    // MARK: - Section Content

    @ViewBuilder private var trueDetectionContent: some View {
        devToggle("Enabled", $settings.trueDetectionEnabled)
        devToggle("Priority", $settings.trueDetectionPriority)
            .disabled(!settings.trueDetectionEnabled)
            .opacity(settings.trueDetectionEnabled ? 1 : 0.4)
        devToggle("Strict Waits", $settings.trueDetectionStrictWaits)
            .disabled(!settings.trueDetectionEnabled)
            .opacity(settings.trueDetectionEnabled ? 1 : 0.4)
        devToggle("No Proxy Rotation", $settings.trueDetectionNoProxyRotation)
        devToggle("Ignore Placeholders", $settings.trueDetectionIgnorePlaceholders)
        devToggle("Ignore XPaths", $settings.trueDetectionIgnoreXPaths)
        devToggle("Ignore ClassNames", $settings.trueDetectionIgnoreClassNames)
        devInt("Hard Pause (ms)", $settings.trueDetectionHardPauseMs)
        devInt("Triple Click Count", $settings.trueDetectionTripleClickCount)
        devInt("Triple Click Delay (ms)", $settings.trueDetectionTripleClickDelayMs)
        devInt("Submit Cycle Count", $settings.trueDetectionSubmitCycleCount)
        devInt("Button Recovery Timeout (ms)", $settings.trueDetectionButtonRecoveryTimeoutMs)
        devInt("Max Attempts", $settings.trueDetectionMaxAttempts)
        devInt("Post Click Wait (ms)", $settings.trueDetectionPostClickWaitMs)
        devInt("Cooldown (minutes)", $settings.trueDetectionCooldownMinutes)
        devString("Email Selector", $settings.trueDetectionEmailSelector)
        devString("Password Selector", $settings.trueDetectionPasswordSelector)
        devString("Submit Selector", $settings.trueDetectionSubmitSelector)
        devStringArray("Success Markers", $settings.trueDetectionSuccessMarkers)
        devStringArray("Terminal Keywords", $settings.trueDetectionTerminalKeywords)
        devStringArray("Error Banner Selectors", $settings.trueDetectionErrorBannerSelectors)
        if !settings.errorBannerDetection {
            infoNote("Error banner selectors inactive — enable Error Banner Detection in Post-Submit to activate.")
        }
    }

    @ViewBuilder private var pageLoadingContent: some View {
        devDouble("Page Load Timeout (s)", $settings.pageLoadTimeout)
        devInt("Page Load Retries", $settings.pageLoadRetries)
        devDouble("Retry Backoff Multiplier", $settings.retryBackoffMultiplier)
        devInt("Wait For JS Render (ms)", $settings.waitForJSRenderMs)
        devToggle("Full Session Reset On Final Retry", $settings.fullSessionResetOnFinalRetry)
        infoNote("All timeouts have a 180s minimum floor enforced by the engine.")
    }

    @ViewBuilder private var fieldDetectionContent: some View {
        devToggle("Field Verification", $settings.fieldVerificationEnabled)
        devDouble("Field Verification Timeout (s)", $settings.fieldVerificationTimeout)
        devToggle("Auto Calibration", $settings.autoCalibrationEnabled)
        devToggle("Vision ML Calibration Fallback", $settings.visionMLCalibrationFallback)
            .disabled(!settings.autoCalibrationEnabled)
            .opacity(settings.autoCalibrationEnabled ? 1 : 0.4)
        devDouble("Calibration Confidence Threshold", $settings.calibrationConfidenceThreshold)
    }

    @ViewBuilder private var cookieContent: some View {
        devToggle("Dismiss Cookie Notices", $settings.dismissCookieNotices)
        devInt("Cookie Dismiss Delay (ms)", $settings.cookieDismissDelayMs)
            .disabled(!settings.dismissCookieNotices)
            .opacity(settings.dismissCookieNotices ? 1 : 0.4)
    }

    @ViewBuilder private var credentialContent: some View {
        devInt("Typing Speed Min (ms)", $settings.typingSpeedMinMs)
        devInt("Typing Speed Max (ms)", $settings.typingSpeedMaxMs)
        if settings.typingSpeedMinMs > settings.typingSpeedMaxMs {
            validationWarning("Min typing speed exceeds Max — values will be clamped")
        }
        devToggle("Typing Jitter", $settings.typingJitterEnabled)
        devToggle("Occasional Backspace", $settings.occasionalBackspaceEnabled)
        devDouble("Backspace / Typo Probability", $settings.backspaceProbability)
            .disabled(!settings.occasionalBackspaceEnabled)
            .opacity(settings.occasionalBackspaceEnabled ? 1 : 0.4)
        devInt("Field Focus Delay (ms)", $settings.fieldFocusDelayMs)
        devInt("Inter-Field Delay (ms)", $settings.interFieldDelayMs)
        devInt("Pre-Fill Pause Min (ms)", $settings.preFillPauseMinMs)
        devInt("Pre-Fill Pause Max (ms)", $settings.preFillPauseMaxMs)
        if settings.preFillPauseMinMs > settings.preFillPauseMaxMs {
            validationWarning("Min pre-fill pause exceeds Max")
        }
    }

    @ViewBuilder private var patternContent: some View {
        devInt("Max Submit Cycles", $settings.maxSubmitCycles)
        devToggle("Prefer Calibrated Patterns First", $settings.preferCalibratedPatternsFirst)
        devToggle("Pattern Learning", $settings.patternLearningEnabled)
        devStringArray("Enabled Patterns", $settings.enabledPatterns)
        devStringArray("Pattern Priority Order", $settings.patternPriorityOrder)
        infoNote("Pattern priority is respected by all automation engines. First enabled pattern in priority order is used for cycle 1.")
    }

    @ViewBuilder private var fallbackContent: some View {
        devToggle("Fallback to Legacy Fill", $settings.fallbackToLegacyFill)
        devToggle("Fallback to OCR Click", $settings.fallbackToOCRClick)
        devToggle("Fallback to Vision ML Click", $settings.fallbackToVisionMLClick)
        devToggle("Fallback to Coordinate Click", $settings.fallbackToCoordinateClick)
    }

    @ViewBuilder private var submitContent: some View {
        devInt("Submit Retry Count", $settings.submitRetryCount)
        devInt("Submit Retry Delay (ms)", $settings.submitRetryDelayMs)
        devDouble("Wait For Response (s)", $settings.waitForResponseSeconds)
        devToggle("Rapid Poll", $settings.rapidPollEnabled)
        devInt("Rapid Poll Interval (ms)", $settings.rapidPollIntervalMs)
            .disabled(!settings.rapidPollEnabled)
            .opacity(settings.rapidPollEnabled ? 1 : 0.4)
    }

    @ViewBuilder private var postSubmitContent: some View {
        devToggle("Redirect Detection", $settings.redirectDetection)
        devToggle("Error Banner Detection", $settings.errorBannerDetection)
        devToggle("Content Change Detection", $settings.contentChangeDetection)
        Picker("Evaluation Strictness", selection: $settings.evaluationStrictness) {
            ForEach(AutomationSettings.EvaluationStrictness.allCases, id: \.self) { s in
                Text(s.rawValue).tag(s)
            }
        }.font(.subheadline)
        devToggle("Capture Page Content", $settings.capturePageContent)
    }

    @ViewBuilder private var retryContent: some View {
        devToggle("Requeue On Timeout", $settings.requeueOnTimeout)
        devToggle("Requeue On Connection Failure", $settings.requeueOnConnectionFailure)
        devToggle("Requeue On Unsure", $settings.requeueOnUnsure)
        devToggle("Requeue On Red Banner", $settings.requeueOnRedBanner)
        devInt("Max Requeue Count", $settings.maxRequeueCount)
        devInt("Min Attempts Before NoAcc", $settings.minAttemptsBeforeNoAcc)
        devInt("Cycle Pause Min (ms)", $settings.cyclePauseMinMs)
        devInt("Cycle Pause Max (ms)", $settings.cyclePauseMaxMs)
        if settings.cyclePauseMinMs > settings.cyclePauseMaxMs {
            validationWarning("Min cycle pause exceeds Max")
        }
    }

    @ViewBuilder private var stealthContent: some View {
        devToggle("Stealth JS Injection", $settings.stealthJSInjection)
        devToggle("Fingerprint Validation", $settings.fingerprintValidationEnabled)
        devToggle("Host Fingerprint Learning", $settings.hostFingerprintLearningEnabled)
        devToggle("Fingerprint Spoofing", $settings.fingerprintSpoofing)
        devToggle("User Agent Rotation", $settings.userAgentRotation)
        devToggle("Viewport Randomization", $settings.viewportRandomization)
        devToggle("WebGL Noise", $settings.webGLNoise)
        devToggle("Canvas Noise", $settings.canvasNoise)
        devToggle("Audio Context Noise", $settings.audioContextNoise)
        devToggle("Timezone Spoof", $settings.timezoneSpoof)
        devToggle("Language Spoof", $settings.languageSpoof)
    }

    @ViewBuilder private var screenshotContent: some View {
        devToggle("Slow Debug Mode", $settings.slowDebugMode)
        devToggle("Screenshot On Every Eval", $settings.screenshotOnEveryEval)
        devToggle("Screenshot On Failure", $settings.screenshotOnFailure)
        devToggle("Screenshot On Success", $settings.screenshotOnSuccess)
        devInt("Max Screenshot Retention", $settings.maxScreenshotRetention)
        Picker("Screenshots Per Attempt", selection: $settings.screenshotsPerAttempt) {
            ForEach(AutomationSettings.ScreenshotsPerAttempt.allCases, id: \.self) { s in
                Text(s.rawValue).tag(s)
            }
        }.font(.subheadline)
        Picker("Unified Screenshots Per Attempt", selection: $settings.unifiedScreenshotsPerAttempt) {
            ForEach(AutomationSettings.UnifiedScreenshotCount.allCases, id: \.self) { s in
                Text(s.label).tag(s)
            }
        }.font(.subheadline)
        devInt("Unified Screenshot Post Click Delay (ms)", $settings.unifiedScreenshotPostClickDelayMs)
        devString("Post Submit Screenshot Timings", $settings.postSubmitScreenshotTimings)
        devToggle("Post Submit Screenshots Only", $settings.postSubmitScreenshotsOnly)
    }

    @ViewBuilder private var concurrencyContent: some View {
        devInt("Max Concurrency", $settings.maxConcurrency)
        Picker("Concurrency Strategy", selection: $settings.concurrencyStrategy) {
            ForEach(ConcurrencyStrategy.allCases, id: \.self) { s in
                Text(s.rawValue).tag(s)
            }
        }.font(.subheadline)
        devInt("Fixed Pair Count", $settings.fixedPairCount)
            .disabled(settings.concurrencyStrategy != .fixedPairs)
            .opacity(settings.concurrencyStrategy == .fixedPairs ? 1 : 0.4)
        devInt("Live User Pair Count", $settings.liveUserPairCount)
        devInt("Batch Delay Between Starts (ms)", $settings.batchDelayBetweenStartsMs)
        devToggle("Connection Test Before Batch", $settings.connectionTestBeforeBatch)
    }

    @ViewBuilder private var networkContent: some View {
        devToggle("Use Assigned Network For Tests", $settings.useAssignedNetworkForTests)
        devToggle("Proxy Rotate On Disabled", $settings.proxyRotateOnDisabled)
        devToggle("Proxy Rotate On Failure", $settings.proxyRotateOnFailure)
        devToggle("DNS Rotate Per Request", $settings.dnsRotatePerRequest)
        devToggle("VPN Config Rotation", $settings.vpnConfigRotation)
    }

    @ViewBuilder private var urlContent: some View {
        devToggle("URL Rotation Enabled", $settings.urlRotationEnabled)
        devInt("Disable URL After Consecutive Failures", $settings.disableURLAfterConsecutiveFailures)
            .disabled(!settings.urlRotationEnabled)
            .opacity(settings.urlRotationEnabled ? 1 : 0.4)
        devDouble("Re-Enable URL After (s)", $settings.reEnableURLAfterSeconds)
            .disabled(!settings.urlRotationEnabled)
            .opacity(settings.urlRotationEnabled ? 1 : 0.4)
        devToggle("Prefer Fastest URL", $settings.preferFastestURL)
        devToggle("Smart URL Selection", $settings.smartURLSelection)
    }

    @ViewBuilder private var blacklistContent: some View {
        devToggle("Auto Blacklist NoAcc", $settings.autoBlacklistNoAcc)
        devToggle("Auto Blacklist Perm Disabled", $settings.autoBlacklistPermDisabled)
        devToggle("Auto Exclude Blacklist", $settings.autoExcludeBlacklist)
    }

    @ViewBuilder private var humanContent: some View {
        devToggle("Human Mouse Movement", $settings.humanMouseMovement)
        devToggle("Human Scroll Jitter", $settings.humanScrollJitter)
        devToggle("Random Pre-Action Pause", $settings.randomPreActionPause)
        devInt("Pre-Action Pause Min (ms)", $settings.preActionPauseMinMs)
            .disabled(!settings.randomPreActionPause)
            .opacity(settings.randomPreActionPause ? 1 : 0.4)
        devInt("Pre-Action Pause Max (ms)", $settings.preActionPauseMaxMs)
            .disabled(!settings.randomPreActionPause)
            .opacity(settings.randomPreActionPause ? 1 : 0.4)
        if settings.preActionPauseMinMs > settings.preActionPauseMaxMs {
            validationWarning("Min pre-action pause exceeds Max")
        }
        devToggle("Gaussian Timing Distribution", $settings.gaussianTimingDistribution)
    }

    @ViewBuilder private var loginButtonContent: some View {
        unwiredPicker("Detection Mode", selection: $settings.loginButtonDetectionMode) {
            ForEach(AutomationSettings.ButtonDetectionMode.allCases, id: \.self) { m in
                Text(m.rawValue).tag(m)
            }
        }
        unwiredPicker("Click Method", selection: $settings.loginButtonClickMethod) {
            ForEach(AutomationSettings.ButtonClickMethod.allCases, id: \.self) { m in
                Text(m.rawValue).tag(m)
            }
        }
        devStringArray("Button Text Matches", $settings.loginButtonTextMatches)
        devString("Custom Selector", $settings.loginButtonCustomSelector)
        devInt("Pre-Click Delay (ms)", $settings.loginButtonPreClickDelayMs)
        devInt("Post-Click Delay (ms)", $settings.loginButtonPostClickDelayMs)
        devToggle("Double Click Guard", $settings.loginButtonDoubleClickGuard)
        devInt("Double Click Window (ms)", $settings.loginButtonDoubleClickWindowMs)
            .disabled(!settings.loginButtonDoubleClickGuard)
            .opacity(settings.loginButtonDoubleClickGuard ? 1 : 0.4)
        devToggle("Scroll Into View", $settings.loginButtonScrollIntoView)
        devToggle("Wait For Enabled", $settings.loginButtonWaitForEnabled)
        devInt("Wait For Enabled Timeout (ms)", $settings.loginButtonWaitForEnabledTimeoutMs)
            .disabled(!settings.loginButtonWaitForEnabled)
            .opacity(settings.loginButtonWaitForEnabled ? 1 : 0.4)
        devInt("Page Load Extra Delay (ms)", $settings.pageLoadExtraDelayMs)
        devInt("Submit Button Wait Delay (ms)", $settings.submitButtonWaitDelayMs)
        devToggle("Visibility Check", $settings.loginButtonVisibilityCheck)
        devToggle("Focus Before Click", $settings.loginButtonFocusBeforeClick)
        devToggle("Hover Before Click", $settings.loginButtonHoverBeforeClick)
        devInt("Hover Duration (ms)", $settings.loginButtonHoverDurationMs)
            .disabled(!settings.loginButtonHoverBeforeClick)
            .opacity(settings.loginButtonHoverBeforeClick ? 1 : 0.4)
        devToggle("Click Offset Jitter", $settings.loginButtonClickOffsetJitter)
        devInt("Click Offset Max (px)", $settings.loginButtonClickOffsetMaxPx)
            .disabled(!settings.loginButtonClickOffsetJitter)
            .opacity(settings.loginButtonClickOffsetJitter ? 1 : 0.4)
        devInt("Min Button Size (px)", $settings.loginButtonMinSizePx)
        devInt("Max Candidates", $settings.loginButtonMaxCandidates)
        devDouble("Confidence Threshold", $settings.loginButtonConfidenceThreshold)
    }

    @ViewBuilder private var timeDelayContent: some View {
        devInt("Global Pre-Action (ms)", $settings.globalPreActionDelayMs)
        devInt("Global Post-Action (ms)", $settings.globalPostActionDelayMs)
        devInt("Pre-Navigation (ms)", $settings.preNavigationDelayMs)
        devInt("Post-Navigation (ms)", $settings.postNavigationDelayMs)
        devInt("Pre-Typing (ms)", $settings.preTypingDelayMs)
        devInt("Post-Typing (ms)", $settings.postTypingDelayMs)
        devInt("Pre-Submit (ms)", $settings.preSubmitDelayMs)
        devInt("Post-Submit (ms)", $settings.postSubmitDelayMs)
        devInt("Between Attempts (ms)", $settings.betweenAttemptsDelayMs)
        devInt("Between Credentials (ms)", $settings.betweenCredentialsDelayMs)
        devInt("Page Stabilization (ms)", $settings.pageStabilizationDelayMs)
        devInt("AJAX Settle (ms)", $settings.ajaxSettleDelayMs)
        devInt("DOM Mutation Settle (ms)", $settings.domMutationSettleMs)
        devInt("Animation Settle (ms)", $settings.animationSettleDelayMs)
        devInt("Redirect Follow (ms)", $settings.redirectFollowDelayMs)
        devInt("CAPTCHA Detection (ms)", $settings.captchaDetectionDelayMs)
        devInt("Error Recovery (ms)", $settings.errorRecoveryDelayMs)
        devInt("Session Cooldown (ms)", $settings.sessionCooldownDelayMs)
        devInt("Proxy Rotation (ms)", $settings.proxyRotationDelayMs)
        devInt("VPN Reconnect (ms)", $settings.vpnReconnectDelayMs)
        devToggle("Auto Fallback WG \u{2192} OVPN", $settings.autoFallbackWGtoOVPN)
        devToggle("Auto Fallback OVPN \u{2192} SOCKS5", $settings.autoFallbackOVPNtoSOCKS5)
        devToggle("Delay Randomization", $settings.delayRandomizationEnabled)
        devInt("Delay Randomization %", $settings.delayRandomizationPercent)
            .disabled(!settings.delayRandomizationEnabled)
            .opacity(settings.delayRandomizationEnabled ? 1 : 0.4)
    }

    @ViewBuilder private var mfaContent: some View {
        devToggle("MFA Detection", $settings.mfaDetectionEnabled)
        devInt("MFA Wait Timeout (s)", $settings.mfaWaitTimeoutSeconds)
            .disabled(!settings.mfaDetectionEnabled)
            .opacity(settings.mfaDetectionEnabled ? 1 : 0.4)
        devToggle("MFA Auto Skip", $settings.mfaAutoSkip)
            .disabled(!settings.mfaDetectionEnabled)
            .opacity(settings.mfaDetectionEnabled ? 1 : 0.4)
        devToggle("MFA Mark As Temp Disabled", $settings.mfaMarkAsTempDisabled)
            .disabled(!settings.mfaDetectionEnabled)
            .opacity(settings.mfaDetectionEnabled ? 1 : 0.4)
        devStringArray("MFA Keywords", $settings.mfaKeywords)
        infoNote("SMS detection runs independently of MFA detection.")
        devToggle("SMS Detection", $settings.smsDetectionEnabled)
        devToggle("SMS Burn Session", $settings.smsBurnSession)
            .disabled(!settings.smsDetectionEnabled)
            .opacity(settings.smsDetectionEnabled ? 1 : 0.4)
        devStringArray("SMS Notification Keywords", $settings.smsNotificationKeywords)
    }

    @ViewBuilder private var captchaContent: some View {
        devToggle("CAPTCHA Detection", $settings.captchaDetectionEnabled)
        devToggle("CAPTCHA Auto Skip", $settings.captchaAutoSkip)
            .disabled(!settings.captchaDetectionEnabled)
            .opacity(settings.captchaDetectionEnabled ? 1 : 0.4)
        devToggle("CAPTCHA Mark As Failed", $settings.captchaMarkAsFailed)
            .disabled(!settings.captchaDetectionEnabled)
            .opacity(settings.captchaDetectionEnabled ? 1 : 0.4)
        devInt("CAPTCHA Wait Timeout (s)", $settings.captchaWaitTimeoutSeconds)
            .disabled(!settings.captchaDetectionEnabled)
            .opacity(settings.captchaDetectionEnabled ? 1 : 0.4)
        devStringArray("CAPTCHA Keywords", $settings.captchaKeywords)
        devToggle("CAPTCHA iFrame Detection", $settings.captchaIframeDetection)
            .disabled(!settings.captchaDetectionEnabled)
            .opacity(settings.captchaDetectionEnabled ? 1 : 0.4)
        devToggle("CAPTCHA Image Detection", $settings.captchaImageDetection)
            .disabled(!settings.captchaDetectionEnabled)
            .opacity(settings.captchaDetectionEnabled ? 1 : 0.4)
    }

    @ViewBuilder private var sessionContent: some View {
        Picker("Session Isolation", selection: $settings.sessionIsolation) {
            ForEach(AutomationSettings.SessionIsolationMode.allCases, id: \.self) { m in
                Text(m.rawValue).tag(m)
            }
        }.font(.subheadline)
        devToggle("Clear Cookies Between Attempts", $settings.clearCookiesBetweenAttempts)
        devToggle("Clear LocalStorage Between Attempts", $settings.clearLocalStorageBetweenAttempts)
        devToggle("Clear SessionStorage Between Attempts", $settings.clearSessionStorageBetweenAttempts)
        devToggle("Clear Cache Between Attempts", $settings.clearCacheBetweenAttempts)
        devToggle("Clear IndexedDB Between Attempts", $settings.clearIndexedDBBetweenAttempts)
        devToggle("Fresh WebView Per Attempt", $settings.freshWebViewPerAttempt)
        devInt("WebView Memory Limit (MB)", $settings.webViewMemoryLimitMB)
        devToggle("WebView JS Enabled", $settings.webViewJSEnabled)
        devToggle("WebView Image Loading", $settings.webViewImageLoadingEnabled)
        devToggle("WebView Plugins Enabled", $settings.webViewPluginsEnabled)
    }

    @ViewBuilder private var blankPageContent: some View {
        devToggle("Blank Page Recovery", $settings.blankPageRecoveryEnabled)
        devInt("Blank Page Timeout (s)", $settings.blankPageTimeoutSeconds)
            .disabled(!settings.blankPageRecoveryEnabled)
            .opacity(settings.blankPageRecoveryEnabled ? 1 : 0.4)
        devInt("Blank Page Wait Threshold (s)", $settings.blankPageWaitThresholdSeconds)
            .disabled(!settings.blankPageRecoveryEnabled)
            .opacity(settings.blankPageRecoveryEnabled ? 1 : 0.4)
        devToggle("Fallback 1: Wait & Recheck", $settings.blankPageFallback1_WaitAndRecheck)
            .disabled(!settings.blankPageRecoveryEnabled)
            .opacity(settings.blankPageRecoveryEnabled ? 1 : 0.4)
        devToggle("Fallback 2: Change URL", $settings.blankPageFallback2_ChangeURL)
            .disabled(!settings.blankPageRecoveryEnabled)
            .opacity(settings.blankPageRecoveryEnabled ? 1 : 0.4)
        devToggle("Fallback 3: Change DNS", $settings.blankPageFallback3_ChangeDNS)
            .disabled(!settings.blankPageRecoveryEnabled)
            .opacity(settings.blankPageRecoveryEnabled ? 1 : 0.4)
        devToggle("Fallback 4: Change Fingerprint", $settings.blankPageFallback4_ChangeFingerprint)
            .disabled(!settings.blankPageRecoveryEnabled)
            .opacity(settings.blankPageRecoveryEnabled ? 1 : 0.4)
        devToggle("Fallback 5: Full Session Reset", $settings.blankPageFallback5_FullSessionReset)
            .disabled(!settings.blankPageRecoveryEnabled)
            .opacity(settings.blankPageRecoveryEnabled ? 1 : 0.4)
        devInt("Max Fallback Attempts", $settings.blankPageMaxFallbackAttempts)
            .disabled(!settings.blankPageRecoveryEnabled)
            .opacity(settings.blankPageRecoveryEnabled ? 1 : 0.4)
        devInt("Recheck Interval (ms)", $settings.blankPageRecheckIntervalMs)
            .disabled(!settings.blankPageRecoveryEnabled)
            .opacity(settings.blankPageRecoveryEnabled ? 1 : 0.4)
    }

    @ViewBuilder private var errorClassContent: some View {
        devToggle("Network Error Auto Retry", $settings.networkErrorAutoRetry)
        devToggle("SSL Error Auto Retry", $settings.sslErrorAutoRetry)
        devToggle("HTTP 403 Mark As Blocked", $settings.http403MarkAsBlocked)
        devInt("HTTP 429 Retry After (s)", $settings.http429RetryAfterSeconds)
        devToggle("HTTP 5xx Auto Retry", $settings.http5xxAutoRetry)
        devToggle("Connection Reset Auto Retry", $settings.connectionResetAutoRetry)
        devToggle("DNS Failure Auto Retry", $settings.dnsFailureAutoRetry)
        devToggle("Classify Unknown As Unsure", $settings.classifyUnknownAsUnsure)
    }

    @ViewBuilder private var formContent: some View {
        devToggle("Clear Fields Before Typing", $settings.clearFieldsBeforeTyping)
        Picker("Clear Field Method", selection: $settings.clearFieldMethod) {
            ForEach(AutomationSettings.FieldClearMethod.allCases, id: \.self) { m in
                Text(m.rawValue).tag(m)
            }
        }.font(.subheadline)
            .disabled(!settings.clearFieldsBeforeTyping)
            .opacity(settings.clearFieldsBeforeTyping ? 1 : 0.4)
        devToggle("Tab Between Fields", $settings.tabBetweenFields)
        unwiredToggle("Click Field Before Typing", $settings.clickFieldBeforeTyping)
        devToggle("Verify Field Value After Typing", $settings.verifyFieldValueAfterTyping)
        devToggle("Retype On Verification Failure", $settings.retypeOnVerificationFailure)
            .disabled(!settings.verifyFieldValueAfterTyping)
            .opacity(settings.verifyFieldValueAfterTyping ? 1 : 0.4)
        devInt("Max Retype Attempts", $settings.maxRetypeAttempts)
            .disabled(!settings.verifyFieldValueAfterTyping || !settings.retypeOnVerificationFailure)
            .opacity(settings.verifyFieldValueAfterTyping && settings.retypeOnVerificationFailure ? 1 : 0.4)
        devToggle("Password Field Unmask Check", $settings.passwordFieldUnmaskCheck)
        devToggle("Auto Detect Remember Me", $settings.autoDetectRememberMe)
        devToggle("Uncheck Remember Me", $settings.uncheckRememberMe)
            .disabled(!settings.autoDetectRememberMe)
            .opacity(settings.autoDetectRememberMe ? 1 : 0.4)
        devToggle("Dismiss Autofill Suggestions", $settings.dismissAutofillSuggestions)
        devToggle("Handle Password Managers", $settings.handlePasswordManagers)
    }

    @ViewBuilder private var viewportContent: some View {
        devInt("Viewport Width", $settings.viewportWidth)
        devInt("Viewport Height", $settings.viewportHeight)
        devToggle("Smart Fingerprint Reuse", $settings.smartFingerprintReuse)
        devInt("Viewport Size Variance (px)", $settings.viewportSizeVariancePx)
        devToggle("Mobile Viewport Emulation", $settings.mobileViewportEmulation)
        devDouble("Device Scale Factor", $settings.deviceScaleFactor)
    }

    @ViewBuilder private var settlementContent: some View {
        devToggle("Settlement Gate Enabled", $settings.v42SettlementGateEnabled)
        devInt("Settlement Max Timeout (ms)", $settings.v42SettlementMaxTimeoutMs)
            .disabled(!settings.v42SettlementGateEnabled)
            .opacity(settings.v42SettlementGateEnabled ? 1 : 0.4)
        devInt("Button Stability (ms)", $settings.v42ButtonStabilityMs)
        devInt("Hover Dwell (ms)", $settings.v42HoverDwellMs)
        devInt("Click Jitter (px)", $settings.v42ClickJitterPx)
        devDouble("Inter-Attempt Delay Min (s)", $settings.v42InterAttemptDelayMinSec)
        devDouble("Inter-Attempt Delay Max (s)", $settings.v42InterAttemptDelayMaxSec)
        if settings.v42InterAttemptDelayMinSec > settings.v42InterAttemptDelayMaxSec {
            validationWarning("Min inter-attempt delay exceeds Max")
        }
        devInt("Human Variance Min (ms)", $settings.v42HumanVarianceMinMs)
        devInt("Human Variance Max (ms)", $settings.v42HumanVarianceMaxMs)
        if settings.v42HumanVarianceMinMs > settings.v42HumanVarianceMaxMs {
            validationWarning("Min human variance exceeds Max")
        }
        devToggle("Strict Classification", $settings.v42StrictClassification)
        devToggle("Coordinate Interaction Only", $settings.v42CoordinateInteractionOnly)
    }

    @ViewBuilder private var aiContent: some View {
        devToggle("AI Telemetry", $settings.aiTelemetryEnabled)
    }

    // MARK: - Reusable Controls

    private func validationWarning(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.caption2)
            Text(message).font(.caption2).foregroundStyle(.red)
        }
    }

    private func infoNote(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle").foregroundStyle(.blue).font(.caption2)
            Text(text).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func devToggle(_ label: String, _ binding: Binding<Bool>) -> some View {
        Toggle(label, isOn: binding).font(.subheadline).tint(.blue)
    }

    private func unwiredToggle(_ label: String, _ binding: Binding<Bool>) -> some View {
        HStack {
            Toggle(label, isOn: binding).font(.subheadline).tint(.blue)
            Image(systemName: "wrench.trianglebadge.exclamationmark")
                .font(.caption2).foregroundStyle(.orange)
        }
    }

    private func unwiredPicker<SelectionValue: Hashable, Content: View>(_ label: String, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Picker(label, selection: selection, content: content).font(.subheadline)
            Image(systemName: "wrench.trianglebadge.exclamationmark")
                .font(.caption2).foregroundStyle(.orange)
        }
    }

    private func devInt(_ label: String, _ binding: Binding<Int>) -> some View {
        HStack {
            Text(label).font(.subheadline).lineLimit(1).minimumScaleFactor(0.7)
            Spacer()
            TextField("", value: binding, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.blue)
        }
    }

    private func devDouble(_ label: String, _ binding: Binding<Double>) -> some View {
        HStack {
            Text(label).font(.subheadline).lineLimit(1).minimumScaleFactor(0.7)
            Spacer()
            TextField("", value: binding, format: .number.precision(.fractionLength(0...3)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.blue)
        }
    }

    private func devString(_ label: String, _ binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline)
            TextField(label, text: binding)
                .font(.system(.caption, design: .monospaced))
                .textFieldStyle(.roundedBorder)
        }
    }

    private func devStringArray(_ label: String, _ binding: Binding<[String]>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline)
            Text(binding.wrappedValue.joined(separator: ", "))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(3)
            TextField("Edit (comma-separated)", text: Binding(
                get: { binding.wrappedValue.joined(separator: ", ") },
                set: { newVal in
                    binding.wrappedValue = newVal
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                }
            ))
            .font(.system(.caption, design: .monospaced))
            .textFieldStyle(.roundedBorder)
        }
    }
}
