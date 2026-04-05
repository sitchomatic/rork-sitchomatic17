import Foundation
import WebKit

@MainActor
final class TripleClickSubmitEngine {
    static let shared = TripleClickSubmitEngine()

    private let logger = DebugLogger.shared

    nonisolated struct TripleClickSequenceResult: Sendable {
        let success: Bool
        let clicksCompleted: Int
        let method: String
        let elapsedMs: Int
    }

    nonisolated enum TripleClickError: Error, Sendable {
        case cancelled
        case targetNotFound
        case webViewUnavailable
        case jsEvaluationFailed(String)
    }

    func executeTripleClickSubmitSequence(
        targetSelector: String,
        executeJS: @escaping (String) async -> String?,
        sessionId: String = ""
    ) async throws -> TripleClickSequenceResult {
        let start = ContinuousClock.now

        guard !Task.isCancelled else { throw TripleClickError.cancelled }

        let locateResult = await locateTargetElement(
            selector: targetSelector,
            executeJS: executeJS,
            sessionId: sessionId
        )
        guard let elementRect = locateResult else {
            logger.log("TripleClickEngine: target NOT_FOUND at \(targetSelector)", category: .automation, level: .error, sessionId: sessionId)
            return TripleClickSequenceResult(success: false, clicksCompleted: 0, method: "NOT_FOUND", elapsedMs: 0)
        }

        guard !Task.isCancelled else { throw TripleClickError.cancelled }

        logger.log("TripleClickEngine: target acquired at (\(Int(elementRect.cx)),\(Int(elementRect.cy))) — starting 3-click sequence", category: .automation, level: .info, sessionId: sessionId)

        // --- Click 1 ---
        let click1JS = buildSyntheticClickJS(
            selector: targetSelector,
            cx: elementRect.cx,
            cy: elementRect.cy,
            jitterPx: 3,
            clickIndex: 1
        )
        let click1Result = await executeJS(click1JS)
        let click1Ok = click1Result != nil && click1Result != "NO_EL" && click1Result != "NOT_FOUND"

        guard !Task.isCancelled else { throw TripleClickError.cancelled }

        if click1Ok {
            logger.log("TripleClickEngine: click 1/3 dispatched", category: .automation, level: .trace, sessionId: sessionId)
        } else {
            logger.log("TripleClickEngine: click 1/3 FAILED (\(click1Result ?? "nil"))", category: .automation, level: .warning, sessionId: sessionId)
        }

        // --- Inter-click delay 1: 240ms ---
        try await Task.sleep(for: .milliseconds(240))
        guard !Task.isCancelled else { throw TripleClickError.cancelled }

        // --- Click 2 ---
        let freshRect2 = await locateTargetElement(selector: targetSelector, executeJS: executeJS, sessionId: sessionId) ?? elementRect
        let click2JS = buildSyntheticClickJS(
            selector: targetSelector,
            cx: freshRect2.cx,
            cy: freshRect2.cy,
            jitterPx: 3,
            clickIndex: 2
        )
        let click2Result = await executeJS(click2JS)
        let click2Ok = click2Result != nil && click2Result != "NO_EL" && click2Result != "NOT_FOUND"

        guard !Task.isCancelled else { throw TripleClickError.cancelled }

        if click2Ok {
            logger.log("TripleClickEngine: click 2/3 dispatched", category: .automation, level: .trace, sessionId: sessionId)
        } else {
            logger.log("TripleClickEngine: click 2/3 FAILED (\(click2Result ?? "nil"))", category: .automation, level: .warning, sessionId: sessionId)
        }

        // --- Inter-click delay 2: 260ms ---
        try await Task.sleep(for: .milliseconds(260))
        guard !Task.isCancelled else { throw TripleClickError.cancelled }

        // --- Click 3 ---
        let freshRect3 = await locateTargetElement(selector: targetSelector, executeJS: executeJS, sessionId: sessionId) ?? elementRect
        let click3JS = buildSyntheticClickJS(
            selector: targetSelector,
            cx: freshRect3.cx,
            cy: freshRect3.cy,
            jitterPx: 3,
            clickIndex: 3
        )
        let click3Result = await executeJS(click3JS)
        let click3Ok = click3Result != nil && click3Result != "NO_EL" && click3Result != "NOT_FOUND"

        if click3Ok {
            logger.log("TripleClickEngine: click 3/3 dispatched", category: .automation, level: .trace, sessionId: sessionId)
        } else {
            logger.log("TripleClickEngine: click 3/3 FAILED (\(click3Result ?? "nil"))", category: .automation, level: .warning, sessionId: sessionId)
        }

        let completed = [click1Ok, click2Ok, click3Ok].filter { $0 }.count
        let success = completed >= 2
        let duration = ContinuousClock.now - start
        let components = duration.components
        let secondsMs: Int = Int(components.seconds) * 1000
        let attoMs: Int = Int(Double(components.attoseconds) / 1e15)
        let elapsed: Int = secondsMs + attoMs

        logger.log("TripleClickEngine: sequence complete — \(completed)/3 clicks (\(success ? "OK" : "PARTIAL")) in \(elapsed)ms", category: .automation, level: success ? .success : .warning, sessionId: sessionId)

        return TripleClickSequenceResult(
            success: success,
            clicksCompleted: completed,
            method: "crimson_triple_click_synced",
            elapsedMs: elapsed
        )
    }

    // MARK: - Multi-Selector Overload

    func executeTripleClickSubmitSequence(
        selectors: [String],
        fallbackSelectors: [String] = [],
        executeJS: @escaping (String) async -> String?,
        sessionId: String = ""
    ) async throws -> TripleClickSequenceResult {
        let allSelectors = selectors + fallbackSelectors
        for selector in allSelectors {
            if await locateTargetElement(selector: selector, executeJS: executeJS, sessionId: sessionId) != nil {
                return try await executeTripleClickSubmitSequence(
                    targetSelector: selector,
                    executeJS: executeJS,
                    sessionId: sessionId
                )
            }
        }
        logger.log("TripleClickEngine: no selector matched from \(allSelectors.count) candidates", category: .automation, level: .error, sessionId: sessionId)
        return TripleClickSequenceResult(success: false, clicksCompleted: 0, method: "NOT_FOUND", elapsedMs: 0)
    }

    // MARK: - Element Location

    private nonisolated struct ElementLocation: Sendable {
        let cx: Double
        let cy: Double
        let width: Double
        let height: Double
    }

    private func locateTargetElement(
        selector: String,
        executeJS: @escaping (String) async -> String?,
        sessionId: String
    ) async -> ElementLocation? {
        let safeSelector = selector.replacingOccurrences(of: "'", with: "\\'").replacingOccurrences(of: "\\", with: "\\\\")
        let js = """
        (function(){
            var el=document.querySelector('\(safeSelector)');
            if(!el)return'NOT_FOUND';
            var r=el.getBoundingClientRect();
            if(r.width===0||r.height===0)return'NOT_FOUND';
            return JSON.stringify({cx:r.left+r.width/2,cy:r.top+r.height/2,w:r.width,h:r.height});
        })()
        """
        guard let raw = await executeJS(js), raw != "NOT_FOUND",
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let cx = json["cx"] as? Double,
              let cy = json["cy"] as? Double,
              let w = json["w"] as? Double,
              let h = json["h"] as? Double,
              w > 0, h > 0 else {
            return nil
        }
        return ElementLocation(cx: cx, cy: cy, width: w, height: h)
    }

    // MARK: - Synthetic Click JS

    private func buildSyntheticClickJS(
        selector: String,
        cx: Double,
        cy: Double,
        jitterPx: Int,
        clickIndex: Int
    ) -> String {
        let jx = Double.random(in: Double(-jitterPx)...Double(jitterPx))
        let jy = Double.random(in: Double(-jitterPx)...Double(jitterPx))
        let fx = cx + jx
        let fy = cy + jy
        return """
        (function(){
            var el=document.elementFromPoint(\(fx),\(fy));
            if(!el)return'NO_EL';
            var opts={bubbles:true,cancelable:true,view:window,clientX:\(fx),clientY:\(fy)};
            el.dispatchEvent(new MouseEvent('mousedown',Object.assign({},opts,{button:0,buttons:1})));
            el.dispatchEvent(new PointerEvent('pointerdown',Object.assign({},opts,{pointerId:1,pointerType:'mouse',button:0,buttons:1})));
            el.dispatchEvent(new PointerEvent('pointerup',Object.assign({},opts,{pointerId:1,pointerType:'mouse',button:0,buttons:0})));
            el.dispatchEvent(new MouseEvent('mouseup',Object.assign({},opts,{button:0,buttons:0})));
            el.dispatchEvent(new MouseEvent('click',Object.assign({},opts,{button:0,buttons:0})));
            return'CLICK_\(clickIndex)_OK';
        })()
        """
    }
}
