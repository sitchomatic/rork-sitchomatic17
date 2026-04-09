import Foundation
import UIKit

// MARK: - Settlement Result

nonisolated struct AIVisionSettlementResult: Sendable {
    let settled: Bool
    let outcome: VisionOutcome
    let screenshotCount: Int
    let totalElapsedMs: Int
}

// MARK: - AI Vision Settlement Service

@MainActor
final class AIVisionSettlementService {
    static let shared = AIVisionSettlementService()

    private let logger = DebugLogger.shared
    private let aiVision = UnifiedAIVisionService.shared

    /// Adaptive screenshot intervals (milliseconds)
    private let intervals: [Int] = [500, 1500, 3000, 5000]

    // MARK: - Wait for Settlement

    func waitForSettlement(
        captureScreenshot: @Sendable () async -> UIImage?,
        context: VisionContext,
        maxTimeoutMs: Int = 8000
    ) async -> AIVisionSettlementResult {
        let startTime = Date()
        var screenshotCount = 0
        var lastOutcome: VisionOutcome? = nil

        for interval in intervals {
            let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
            if elapsed >= maxTimeoutMs { break }

            // Wait for the interval
            let waitMs = min(interval, maxTimeoutMs - elapsed)
            if waitMs > 0 {
                try? await Task.sleep(for: .milliseconds(waitMs))
            }

            // Capture and analyze screenshot
            guard let screenshot = await captureScreenshot() else {
                logger.log("AIVisionSettlement: screenshot capture failed at interval \(interval)ms", category: .automation, level: .warning)
                continue
            }

            screenshotCount += 1

            let settlementContext = VisionContext(
                site: context.site,
                phase: .settlement,
                currentURL: context.currentURL
            )

            // Apply per-iteration timeout based on remaining budget
            let remainingMs = maxTimeoutMs - Int(Date().timeIntervalSince(startTime) * 1000)
            guard remainingMs > 0 else { break }

            let analysisResult: VisionOutcome? = await withTaskGroup(of: VisionOutcome?.self) { group in
                group.addTask {
                    await self.aiVision.analyzeScreenshot(image: screenshot, context: settlementContext)
                }
                group.addTask {
                    try? await Task.sleep(for: .milliseconds(remainingMs))
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }

            guard let result = analysisResult else {
                logger.log("AIVisionSettlement: analysis timed out at interval \(interval)ms (budget exhausted)", category: .automation, level: .warning)
                break
            }
            lastOutcome = result

            logger.log("AIVisionSettlement: screenshot \(screenshotCount) at \(interval)ms — settled=\(result.isPageSettled), outcome=\(result.outcome.rawValue), confidence=\(result.confidence)", category: .automation, level: .info)

            // If page is settled with a definitive outcome, return immediately
            if result.isPageSettled
                && result.outcome != .pageLoading
                && result.outcome != .unknown
                && result.confidence >= 50 {
                let totalMs = Int(Date().timeIntervalSince(startTime) * 1000)
                return AIVisionSettlementResult(
                    settled: true,
                    outcome: result,
                    screenshotCount: screenshotCount,
                    totalElapsedMs: totalMs
                )
            }
        }

        // Timeout — return last analysis or unknown
        let totalMs = Int(Date().timeIntervalSince(startTime) * 1000)
        logger.log("AIVisionSettlement: timed out after \(totalMs)ms with \(screenshotCount) screenshots", category: .automation, level: .warning)

        return AIVisionSettlementResult(
            settled: false,
            outcome: lastOutcome ?? .unknown,
            screenshotCount: screenshotCount,
            totalElapsedMs: totalMs
        )
    }

    // MARK: - Single Screenshot Settlement Check

    func checkSettlement(
        screenshot: UIImage,
        context: VisionContext
    ) async -> VisionOutcome {
        let settlementContext = VisionContext(
            site: context.site,
            phase: .settlement,
            currentURL: context.currentURL
        )
        return await aiVision.analyzeScreenshot(image: screenshot, context: settlementContext)
    }
}
