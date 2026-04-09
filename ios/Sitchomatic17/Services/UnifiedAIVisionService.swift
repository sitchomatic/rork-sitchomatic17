import Foundation
import UIKit
import Vision

// MARK: - Vision Context

nonisolated enum VisionSite: String, Sendable {
    case joe = "joe"
    case ignition = "ignition"
    case unknown = "unknown"
}

nonisolated enum VisionPhase: String, Sendable {
    case login = "login"
    case ppsr = "ppsr"
    case settlement = "settlement"
    case disabledCheck = "disabled-check"
}

nonisolated struct VisionContext: Sendable {
    let site: VisionSite
    let phase: VisionPhase
    let currentURL: String

    init(site: VisionSite = .unknown, phase: VisionPhase = .login, currentURL: String = "") {
        self.site = site
        self.phase = phase
        self.currentURL = currentURL
    }
}

// MARK: - Vision Outcome

nonisolated enum VisionOutcomeType: String, Sendable {
    case success = "success"
    case incorrectPassword = "incorrect_password"
    case noAccount = "no_account"
    case permDisabled = "perm_disabled"
    case tempDisabled = "temp_disabled"
    case smsVerification = "sms_verification"
    case captchaDetected = "captcha_detected"
    case errorBanner = "error_banner"
    case pageLoading = "page_loading"
    case pageSettled = "page_settled"
    case ppsrPassed = "ppsr_passed"
    case ppsrDeclined = "ppsr_declined"
    case accountDisabledConfirmed = "account_disabled_confirmed"
    case accountActive = "account_active"
    case unknown = "unknown"
}

nonisolated struct VisionOutcome: Sendable {
    let outcome: VisionOutcomeType
    let confidence: Int
    let reasoning: String
    let isPageSettled: Bool
    let isPageBlank: Bool
    let errorText: String
    let rawResponse: String

    static let unknown = VisionOutcome(
        outcome: .unknown,
        confidence: 0,
        reasoning: "No analysis performed",
        isPageSettled: false,
        isPageBlank: false,
        errorText: "",
        rawResponse: ""
    )
}

// MARK: - AI Vision Signal (replaces ConfidenceResultEngine.SignalContribution)

nonisolated struct AIVisionSignal: Sendable {
    let source: String
    let weight: Double
    let rawScore: Double
    let weightedScore: Double
    let detail: String

    init(source: String = "AI_VISION", weight: Double = 1.0, rawScore: Double = 0, weightedScore: Double = 0, detail: String) {
        self.source = source
        self.weight = weight
        self.rawScore = rawScore
        self.weightedScore = weightedScore
        self.detail = detail
    }

    static func fromVisionOutcome(_ outcome: VisionOutcome) -> AIVisionSignal {
        AIVisionSignal(
            source: "AI_VISION",
            weight: 1.0,
            rawScore: Double(outcome.confidence) / 100.0,
            weightedScore: Double(outcome.confidence) / 100.0,
            detail: outcome.reasoning
        )
    }
}

// MARK: - Unified AI Vision Service

@MainActor
final class UnifiedAIVisionService {
    static let shared = UnifiedAIVisionService()

    private let logger = DebugLogger.shared
    private let toolkit = RorkToolkitService.shared

    // MARK: - Primary Entry Point

    func analyzeScreenshot(image: UIImage, context: VisionContext) async -> VisionOutcome {
        // Primary: Grok Vision API
        if let grokResult = await analyzeWithGrok(image: image, context: context) {
            return grokResult
        }

        // Fallback: Apple Vision OCR + on-device analysis
        logger.log("UnifiedAIVision: Grok unavailable, falling back to on-device OCR analysis", category: .automation, level: .warning)
        return await analyzeWithOnDeviceOCR(image: image, context: context)
    }

    // MARK: - Grok Vision (Primary)

    private func analyzeWithGrok(image: UIImage, context: VisionContext) async -> VisionOutcome? {
        let prompt = buildPrompt(for: context)

        guard let result = await toolkit.analyzeWithUnifiedVision(image: image, prompt: prompt) else {
            return nil
        }

        let parsed = parseGrokResponse(result, context: context)
        // Treat parse failures as nil so OCR fallback can run
        let normalizedReasoning = parsed.reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        if parsed.outcome == .unknown &&
            (normalizedReasoning.isEmpty || normalizedReasoning == "Failed to parse Grok response") {
            return nil
        }
        return parsed
    }

    private func buildPrompt(for context: VisionContext) -> String {
        switch context.phase {
        case .login:
            return """
            Analyze this casino/gambling website screenshot after a login attempt. Determine the exact result.

            Answer ONLY with JSON:
            {
              "outcome": "success|incorrect_password|no_account|perm_disabled|temp_disabled|sms_verification|captcha_detected|error_banner|unknown",
              "confidence": 90,
              "reasoning": "Brief explanation of what you see",
              "errorText": "",
              "isPageSettled": true,
              "isPageBlank": false,
              "isLobbyOrDashboard": false,
              "isSMSDetected": false
            }

            Rules:
            - outcome=success if you see a lobby, dashboard, game grid, user balance — NOT the login form
            - outcome=incorrect_password if you see "incorrect password", "invalid credentials", red error message about credentials
            - outcome=no_account if you see "account not found", "no account exists"
            - outcome=perm_disabled if text says "has been disabled", "account suspended", "permanently banned"
            - outcome=temp_disabled if text says "temporarily disabled", "temporarily locked"
            - outcome=sms_verification if you see SMS/phone verification prompt
            - outcome=captcha_detected if there is a CAPTCHA challenge
            - outcome=error_banner if there is a visible error not matching above categories
            - isPageSettled=true if the page has fully loaded with definitive content
            - isPageBlank=true if the page appears blank or still loading
            - errorText = exact visible error text, empty string if none
            - confidence = 0-100 how confident you are
            """

        case .settlement:
            return """
            Analyze this website screenshot to determine if the page has settled after a form submission.

            Answer ONLY with JSON:
            {
              "outcome": "page_settled|page_loading|success|incorrect_password|error_banner|unknown",
              "confidence": 90,
              "reasoning": "Brief explanation",
              "errorText": "",
              "isPageSettled": true,
              "isPageBlank": false,
              "hasContentChanged": true
            }

            Rules:
            - isPageSettled=true if the page has fully loaded with definitive content (not a spinner/loading state)
            - isPageBlank=true if the page appears blank/white/empty
            - outcome=page_loading if there are loading spinners, progress bars, or the page is clearly still loading
            - outcome=page_settled if the page is loaded but you can't determine success/failure
            - If you can determine success/failure, use the specific outcome
            """

        case .ppsr:
            return """
            Analyze this Australian PPSR vehicle check payment page screenshot.

            Answer ONLY with JSON:
            {
              "outcome": "ppsr_passed|ppsr_declined|error_banner|unknown",
              "confidence": 90,
              "reasoning": "Brief explanation",
              "errorText": "",
              "isPageSettled": true,
              "isPageBlank": false
            }

            Rules:
            - outcome=ppsr_passed if you see a PPSR certificate, success message, or confirmation page
            - outcome=ppsr_declined if you see "declined", "payment failed", "card declined", "insufficient funds"
            - outcome=error_banner for any other error
            """

        case .disabledCheck:
            return """
            Analyze this website screenshot to determine if the account is disabled/suspended.

            Answer ONLY with JSON:
            {
              "outcome": "account_disabled_confirmed|account_active|unknown",
              "confidence": 90,
              "reasoning": "Brief explanation",
              "errorText": "",
              "isPageSettled": true,
              "isPageBlank": false,
              "isPermanentBan": false,
              "isTempLock": false
            }

            Rules:
            - outcome=account_disabled_confirmed if you see "has been disabled", "suspended", "banned", "account is closed"
            - outcome=account_active if you see normal login page, dashboard, or lobby
            - isPermanentBan=true ONLY for permanent disabled/banned messages
            - isTempLock=true ONLY for temporary disabled/locked messages
            """
        }
    }

    private func parseGrokResponse(_ raw: String, context: VisionContext) -> VisionOutcome {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonStr: String
        if let start = cleaned.range(of: "{"), let end = cleaned.range(of: "}", options: .backwards) {
            jsonStr = String(cleaned[start.lowerBound...end.lowerBound])
        } else {
            jsonStr = cleaned
        }

        guard let data = jsonStr.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return VisionOutcome(
                outcome: .unknown,
                confidence: 20,
                reasoning: "Failed to parse Grok response",
                isPageSettled: false,
                isPageBlank: false,
                errorText: "",
                rawResponse: raw
            )
        }

        let outcomeStr = dict["outcome"] as? String ?? "unknown"
        let outcomeType = VisionOutcomeType(rawValue: outcomeStr) ?? .unknown

        return VisionOutcome(
            outcome: outcomeType,
            confidence: Self.parseConfidence(dict["confidence"]),
            reasoning: dict["reasoning"] as? String ?? "",
            isPageSettled: dict["isPageSettled"] as? Bool ?? false,
            isPageBlank: dict["isPageBlank"] as? Bool ?? false,
            errorText: dict["errorText"] as? String ?? "",
            rawResponse: raw
        )
    }

    /// Parse confidence from Grok JSON — accepts Int, Double, or numeric String, clamped to 0–100.
    private static func parseConfidence(_ value: Any?) -> Int {
        if let intVal = value as? Int {
            return min(max(intVal, 0), 100)
        }
        if let doubleVal = value as? Double {
            return min(max(Int(doubleVal), 0), 100)
        }
        if let strVal = value as? String, let parsed = Double(strVal) {
            return min(max(Int(parsed), 0), 100)
        }
        return 50
    }

    // MARK: - On-Device OCR Fallback

    private func analyzeWithOnDeviceOCR(image: UIImage, context: VisionContext) async -> VisionOutcome {
        let ocrTexts = await extractOCRText(from: image)
        let combinedText = ocrTexts.joined(separator: " ").lowercased()

        if combinedText.isEmpty {
            return VisionOutcome(
                outcome: .unknown,
                confidence: 20,
                reasoning: "No text detected via OCR — page may be blank or image-heavy",
                isPageSettled: false,
                isPageBlank: true,
                errorText: "",
                rawResponse: ""
            )
        }

        return classifyFromOCRText(combinedText, context: context)
    }

    private func extractOCRText(from image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { request, error in
                    guard error == nil,
                          let observations = request.results as? [VNRecognizedTextObservation] else {
                        continuation.resume(returning: [])
                        return
                    }
                    let texts = observations.compactMap { $0.topCandidates(1).first?.string }
                    continuation.resume(returning: texts)
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    private func classifyFromOCRText(_ text: String, context: VisionContext) -> VisionOutcome {
        switch context.phase {
        case .login:
            return classifyLoginOCR(text)
        case .ppsr:
            return classifyPPSROCR(text)
        case .disabledCheck:
            return classifyDisabledCheckOCR(text)
        case .settlement:
            return classifySettlementOCR(text)
        }
    }

    private func classifyLoginOCR(_ text: String) -> VisionOutcome {
        if text.contains("incorrect") || text.contains("invalid credentials") || text.contains("wrong password") {
            return VisionOutcome(outcome: .incorrectPassword, confidence: 70, reasoning: "OCR fallback: error text detected", isPageSettled: true, isPageBlank: false, errorText: "Incorrect password detected via OCR", rawResponse: "")
        }
        if text.contains("has been disabled") || text.contains("permanently banned") || text.contains("account is closed") {
            return VisionOutcome(outcome: .permDisabled, confidence: 75, reasoning: "OCR fallback: permanent disable text detected", isPageSettled: true, isPageBlank: false, errorText: "Account disabled detected via OCR", rawResponse: "")
        }
        if text.contains("temporarily disabled") || text.contains("temporarily locked") {
            return VisionOutcome(outcome: .tempDisabled, confidence: 75, reasoning: "OCR fallback: temporary disable text detected", isPageSettled: true, isPageBlank: false, errorText: "Temp disabled detected via OCR", rawResponse: "")
        }
        if text.contains("account not found") || text.contains("no account") {
            return VisionOutcome(outcome: .noAccount, confidence: 70, reasoning: "OCR fallback: no account text detected", isPageSettled: true, isPageBlank: false, errorText: "No account detected via OCR", rawResponse: "")
        }
        if text.contains("sms") || text.contains("verification code") || text.contains("phone verification") {
            return VisionOutcome(outcome: .smsVerification, confidence: 65, reasoning: "OCR fallback: SMS verification prompt detected", isPageSettled: true, isPageBlank: false, errorText: "", rawResponse: "")
        }
        if text.contains("captcha") || text.contains("not a robot") {
            return VisionOutcome(outcome: .captchaDetected, confidence: 65, reasoning: "OCR fallback: CAPTCHA detected", isPageSettled: true, isPageBlank: false, errorText: "", rawResponse: "")
        }
        if text.contains("lobby") || text.contains("dashboard") || text.contains("balance") || text.contains("my account") || text.contains("deposit") || text.contains("logout") {
            return VisionOutcome(outcome: .success, confidence: 60, reasoning: "OCR fallback: success indicators detected in page text", isPageSettled: true, isPageBlank: false, errorText: "", rawResponse: "")
        }

        return VisionOutcome(outcome: .unknown, confidence: 30, reasoning: "OCR fallback: no definitive indicators found", isPageSettled: true, isPageBlank: false, errorText: "", rawResponse: "")
    }

    private func classifyPPSROCR(_ text: String) -> VisionOutcome {
        if text.contains("certificate") || (text.contains("ppsr") && text.contains("success")) {
            return VisionOutcome(outcome: .ppsrPassed, confidence: 65, reasoning: "OCR fallback: PPSR success indicators detected", isPageSettled: true, isPageBlank: false, errorText: "", rawResponse: "")
        }
        if text.contains("declined") || text.contains("payment failed") || text.contains("insufficient funds") {
            return VisionOutcome(outcome: .ppsrDeclined, confidence: 65, reasoning: "OCR fallback: PPSR declined indicators detected", isPageSettled: true, isPageBlank: false, errorText: "Payment declined via OCR", rawResponse: "")
        }
        return VisionOutcome(outcome: .unknown, confidence: 30, reasoning: "OCR fallback: no PPSR indicators found", isPageSettled: true, isPageBlank: false, errorText: "", rawResponse: "")
    }

    private func classifyDisabledCheckOCR(_ text: String) -> VisionOutcome {
        if text.contains("has been disabled") || text.contains("suspended") || text.contains("banned") || text.contains("account is closed") {
            let isPerm = text.contains("has been disabled") || text.contains("permanently")
            let isTemp = text.contains("temporarily")
            return VisionOutcome(outcome: .accountDisabledConfirmed, confidence: 70, reasoning: "OCR fallback: disabled account indicators detected (perm=\(isPerm), temp=\(isTemp))", isPageSettled: true, isPageBlank: false, errorText: "", rawResponse: "")
        }
        return VisionOutcome(outcome: .accountActive, confidence: 40, reasoning: "OCR fallback: no disabled indicators found", isPageSettled: true, isPageBlank: false, errorText: "", rawResponse: "")
    }

    private func classifySettlementOCR(_ text: String) -> VisionOutcome {
        if text.contains("loading") || text.contains("please wait") {
            return VisionOutcome(outcome: .pageLoading, confidence: 50, reasoning: "OCR fallback: loading indicators detected", isPageSettled: false, isPageBlank: false, errorText: "", rawResponse: "")
        }
        return VisionOutcome(outcome: .pageSettled, confidence: 40, reasoning: "OCR fallback: page appears settled", isPageSettled: true, isPageBlank: false, errorText: "", rawResponse: "")
    }

    // MARK: - Convenience: Convert to LoginOutcome

    func toLoginOutcome(_ visionOutcome: VisionOutcome) -> LoginOutcome {
        switch visionOutcome.outcome {
        case .success: return .success
        case .incorrectPassword, .noAccount: return .noAcc
        case .permDisabled, .accountDisabledConfirmed: return .permDisabled
        case .tempDisabled: return .tempDisabled
        case .smsVerification: return .smsDetected
        case .captchaDetected, .errorBanner: return .unsure
        case .ppsrPassed, .ppsrDeclined: return .unsure
        case .pageLoading, .pageSettled, .accountActive, .unknown: return .unsure
        }
    }
}
