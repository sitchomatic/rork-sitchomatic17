import Foundation
import WebKit

@MainActor
final class CrimsonSweepOrchestrator {
    static let shared = CrimsonSweepOrchestrator()

    private let logger = DebugLogger.shared
    private let tripleClickEngine = TripleClickSubmitEngine.shared
    private let pixelSniper = ThickRedDetectEngine.shared
    private let janitor = WebViewLifecycleManager.shared
    private let submitRouter = SubmitMethodRouter.shared

    nonisolated enum OrchestratorOutcome: Sendable {
        case success
        case redBannerDetected
        case submitFailed(String)
        case cancelled
        case error(String)
    }

    nonisolated struct CrimsonResult: Sendable {
        let outcome: OrchestratorOutcome
        let submitClicksCompleted: Int
        let submitMethod: String
        let elapsedMs: Int
        let pixelSniperResult: ThickRedDetectEngine.DetectResult?
    }

    func executeCrimsonPipeline(
        session: LoginSiteWebSession,
        settings: AutomationSettings,
        submitSelectors: [String],
        fallbackSelectors: [String] = [],
        sessionId: String = "",
        onRedDetected: (() async -> Void)? = nil,
        onSuccess: (() async -> Void)? = nil
    ) async -> CrimsonResult {
        guard let webView = session.webView else {
            logger.log("CrimsonSweep: NO WEBVIEW — aborting pipeline", category: .automation, level: .critical, sessionId: sessionId)
            return CrimsonResult(outcome: .error("No WebView available"), submitClicksCompleted: 0, submitMethod: "none", elapsedMs: 0, pixelSniperResult: nil)
        }

        let pipelineLabel = "crimson:\(sessionId.prefix(8))"
        janitor.track(webView, label: pipelineLabel)
        logger.log("CrimsonSweep: pipeline START — method=\(settings.joeSubmitMethod.rawValue) selectors=\(submitSelectors.count)+\(fallbackSelectors.count)", category: .automation, level: .info, sessionId: sessionId)

        let start = ContinuousClock.now

        var submitResult: SubmitMethodRouter.SubmitRouteResult?
        var sniperResult: ThickRedDetectEngine.DetectResult?

        defer {
            janitor.performDeepClean(on: webView, label: pipelineLabel)
            let duration = ContinuousClock.now - start
            let components = duration.components
            let ms = Int(components.seconds) * 1000 + Int(Double(components.attoseconds) / 1e15)
            logger.log("CrimsonSweep: pipeline END — \(ms)ms (defer cleanup fired)", category: .automation, level: .info, sessionId: sessionId)
        }

        do {
            guard !Task.isCancelled else { throw CancellationError() }

            // --- PHASE 2: Submit via configured method ---

            let activeMethod = settings.joeSubmitMethod
            logger.log("CrimsonSweep: Phase 2 — launching submit via \(activeMethod.rawValue)", category: .automation, level: .info, sessionId: sessionId)

            let routeResult = await submitRouter.executeSubmit(
                method: activeMethod,
                selectors: submitSelectors,
                fallbackSelectors: fallbackSelectors,
                executeJS: { js in await session.executeJS(js) },
                sessionId: sessionId
            )
            submitResult = routeResult

            guard !Task.isCancelled else { throw CancellationError() }

            if !routeResult.success {
                logger.log("CrimsonSweep: Phase 2 FAILED — \(routeResult.method) (\(routeResult.clicksCompleted) clicks)", category: .automation, level: .error, sessionId: sessionId)
                return buildResult(outcome: .submitFailed(routeResult.method), submit: routeResult, sniper: nil, start: start)
            }

            logger.log("CrimsonSweep: Phase 2 COMPLETE — \(routeResult.clicksCompleted) clicks via \(routeResult.method)", category: .automation, level: .success, sessionId: sessionId)

            // --- PHASE 3: ThickRedDetect Pixel Sniper Race ---

            guard !Task.isCancelled else { throw CancellationError() }

            logger.log("CrimsonSweep: Phase 3 — launching pixel sniper race", category: .evaluation, level: .info, sessionId: sessionId)

            let detectResult = await pixelSniper.runPostClickDetection(
                webView: webView,
                sessionId: sessionId
            )
            sniperResult = detectResult

            guard !Task.isCancelled else { throw CancellationError() }

            switch detectResult {
            case .redDetected:
                logger.log("CrimsonSweep: Phase 3 — RED DETECTED — routing to handleRedDetect", category: .evaluation, level: .critical, sessionId: sessionId)
                await onRedDetected?()
                return buildResult(outcome: .redBannerDetected, submit: routeResult, sniper: detectResult, start: start)

            case .clean:
                logger.log("CrimsonSweep: Phase 3 — CLEAN — no red banner, continuing automation", category: .evaluation, level: .success, sessionId: sessionId)
                await onSuccess?()
                return buildResult(outcome: .success, submit: routeResult, sniper: detectResult, start: start)

            case .cancelled:
                logger.log("CrimsonSweep: Phase 3 — cancelled during pixel sniper", category: .evaluation, level: .warning, sessionId: sessionId)
                return buildResult(outcome: .cancelled, submit: routeResult, sniper: detectResult, start: start)

            case .snapshotFailed:
                logger.log("CrimsonSweep: Phase 3 — snapshot failures, treating as clean (optimistic)", category: .evaluation, level: .warning, sessionId: sessionId)
                await onSuccess?()
                return buildResult(outcome: .success, submit: routeResult, sniper: detectResult, start: start)
            }

        } catch is CancellationError {
            logger.log("CrimsonSweep: pipeline CANCELLED", category: .automation, level: .warning, sessionId: sessionId)
            return buildResult(outcome: .cancelled, submit: submitResult, sniper: sniperResult, start: start)
        } catch {
            logger.log("CrimsonSweep: pipeline ERROR — \(error)", category: .automation, level: .error, sessionId: sessionId)
            return buildResult(outcome: .error(error.localizedDescription), submit: submitResult, sniper: sniperResult, start: start)
        }
    }

    private func buildResult(
        outcome: OrchestratorOutcome,
        submit: SubmitMethodRouter.SubmitRouteResult?,
        sniper: ThickRedDetectEngine.DetectResult?,
        start: ContinuousClock.Instant
    ) -> CrimsonResult {
        let duration = ContinuousClock.now - start
        let components = duration.components
        let ms = Int(components.seconds) * 1000 + Int(Double(components.attoseconds) / 1e15)
        return CrimsonResult(
            outcome: outcome,
            submitClicksCompleted: submit?.clicksCompleted ?? 0,
            submitMethod: submit?.method ?? "none",
            elapsedMs: ms,
            pixelSniperResult: sniper
        )
    }
}
