import Foundation
import WebKit

@MainActor
final class SubmitMethodRouter {
    static let shared = SubmitMethodRouter()

    private let logger = DebugLogger.shared
    private let tripleClickEngine = TripleClickSubmitEngine.shared
    private let coordEngine = CoordinateInteractionEngine.shared
    private let jsBuilder = LoginJSBuilder.shared

    nonisolated struct SubmitRouteResult: Sendable {
        let success: Bool
        let method: String
        let clicksCompleted: Int
        let elapsedMs: Int
    }

    func executeSubmit(
        method: AutomationSettings.SubmitMethod,
        selectors: [String],
        fallbackSelectors: [String] = [],
        executeJS: @escaping (String) async -> String?,
        sessionId: String = ""
    ) async -> SubmitRouteResult {
        logger.log("SubmitRouter: dispatching via \(method.rawValue)", category: .automation, level: .info, sessionId: sessionId)

        switch method {
        case .tripleClickSynced:
            return await routeTripleClickSynced(
                selectors: selectors,
                fallbackSelectors: fallbackSelectors,
                executeJS: executeJS,
                sessionId: sessionId
            )
        case .singleClickJS:
            return await routeSingleClickJS(
                selectors: selectors,
                fallbackSelectors: fallbackSelectors,
                executeJS: executeJS,
                sessionId: sessionId
            )
        case .coordinateClick:
            return await routeCoordinateClick(
                selectors: selectors,
                fallbackSelectors: fallbackSelectors,
                executeJS: executeJS,
                sessionId: sessionId
            )
        case .enterKeySubmit:
            return await routeEnterKey(
                executeJS: executeJS,
                sessionId: sessionId
            )
        case .formSubmitDirect:
            return await routeFormSubmit(
                executeJS: executeJS,
                sessionId: sessionId
            )
        case .pointerDispatch:
            return await routePointerDispatch(
                selectors: selectors,
                fallbackSelectors: fallbackSelectors,
                executeJS: executeJS,
                sessionId: sessionId
            )
        }
    }

    // MARK: - Route: Triple-Click Synced (Crimson Sweep Phase 2)

    private func routeTripleClickSynced(
        selectors: [String],
        fallbackSelectors: [String],
        executeJS: @escaping (String) async -> String?,
        sessionId: String
    ) async -> SubmitRouteResult {
        do {
            let result = try await tripleClickEngine.executeTripleClickSubmitSequence(
                selectors: selectors,
                fallbackSelectors: fallbackSelectors,
                executeJS: executeJS,
                sessionId: sessionId
            )
            return SubmitRouteResult(
                success: result.success,
                method: result.method,
                clicksCompleted: result.clicksCompleted,
                elapsedMs: result.elapsedMs
            )
        } catch is CancellationError {
            logger.log("SubmitRouter: triple-click cancelled", category: .automation, level: .warning, sessionId: sessionId)
            return SubmitRouteResult(success: false, method: "triple_click_cancelled", clicksCompleted: 0, elapsedMs: 0)
        } catch {
            logger.log("SubmitRouter: triple-click error: \(error)", category: .automation, level: .error, sessionId: sessionId)
            return SubmitRouteResult(success: false, method: "triple_click_error", clicksCompleted: 0, elapsedMs: 0)
        }
    }

    // MARK: - Route: Single Click JS

    private func routeSingleClickJS(
        selectors: [String],
        fallbackSelectors: [String],
        executeJS: @escaping (String) async -> String?,
        sessionId: String
    ) async -> SubmitRouteResult {
        let allSelectors = selectors + fallbackSelectors
        for selector in allSelectors {
            let safeSelector = selector.replacingOccurrences(of: "'", with: "\\'")
            let js = "(function(){var el=document.querySelector('\(safeSelector)');if(!el)return'NOT_FOUND';el.click();return'CLICKED';})()"
            let result = await executeJS(js)
            if result == "CLICKED" {
                logger.log("SubmitRouter: single JS click on \(selector)", category: .automation, level: .info, sessionId: sessionId)
                return SubmitRouteResult(success: true, method: "single_click_js", clicksCompleted: 1, elapsedMs: 0)
            }
        }
        logger.log("SubmitRouter: single JS click — no element found", category: .automation, level: .error, sessionId: sessionId)
        return SubmitRouteResult(success: false, method: "single_click_js_not_found", clicksCompleted: 0, elapsedMs: 0)
    }

    // MARK: - Route: Coordinate Click

    private func routeCoordinateClick(
        selectors: [String],
        fallbackSelectors: [String],
        executeJS: @escaping (String) async -> String?,
        sessionId: String
    ) async -> SubmitRouteResult {
        let result = await coordEngine.coordinateClickWithFallback(
            primarySelectors: selectors,
            fallbackSelectors: fallbackSelectors,
            executeJS: executeJS,
            jitterPx: 3,
            hoverDwellMs: 300,
            sessionId: sessionId
        )
        return SubmitRouteResult(
            success: result.success,
            method: "coordinate_click_\(result.method)",
            clicksCompleted: result.success ? 1 : 0,
            elapsedMs: 0
        )
    }

    // MARK: - Route: Enter Key

    private func routeEnterKey(
        executeJS: @escaping (String) async -> String?,
        sessionId: String
    ) async -> SubmitRouteResult {
        let js = """
        (function(){
            var el=document.querySelector('input[type="password"]');
            if(!el){el=document.querySelector('input[type="email"]')||document.querySelector('input[type="text"]');}
            if(!el)return'NOT_FOUND';
            el.focus();
            el.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',code:'Enter',keyCode:13,which:13,bubbles:true}));
            el.dispatchEvent(new KeyboardEvent('keypress',{key:'Enter',code:'Enter',keyCode:13,which:13,bubbles:true}));
            el.dispatchEvent(new KeyboardEvent('keyup',{key:'Enter',code:'Enter',keyCode:13,which:13,bubbles:true}));
            var form=el.closest('form');
            if(form){form.dispatchEvent(new Event('submit',{bubbles:true,cancelable:true}));}
            return'ENTER_PRESSED';
        })()
        """
        let result = await executeJS(js)
        let ok = result == "ENTER_PRESSED"
        logger.log("SubmitRouter: enter key \(ok ? "OK" : "FAILED")", category: .automation, level: ok ? .info : .warning, sessionId: sessionId)
        return SubmitRouteResult(success: ok, method: "enter_key_submit", clicksCompleted: ok ? 1 : 0, elapsedMs: 0)
    }

    // MARK: - Route: Form Submit Direct

    private func routeFormSubmit(
        executeJS: @escaping (String) async -> String?,
        sessionId: String
    ) async -> SubmitRouteResult {
        let result = await executeJS(jsBuilder.formSubmitJS)
        let ok = result != nil && result != "FAILED"
        logger.log("SubmitRouter: form submit \(ok ? result ?? "" : "FAILED")", category: .automation, level: ok ? .info : .error, sessionId: sessionId)
        return SubmitRouteResult(success: ok, method: "form_submit_direct", clicksCompleted: ok ? 1 : 0, elapsedMs: 0)
    }

    // MARK: - Route: Pointer+Touch Dispatch

    private func routePointerDispatch(
        selectors: [String],
        fallbackSelectors: [String],
        executeJS: @escaping (String) async -> String?,
        sessionId: String
    ) async -> SubmitRouteResult {
        let allSelectors = selectors + fallbackSelectors
        for selector in allSelectors {
            let safeSelector = selector.replacingOccurrences(of: "'", with: "\\'")
            let js = """
            (function(){
                var el=document.querySelector('\(safeSelector)');
                if(!el)return'NOT_FOUND';
                el.scrollIntoView({behavior:'instant',block:'center'});
                var r=el.getBoundingClientRect();
                var cx=r.left+r.width/2,cy=r.top+r.height/2;
                var base={bubbles:true,cancelable:true,view:window,clientX:cx,clientY:cy};
                el.dispatchEvent(new PointerEvent('pointerdown',Object.assign({},base,{pointerId:1,pointerType:'touch',button:0,buttons:1})));
                el.dispatchEvent(new TouchEvent('touchstart',{bubbles:true,cancelable:true}));
                el.dispatchEvent(new MouseEvent('mousedown',Object.assign({},base,{button:0,buttons:1})));
                el.dispatchEvent(new PointerEvent('pointerup',Object.assign({},base,{pointerId:1,pointerType:'touch',button:0,buttons:0})));
                el.dispatchEvent(new TouchEvent('touchend',{bubbles:true,cancelable:true}));
                el.dispatchEvent(new MouseEvent('mouseup',Object.assign({},base,{button:0,buttons:0})));
                el.dispatchEvent(new MouseEvent('click',Object.assign({},base,{button:0,buttons:0})));
                el.click();
                return'DISPATCHED';
            })()
            """
            let result = await executeJS(js)
            if result == "DISPATCHED" {
                logger.log("SubmitRouter: pointer dispatch on \(selector)", category: .automation, level: .info, sessionId: sessionId)
                return SubmitRouteResult(success: true, method: "pointer_touch_dispatch", clicksCompleted: 1, elapsedMs: 0)
            }
        }
        logger.log("SubmitRouter: pointer dispatch — no element found", category: .automation, level: .error, sessionId: sessionId)
        return SubmitRouteResult(success: false, method: "pointer_dispatch_not_found", clicksCompleted: 0, elapsedMs: 0)
    }
}
