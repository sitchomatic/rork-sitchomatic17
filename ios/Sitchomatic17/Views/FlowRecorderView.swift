import SwiftUI
import WebKit

struct FlowRecorderView: View {
    @State private var vm = FlowRecorderViewModel()
    @State private var showURLInput: Bool = true


    var body: some View {
        VStack(spacing: 0) {
            headerBar
            if showURLInput && !vm.isRecording && !vm.isPlaying {
                urlInputBar
            }
            webViewArea
            recordingControls
            statsBar
        }
        .background(Color(.systemBackground))
        .navigationTitle("Record Flow")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    NavigationLink(value: "savedFlows") {
                        Label("Saved Flows", systemImage: "tray.full.fill")
                    }
                    Button {
                        vm.validateFingerprint()
                    } label: {
                        Label("Check Fingerprint", systemImage: "fingerprint")
                    }
                    Button {
                        showURLInput.toggle()
                    } label: {
                        Label(showURLInput ? "Hide URL Bar" : "Show URL Bar", systemImage: "link")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
        }
        .sheet(isPresented: $vm.showSaveSheet) {
            saveFlowSheet
        }
        .sheet(isPresented: $vm.showPlaybackSheet) {
            playbackConfigSheet
        }
        .navigationDestination(for: String.self) { destination in
            if destination == "savedFlows" {
                SavedFlowsView(vm: vm)
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(vm.isRecording ? .red : vm.isPlaying ? .orange : .green)
                    .frame(width: 8, height: 8)
                    .shadow(color: vm.isRecording ? .red.opacity(0.6) : .clear, radius: 4)

                Text(vm.isRecording ? "REC" : vm.isPlaying ? "PLAY" : "IDLE")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(vm.isRecording ? .red : vm.isPlaying ? .orange : .secondary)
            }

            Spacer()

            if vm.isRecording {
                Text(vm.formattedDuration)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.red)
                    .monospacedDigit()
            }

            if vm.isPlaying {
                HStack(spacing: 4) {
                    ProgressView(value: vm.playbackProgress)
                        .frame(width: 60)
                        .tint(.orange)
                    Text("\(vm.playbackActionIndex)/\(vm.playbackTotalActions)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            if vm.isTestingAction {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("TESTING")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(.purple)
                }
            }

            HStack(spacing: 4) {
                Image(systemName: "fingerprint")
                    .font(.system(size: 10, weight: .semibold))
                Text(vm.fingerprintScore)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(.cyan)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.cyan.opacity(0.1))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    private var urlInputBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                TextField("Enter URL", text: $vm.targetURL)
                    .font(.system(size: 13, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)

                if !vm.targetURL.isEmpty {
                    Button {
                        vm.targetURL = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }

                Menu {
                    ForEach(vm.allAvailableURLs, id: \.self) { url in
                        Button {
                            vm.targetURL = url
                        } label: {
                            Text(url)
                                .lineLimit(1)
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemBackground))
            .clipShape(.rect(cornerRadius: 8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var webViewArea: some View {
        if let url = URL(string: vm.targetURL), url.scheme != nil {
            FlowRecorderWebView(
                url: url,
                isRecording: vm.isRecording,
                onActionsReceived: { actions in
                    vm.appendActions(actions)
                },
                onPageLoaded: { title in
                    vm.handlePageLoaded(title)
                },
                webViewRef: { webView in
                    vm.activeWebView = webView
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "globe.badge.chevron.backward")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Enter a valid URL above")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.secondarySystemBackground))
        }
    }

    private var recordingControls: some View {
        HStack(spacing: 12) {
            if vm.isRecording {
                Button {
                    vm.stopRecording()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12))
                        Text("STOP")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.red)
                    .clipShape(Capsule())
                }
                .sensoryFeedback(.impact(weight: .heavy), trigger: vm.isRecording)
            } else if vm.isPlaying {
                Button {
                    vm.cancelPlayback()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12))
                        Text("CANCEL")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.orange)
                    .clipShape(Capsule())
                }
            } else {
                Button {
                    vm.startRecording()
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.red)
                            .frame(width: 10, height: 10)
                        Text("RECORD")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(Capsule())
                }
                .sensoryFeedback(.impact(weight: .medium), trigger: vm.isRecording)

                if !vm.savedFlows.isEmpty {
                    Menu {
                        ForEach(vm.savedFlows) { flow in
                            Button {
                                vm.selectFlowForPlayback(flow)
                            } label: {
                                Label("\(flow.name) (\(flow.actionCount))", systemImage: "play.fill")
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12))
                            Text("PLAY")
                                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
    }

    private var statsBar: some View {
        VStack(spacing: 4) {
            if !vm.statusMessage.isEmpty {
                Text(vm.statusMessage)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let error = vm.lastError {
                Text(error)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            HStack(spacing: 16) {
                statPill(icon: "cursorarrow.motionlines", label: "Move", value: "\(vm.mouseMovements)")
                statPill(icon: "hand.tap.fill", label: "Click", value: "\(vm.clicks)")
                statPill(icon: "keyboard.fill", label: "Keys", value: "\(vm.keystrokes)")
                statPill(icon: "scroll.fill", label: "Scroll", value: "\(vm.scrollEvents)")
                statPill(icon: "number", label: "Total", value: "\(vm.currentActionCount)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
    }

    private func statPill(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(.tertiary)
        }
    }

    private var saveFlowSheet: some View {
        NavigationStack {
            Form {
                Section("Flow Name") {
                    TextField("e.g. JoePoint Login", text: $vm.flowName)
                }

                Section("Recording Summary") {
                    LabeledContent("Actions", value: "\(vm.currentActionCount)")
                    LabeledContent("Duration", value: vm.formattedDuration)
                    LabeledContent("Mouse Movements", value: "\(vm.mouseMovements)")
                    LabeledContent("Clicks", value: "\(vm.clicks)")
                    LabeledContent("Keystrokes", value: "\(vm.keystrokes)")
                    LabeledContent("Scroll Events", value: "\(vm.scrollEvents)")
                }

                if !vm.detectedTextboxes.isEmpty {
                    Section("Detected Text Fields") {
                        ForEach(vm.detectedTextboxes, id: \.self) { label in
                            HStack {
                                Image(systemName: "textformat.abc")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.blue)
                                Text(label)
                                    .font(.system(size: 13, design: .monospaced))
                            }
                        }
                    }
                }

                if vm.isRecordingAfterPlay, let flow = vm.selectedFlow {
                    Section {
                        Button {
                            vm.mergeRecordedActionsIntoFlow(flow, fromStep: vm.playFromStepIndex)
                            vm.showSaveSheet = false
                        } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.merge")
                                Text("Merge into '\(flow.name)' from step \(vm.playFromStepIndex)")
                            }
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                        }
                    }
                }

                Section {
                    Button {
                        vm.saveCurrentFlow()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down.fill")
                            Text("Save as New Flow")
                        }
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                    }
                }
            }
            .navigationTitle("Save Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        vm.showSaveSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var playbackConfigSheet: some View {
        NavigationStack {
            Form {
                if let flow = vm.selectedFlow {
                    Section("Flow: \(flow.name)") {
                        LabeledContent("Actions", value: "\(flow.actionCount)")
                        LabeledContent("Duration", value: flow.formattedDuration)
                        LabeledContent("URL") {
                            Text(flow.url)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Section("Playback Options") {
                        Stepper("Start from step: \(vm.playFromStepIndex)", value: $vm.playFromStepIndex, in: 0...max(0, flow.actions.count - 1))

                        Toggle("Record after playback", isOn: $vm.recordAfterPlayback)
                            .tint(.red)

                        if vm.playFromStepIndex > 0 {
                            let actionAtStep = flow.actions[min(vm.playFromStepIndex, flow.actions.count - 1)]
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Step \(vm.playFromStepIndex): \(actionAtStep.type.rawValue)")
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    if let pos = actionAtStep.mousePosition {
                                        Text("(\(Int(pos.x)),\(Int(pos.y)))")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    if !flow.textboxMappings.isEmpty {
                        Section("Fill Text Fields") {
                            ForEach(flow.textboxMappings) { mapping in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(mapping.label)
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.blue)
                                    TextField("Enter value for \(mapping.label)", text: Binding(
                                        get: { vm.textboxValues[mapping.placeholderKey] ?? "" },
                                        set: { vm.textboxValues[mapping.placeholderKey] = $0 }
                                    ))
                                    .font(.system(size: 14))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    if !mapping.originalText.isEmpty {
                                        Text("Original: \(mapping.originalText)")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    }

                    Section {
                        Button {
                            vm.playSelectedFlow()
                        } label: {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Start Playback")
                            }
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                        }
                    }
                }
            }
            .navigationTitle("Playback Config")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        vm.showPlaybackSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
    }
}

