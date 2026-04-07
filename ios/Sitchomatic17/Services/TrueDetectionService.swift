import Foundation
import WebKit
import UIKit

@MainActor
class TrueDetectionService {
    static let shared = TrueDetectionService()

    private let logger = DebugLogger.shared

    struct TrueDetectionResult {
        var emailFilled: Bool = false
        var passwordFilled: Bool = false
        var submitTriggered: Bool = false
        var submitMethod: String = ""
        var terminalError: TerminalError?
        var attemptNumber: Int = 0
        var successValidated: Bool = false

        var overallSuccess: Bool {
            emailFilled && passwordFilled && submitTriggered
        }

        var summary: String {
            "TrueDetection[attempt:\(attemptNumber)] email:\(emailFilled) pass:\(passwordFilled) submit:\(submitTriggered) method:\(submitMethod) terminal:\(terminalError?.rawValue ?? "none")"
        }
    }

    nonisolated enum TerminalError: String, Sendable {
        case temporarilyDisabled = "temporarily_disabled"
        case accountDisabled = "account_disabled"
        case errorBanner = "error_banner"
        case smsVerification = "sms_verification"
    }

    nonisolated struct TrueDetectionConfig: Sendable {
        var hardPauseMs: Int = 4000
        var tripleClickDelayMs: Int = 1100
        var tripleClickCount: Int = 4
        var submitCycleCount: Int = 4
        var buttonRecoveryTimeoutMs: Int = 12000
        var maxAttempts: Int = 4
        var postClickWaitMs: Int = 2500
        var cooldownMinutes: Int = 15
        var emailSelector: String = "#email"
        var passwordSelector: String = "#login-password"
        var submitSelector: String = "#login-submit"
        var successMarkers: [String] = ["recommended for you", "last played"]
        var terminalKeywords: [String] = [
            "temporarily disabled",
            "has been disabled"
        ]
        var errorBannerSelectors: [String] = [".error-banner", ".alert-danger", ".alert-error", ".login-error", ".notification-error", "[role='alert']"]
    }

    private var cooldownAccounts: [String: Date] = [:]

    func isOnCooldown(account: String) -> Bool {
        guard let cooldownUntil = cooldownAccounts[account] else { return false }
        return Date() < cooldownUntil
    }

    func setCooldown(account: String, minutes: Int) {
        cooldownAccounts[account] = Date().addingTimeInterval(TimeInterval(minutes * 60))
    }

    func clearCooldown(account: String) {
        cooldownAccounts.removeValue(forKey: account)
    }

    func runFullTrueDetectionSequence(
        session: LoginSiteWebSession,
        username: String,
        password: String,
        config: TrueDetectionConfig = TrueDetectionConfig(),
        sessionId: String = "",
        onLog: ((String, PPSRLogEntry.Level) -> Void)? = nil
    ) async -> TrueDetectionResult {
        var finalResult = TrueDetectionResult()

        if isOnCooldown(account: username) {
            onLog?("TRUE DETECTION: Account '\(username)' is on cooldown — skipping", .warning)
            logger.log("TrueDetection: account on cooldown, skipping", category: .automation, level: .warning, sessionId: sessionId)
            finalResult.terminalError = .temporarilyDisabled
            return finalResult
        }

        for attempt in 1...config.maxAttempts {
            finalResult.attemptNumber = attempt
            onLog?("TRUE DETECTION: Attempt \(attempt)/\(config.maxAttempts)", .info)
            logger.log("TrueDetection: attempt \(attempt)/\(config.maxAttempts)", category: .automation, level: .info, sessionId: sessionId)

            let stepResult = await executeTrueDetectionStep(
                session: session,
                username: username,
                password: password,
                config: config,
                attempt: attempt,
                sessionId: sessionId,
                onLog: onLog
            )

            finalResult.emailFilled = stepResult.emailFilled
            finalResult.passwordFilled = stepResult.passwordFilled
            finalResult.submitTriggered = stepResult.submitTriggered
            finalResult.submitMethod = stepResult.submitMethod

            if let terminal = stepResult.terminalError {
                finalResult.terminalError = terminal
                onLog?("TRUE DETECTION: TERMINAL ERROR — \(terminal.rawValue) on attempt \(attempt)", .error)
                logger.log("TrueDetection: TERMINAL \(terminal.rawValue)", category: .automation, level: .critical, sessionId: sessionId)
                setCooldown(account: username, minutes: config.cooldownMinutes)
                return finalResult
            }

            if stepResult.submitTriggered {
                try? await Task.sleep(for: .milliseconds(config.postClickWaitMs))

                let validated = await validateSuccess(session: session, config: config, sessionId: sessionId, onLog: onLog)
                finalResult.successValidated = validated
                if validated {
                    onLog?("TRUE DETECTION: SUCCESS VALIDATED on attempt \(attempt)", .success)
                    logger.log("TrueDetection: SUCCESS on attempt \(attempt)", category: .automation, level: .success, sessionId: sessionId)
                    return finalResult
                }

                let terminalCheck = await checkTerminalErrors(session: session, config: config, sessionId: sessionId, onLog: onLog)
                if let terminal = terminalCheck {
                    finalResult.terminalError = terminal
                    setCooldown(account: username, minutes: config.cooldownMinutes)
                    return finalResult
                }

                onLog?("TRUE DETECTION: Attempt \(attempt) — submit triggered but no success markers found", .warning)
            }

            if attempt < config.maxAttempts {
                let backoff = 2000 * attempt
                onLog?("TRUE DETECTION: Waiting \(backoff)ms before retry...", .info)
                try? await Task.sleep(for: .milliseconds(backoff))
            }
        }

        onLog?("TRUE DETECTION: All \(config.maxAttempts) attempts exhausted", .error)
        return finalResult
    }

    private func executeTrueDetectionStep(
        session: LoginSiteWebSession,
        username: String,
        password: String,
        config: TrueDetectionConfig,
        attempt: Int,
        sessionId: String,
        onLog: ((String, PPSRLogEntry.Level) -> Void)?
    ) async -> TrueDetectionResult {
        var result = TrueDetectionResult()
        result.attemptNumber = attempt

        let domReadyTimeout = TimeoutResolver.resolveAutomationTimeout(10)
        let domReady = await waitForDOMComplete(session: session, timeout: domReadyTimeout, sessionId: sessionId)
        if !domReady {
            onLog?("TRUE DETECTION: DOM not ready after \(Int(domReadyTimeout))s", .warning)
        }

        onLog?("TRUE DETECTION: Hard pause \(config.hardPauseMs)ms before interaction...", .info)
        logger.log("TrueDetection: hard pause \(config.hardPauseMs)ms", category: .automation, level: .trace, sessionId: sessionId)
        try? await Task.sleep(for: .milliseconds(config.hardPauseMs))

        let emailResult = await fillHardcodedField(
            session: session,
            selector: config.emailSelector,
            value: username,
            fieldName: "email",
            sessionId: sessionId,
            onLog: onLog
        )
        result.emailFilled = emailResult
        if !emailResult {
            onLog?("TRUE DETECTION: Email fill FAILED on \(config.emailSelector)", .error)
            return result
        }
        onLog?("TRUE DETECTION: Email filled via \(config.emailSelector)", .success)
        try? await Task.sleep(for: .milliseconds(Int.random(in: 300...600)))

        let passwordResult = await fillHardcodedField(
            session: session,
            selector: config.passwordSelector,
            value: password,
            fieldName: "password",
            sessionId: sessionId,
            onLog: onLog
        )
        result.passwordFilled = passwordResult
        if !passwordResult {
            onLog?("TRUE DETECTION: Password fill FAILED on \(config.passwordSelector)", .error)
            return result
        }
        onLog?("TRUE DETECTION: Password filled via \(config.passwordSelector)", .success)
        try? await Task.sleep(for: .milliseconds(Int.random(in: 300...600)))

        let submitResult = await cycledTripleClickWithButtonDetection(
            session: session,
            selector: config.submitSelector,
            clickCount: config.tripleClickCount,
            delayMs: config.tripleClickDelayMs,
            cycleCount: config.submitCycleCount,
            buttonRecoveryTimeoutMs: config.buttonRecoveryTimeoutMs,
            sessionId: sessionId,
            onLog: onLog
        )
        result.submitTriggered = submitResult.success
        result.submitMethod = submitResult.method

        return result
    }

    private func waitForDOMComplete(session: LoginSiteWebSession, timeout: TimeInterval, sessionId: String) async -> Bool {
        let timeout = TimeoutResolver.resolveAutomationTimeout(timeout)
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            let ready = await session.executeJS("document.readyState")
            if ready == "complete" {
                return true
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
        return false
    }

    private func fillHardcodedField(
        session: LoginSiteWebSession,
        selector: String,
        value: String,
        fieldName: String,
        sessionId: String,
        onLog: ((String, PPSRLogEntry.Level) -> Void)?
    ) async -> Bool {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let escapedSelector = selector
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")

        let humanTapJS = """
        (function() {
            var el = document.querySelector('\(escapedSelector)');
            if (!el) return 'NOT_FOUND';
            el.scrollIntoView({behavior: 'instant', block: 'center'});
            var rect = el.getBoundingClientRect();
            var cx = rect.left + rect.width / 2 + (Math.random() * 8 - 4);
            var cy = rect.top + rect.height / 2 + (Math.random() * 8 - 4);
            el.dispatchEvent(new PointerEvent('pointerdown', {bubbles:true,cancelable:true,view:window,clientX:cx,clientY:cy,pointerId:1,pointerType:'touch',button:0,buttons:1}));
            el.dispatchEvent(new TouchEvent('touchstart', {bubbles:true,cancelable:true,view:window}));
            el.dispatchEvent(new PointerEvent('pointerup', {bubbles:true,cancelable:true,view:window,clientX:cx,clientY:cy,pointerId:1,pointerType:'touch',button:0}));
            el.dispatchEvent(new TouchEvent('touchend', {bubbles:true,cancelable:true,view:window}));
            el.dispatchEvent(new MouseEvent('click', {bubbles:true,cancelable:true,view:window,clientX:cx,clientY:cy,button:0}));
            return 'TAPPED';
        })();
        """
        let tapResult = await session.executeJS(humanTapJS)
        logger.log("TrueDetection: human tap on \(fieldName) via \(selector) \u{2192} \(tapResult ?? "nil")", category: .automation, level: .trace, sessionId: sessionId)
        try? await Task.sleep(for: .milliseconds(Int.random(in: 80...220)))

        let js = """
        (function() {
            var el = document.querySelector('\(escapedSelector)');
            if (!el) return 'NOT_FOUND';
            el.focus();
            el.dispatchEvent(new Event('focus', {bubbles: true}));
            var nativeSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value');
            if (nativeSetter && nativeSetter.set) {
                nativeSetter.set.call(el, '');
            } else {
                el.value = '';
            }
            el.dispatchEvent(new Event('input', {bubbles: true}));
            if (nativeSetter && nativeSetter.set) {
                nativeSetter.set.call(el, '\(escaped)');
            } else {
                el.value = '\(escaped)';
            }
            el.dispatchEvent(new Event('input', {bubbles: true}));
            el.dispatchEvent(new Event('change', {bubbles: true}));
            el.dispatchEvent(new Event('blur', {bubbles: true}));
            return el.value === '\(escaped)' ? 'OK' : 'VALUE_MISMATCH';
        })();
        """

        let result = await session.executeJS(js)
        logger.log("TrueDetection: fill \(fieldName) via \(selector) \u{2192} \(result ?? "nil")", category: .automation, level: result == "OK" ? .success : .warning, sessionId: sessionId)

        if result == "OK" || result == "VALUE_MISMATCH" {
            return true
        }
        return false
    }

    // MARK: - 4-Cycle Submit: Triple Click → Smart Button Color Detection → Triple Click → Detection → Triple Click → Detection → Triple Click

    private func cycledTripleClickWithButtonDetection(
        session: LoginSiteWebSession,
        selector: String,
        clickCount: Int,
        delayMs: Int,
        cycleCount: Int,
        buttonRecoveryTimeoutMs: Int,
        sessionId: String,
        onLog: ((String, PPSRLogEntry.Level) -> Void)?
    ) async -> (success: Bool, method: String) {
        let escapedSelector = selector
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")

        let checkJS = """
        (function() {
            var btn = document.querySelector('\(escapedSelector)');
            if (!btn) return 'NOT_FOUND';
            return 'FOUND:' + (btn.textContent || '').trim().substring(0, 30);
        })();
        """
        let checkResult = await session.executeJS(checkJS)
        guard let checkResult, checkResult.hasPrefix("FOUND") else {
            onLog?("TRUE DETECTION: Submit button NOT_FOUND at \(selector)", .error)
            logger.log("TrueDetection: submit button NOT_FOUND at \(selector)", category: .automation, level: .error, sessionId: sessionId)
            return (false, "NOT_FOUND")
        }

        let effectiveCycles = max(1, cycleCount)
        onLog?("TRUE DETECTION: Starting \(effectiveCycles)-cycle submit (triple-click \u{2192} button color detection \u{2192} triple-click \u{2192} ...) on \(selector)", .info)
        logger.log("TrueDetection: \(effectiveCycles)-cycle submit sequence starting (\(clickCount) clicks/cycle, \(delayMs)ms apart)", category: .automation, level: .info, sessionId: sessionId)

        let buttonRecovery = SmartButtonRecoveryService.shared
        let currentURL = await session.getCurrentURL()
        let host = URL(string: currentURL)?.host ?? "unknown"

        for cycle in 0..<effectiveCycles {
            onLog?("TRUE DETECTION: Cycle \(cycle + 1)/\(effectiveCycles) — triple-click submit", .info)
            logger.log("TrueDetection: cycle \(cycle + 1)/\(effectiveCycles) triple-click", category: .automation, level: .info, sessionId: sessionId)

            let preClickFingerprint = await buttonRecovery.captureFingerprint(
                executeJS: { js in await session.executeJS(js) },
                sessionId: sessionId
            )

            for i in 0..<clickCount {
                let clickJS = """
                (function() {
                    var btn = document.querySelector('\(escapedSelector)');
                    if (!btn) return 'NOT_FOUND';
                    btn.scrollIntoView({behavior: 'instant', block: 'center'});
                    var rect = btn.getBoundingClientRect();
                    var cx = rect.left + rect.width * (0.3 + Math.random() * 0.4);
                    var cy = rect.top + rect.height * (0.3 + Math.random() * 0.4);

                    btn.dispatchEvent(new PointerEvent('pointerdown', {
                        bubbles: true, cancelable: true, view: window,
                        clientX: cx, clientY: cy, pointerId: 1, pointerType: 'mouse',
                        button: 0, buttons: 1
                    }));
                    btn.dispatchEvent(new MouseEvent('mousedown', {
                        bubbles: true, cancelable: true, view: window,
                        clientX: cx, clientY: cy, button: 0, buttons: 1
                    }));
                    btn.dispatchEvent(new PointerEvent('pointerup', {
                        bubbles: true, cancelable: true, view: window,
                        clientX: cx, clientY: cy, pointerId: 1, pointerType: 'mouse', button: 0
                    }));
                    btn.dispatchEvent(new MouseEvent('mouseup', {
                        bubbles: true, cancelable: true, view: window,
                        clientX: cx, clientY: cy, button: 0
                    }));
                    btn.dispatchEvent(new MouseEvent('click', {
                        bubbles: true, cancelable: true, view: window,
                        clientX: cx, clientY: cy, button: 0
                    }));
                    btn.click();
                    return 'CLICKED_' + \(i);
                })();
                """
                let clickResult = await session.executeJS(clickJS)
                onLog?("TRUE DETECTION: Cycle \(cycle + 1) Click \(i + 1)/\(clickCount) \u{2192} \(clickResult ?? "nil")", .info)
                logger.log("TrueDetection: cycle \(cycle + 1) click \(i + 1)/\(clickCount) \u{2192} \(clickResult ?? "nil")", category: .automation, level: .trace, sessionId: sessionId)

                if i < clickCount - 1 {
                    try? await Task.sleep(for: .milliseconds(delayMs))
                }
            }

            if cycle < effectiveCycles - 1 {
                onLog?("TRUE DETECTION: Cycle \(cycle + 1) complete — AI smart button color change detection...", .info)
                logger.log("TrueDetection: cycle \(cycle + 1) done, waiting for smart button color change detection", category: .automation, level: .info, sessionId: sessionId)

                if let fingerprint = preClickFingerprint {
                    let recovery = await buttonRecovery.waitForRecovery(
                        originalFingerprint: fingerprint,
                        executeJS: { js in await session.executeJS(js) },
                        host: host,
                        sessionId: sessionId,
                        maxTimeoutMs: buttonRecoveryTimeoutMs
                    )
                    onLog?("TRUE DETECTION: Button detection — recovered=\(recovery.recovered) duration=\(recovery.durationMs)ms reason=\(recovery.reason)", recovery.recovered ? .success : .warning)
                    logger.log("TrueDetection: button recovery \(recovery.recovered ? "OK" : "TIMEOUT") in \(recovery.durationMs)ms — \(recovery.reason)", category: .automation, level: recovery.recovered ? .success : .warning, sessionId: sessionId)
                } else {
                    onLog?("TRUE DETECTION: No button fingerprint captured — fixed delay fallback", .warning)
                    try? await Task.sleep(for: .milliseconds(2000))
                }

                try? await Task.sleep(for: .milliseconds(Int.random(in: 200...500)))
            }
        }

        onLog?("TRUE DETECTION: All \(effectiveCycles) submit cycles complete", .success)
        logger.log("TrueDetection: all \(effectiveCycles) submit cycles complete", category: .automation, level: .success, sessionId: sessionId)
        return (true, "CYCLED_TRIPLE_CLICK_\(effectiveCycles)x\(clickCount)_\(selector)")
    }

    func validateSuccess(
        session: LoginSiteWebSession,
        config: TrueDetectionConfig,
        sessionId: String,
        onLog: ((String, PPSRLogEntry.Level) -> Void)?
    ) async -> Bool {
        let pageContent = await session.getPageContent() ?? ""
        let contentLower = pageContent.lowercased()

        for marker in config.successMarkers {
            if contentLower.contains(marker.lowercased()) {
                onLog?("TRUE DETECTION: Success marker found — '\(marker)'", .success)
                logger.log("TrueDetection: success marker '\(marker)' found", category: .evaluation, level: .success, sessionId: sessionId)
                return true
            }
        }

        onLog?("TRUE DETECTION: No success markers found in page content", .warning)
        return false
    }

    private func checkTerminalErrors(
        session: LoginSiteWebSession,
        config: TrueDetectionConfig,
        sessionId: String,
        onLog: ((String, PPSRLogEntry.Level) -> Void)?
    ) async -> TerminalError? {
        let pageContent = await session.getPageContent() ?? ""
        let contentLower = pageContent.lowercased()

        if contentLower.contains("temporarily disabled") {
            onLog?("TRUE DETECTION: TERMINAL keyword detected — 'temporarily disabled'", .error)
            logger.log("TrueDetection: TERMINAL keyword 'temporarily disabled'", category: .evaluation, level: .critical, sessionId: sessionId)
            return .temporarilyDisabled
        }
        if contentLower.contains("has been disabled") {
            onLog?("TRUE DETECTION: TERMINAL keyword detected — 'has been disabled'", .error)
            logger.log("TrueDetection: TERMINAL keyword 'has been disabled'", category: .evaluation, level: .critical, sessionId: sessionId)
            return .accountDisabled
        }

        let isIgnitionSite = (await session.getCurrentURL()).lowercased().contains("ignition")
        if isIgnitionSite {
            let smsKeywords = [
                "sms", "text message", "verification code", "verify your phone",
                "send code", "sent a code", "enter the code", "phone verification",
                "mobile verification", "confirm your number", "we sent", "code sent",
                "enter code", "security code sent", "check your phone"
            ]
            for keyword in smsKeywords {
                if contentLower.contains(keyword.lowercased()) {
                    onLog?("TRUE DETECTION: SMS NOTIFICATION detected (Ignition) — '\(keyword)' — burn session", .error)
                    logger.log("TrueDetection: SMS NOTIFICATION '\(keyword)' on Ignition", category: .evaluation, level: .critical, sessionId: sessionId)
                    return .smsVerification
                }
            }
        }

        // CRIMSON SWEEP: Legacy DOM-based error banner detection REMOVED.
        // Red banner detection is now handled exclusively by ThickRedDetectEngine (pixel sniper).
        // See CrimsonSweepOrchestrator.executeCrimsonPipeline() for the new pathway.

        return nil
    }

    // CRIMSON SWEEP: Legacy captureErrorBannerCrop REMOVED.
    // DOM-based banner cropping replaced by ThickRedDetectEngine pixel sampling.
    func captureErrorBannerCrop(
        session: LoginSiteWebSession,
        config: TrueDetectionConfig
    ) async -> UIImage? {
        return await session.captureScreenshot()
    }
}
