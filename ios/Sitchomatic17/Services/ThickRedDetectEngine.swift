import Foundation
import WebKit
import CoreGraphics
import UIKit

@MainActor
final class ThickRedDetectEngine {
    static let shared = ThickRedDetectEngine()

    private let logger = DebugLogger.shared

    nonisolated enum DetectResult: Sendable {
        case clean
        case redDetected
        case cancelled
        case snapshotFailed
    }

    nonisolated enum SniperError: Error, Sendable {
        case cancelled
        case webViewUnavailable
        case snapshotFailed
        case taskGroupRace
    }

    private static let sampleRect = CGRect(x: 40, y: 20, width: 15, height: 15)
    private static let pollInterval: Duration = .milliseconds(150)
    private static let successTimeout: Duration = .seconds(3)
    private static let redThresholdR: UInt8 = 160
    private static let redThresholdG: UInt8 = 90
    private static let redThresholdB: UInt8 = 90
    private static let expectedPixelCount = 225 // 15 * 15

    func runPostClickDetection(
        webView: WKWebView,
        sessionId: String = ""
    ) async -> DetectResult {
        guard !Task.isCancelled else { return .cancelled }

        logger.log("ThickRedDetect: starting post-click pixel sniper race", category: .evaluation, level: .info, sessionId: sessionId)

        do {
            let result: DetectResult = try await withThrowingTaskGroup(of: DetectResult.self) { group in

                group.addTask { @MainActor [self] in
                    try await Task.sleep(for: Self.successTimeout)
                    guard !Task.isCancelled else { throw SniperError.cancelled }
                    logger.log("ThickRedDetect: Runner A — 3s timeout elapsed, no red detected → CLEAN", category: .evaluation, level: .success, sessionId: sessionId)
                    return .clean
                }

                group.addTask { @MainActor [self] in
                    var pollCount = 0
                    while !Task.isCancelled {
                        pollCount += 1
                        let detected = await self.samplePixels(webView: webView, sessionId: sessionId, pollIndex: pollCount)
                        guard !Task.isCancelled else { throw SniperError.cancelled }

                        if detected {
                            logger.log("ThickRedDetect: Runner B — RED DETECTED on poll #\(pollCount) → triggering handleRedDetect", category: .evaluation, level: .critical, sessionId: sessionId)
                            return .redDetected
                        }

                        try await Task.sleep(for: Self.pollInterval)
                        guard !Task.isCancelled else { throw SniperError.cancelled }
                    }
                    throw SniperError.cancelled
                }

                guard let winner = try await group.next() else {
                    throw SniperError.taskGroupRace
                }
                group.cancelAll()
                return winner
            }
            return result
        } catch is CancellationError {
            logger.log("ThickRedDetect: race cancelled externally", category: .evaluation, level: .warning, sessionId: sessionId)
            return .cancelled
        } catch is SniperError {
            logger.log("ThickRedDetect: sniper error during race", category: .evaluation, level: .warning, sessionId: sessionId)
            return .cancelled
        } catch {
            logger.log("ThickRedDetect: unexpected error: \(error)", category: .evaluation, level: .error, sessionId: sessionId)
            return .snapshotFailed
        }
    }

    // MARK: - Pixel Sampling

    private func samplePixels(
        webView: WKWebView,
        sessionId: String,
        pollIndex: Int
    ) async -> Bool {
        let config = WKSnapshotConfiguration()
        config.rect = Self.sampleRect

        guard let snapshot = try? await webView.takeSnapshot(configuration: config) else {
            if pollIndex <= 2 {
                logger.log("ThickRedDetect: snapshot failed on poll #\(pollIndex)", category: .screenshot, level: .debug, sessionId: sessionId)
            }
            return false
        }

        guard let cgImage = snapshot.cgImage else { return false }

        return analyzePixels(cgImage: cgImage, sessionId: sessionId, pollIndex: pollIndex)
    }

    // MARK: - Core Graphics Pixel Math

    private func analyzePixels(cgImage: CGImage, sessionId: String, pollIndex: Int) -> Bool {
        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data else { return false }

        let ptr: UnsafePointer<UInt8> = CFDataGetBytePtr(data)
        let bytesPerRow = cgImage.bytesPerRow
        let bitsPerPixel = cgImage.bitsPerPixel
        let bytesPerPixel = bitsPerPixel / 8
        let width = cgImage.width
        let height = cgImage.height

        guard bytesPerPixel >= 3 else { return false }

        let alphaInfo = cgImage.alphaInfo
        let byteOrder = cgImage.bitmapInfo.intersection(.byteOrderMask)

        let isBGRA: Bool = {
            if byteOrder == .byteOrder32Little {
                return true
            }
            if byteOrder == .byteOrder32Big || byteOrder == CGBitmapInfo(rawValue: 0) {
                if alphaInfo == .premultipliedFirst || alphaInfo == .first || alphaInfo == .noneSkipFirst {
                    return true
                }
                return false
            }
            return false
        }()

        var crimsonCount = 0
        let totalPixels = width * height

        for y in 0..<height {
            let rowBase = y * bytesPerRow
            for x in 0..<width {
                let offset = rowBase + (x * bytesPerPixel)

                let r: UInt8
                let g: UInt8
                let b: UInt8

                if isBGRA {
                    b = ptr[offset]
                    g = ptr[offset + 1]
                    r = ptr[offset + 2]
                } else {
                    r = ptr[offset]
                    g = ptr[offset + 1]
                    b = ptr[offset + 2]
                }

                if r > Self.redThresholdR && g < Self.redThresholdG && b < Self.redThresholdB {
                    crimsonCount += 1
                } else {
                    return false
                }
            }
        }

        if crimsonCount == totalPixels && totalPixels > 0 {
            logger.log("ThickRedDetect: ALL \(totalPixels) pixels crimson (poll #\(pollIndex)) — format: \(isBGRA ? "BGRA" : "RGBA")", category: .evaluation, level: .critical, sessionId: sessionId)
            return true
        }

        return false
    }
}
