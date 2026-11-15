import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private let model = BoardModel()
    private let prediction = KanaPrediction()
    private var documentID: UUID?
    private var reading = ""
    private var previousReading = ""
    private var candidateIndex: Int?
    private var pendingPrediction: Task<Void, Never>?
    private var tapCycle: (key: FlickKey, index: Int, time: TimeInterval)?
    private var boardHeight: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()

        let board = ExtensionBoard(model: model, controller: self)
        let host = UIHostingController(rootView: board)
        host.sizingOptions = []
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)

        let height = view.heightAnchor.constraint(equalToConstant: FlickBoard.height)
        height.priority = .defaultHigh
        height.isActive = true
        boardHeight = height
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        if let screen = view.window?.windowScene?.screen ?? view.window?.screen {
            let isInner = DuoDisplay.isInner(nativeSize: screen.nativeBounds.size)
            let isLandscape = screen.bounds.width > screen.bounds.height
            if model.isInner != isInner {
                model.isInner = isInner
                if !isInner { model.isAlphabet = false }
            }
            if model.isLandscape != isLandscape { model.isLandscape = isLandscape }
            if !isInner || !isLandscape { model.showsTopGuide = false }
            updateBoardHeight()
        }
        if model.showsGlobe != needsInputModeSwitchKey {
            model.showsGlobe = needsInputModeSwitchKey
        }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        syncDocument()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        setTopGuideVisible(false)
        syncDocument()
        if !reading.isEmpty { finish() }
    }

    func setTopGuideVisible(_ visible: Bool) {
        let visible = visible && model.isInner && model.isLandscape
        guard model.showsTopGuide != visible else { return }
        model.showsTopGuide = visible
        UIView.performWithoutAnimation {
            updateBoardHeight()
            view.layoutIfNeeded()
        }
    }

    private func updateBoardHeight() {
        let height = model.isInner
            ? FlickBoard.innerHeight(landscape: model.isLandscape, showsTopGuide: model.showsTopGuide)
            : FlickBoard.height
        if boardHeight?.constant != height { boardHeight?.constant = height }
    }

    func perform(_ action: KeyAction) {
        syncDocument()
        let proxy = textDocumentProxy

        switch action {
        case .tapKana, .undo: break
        default: tapCycle = nil
        }

        switch action {
        case .tapKana(let key):
            let choices = key.tapChoices
            let now = ProcessInfo.processInfo.systemUptime
            if let cycle = tapCycle, cycle.key == key, now - cycle.time < 0.7, !reading.isEmpty {
                let index = (cycle.index + 1) % choices.count
                changeReading(to: String(reading.dropLast()) + choices[index])
                tapCycle = (key, index, now)
            } else {
                if candidateIndex != nil { finish() }
                changeReading(to: reading + choices[0])
                tapCycle = (key, 0, now)
            }
        case .insert(let text):
            if model.isAlphabet || text == " " || text == "\n" {
                if !reading.isEmpty { finish() }
                proxy.insertText(text)
                model.candidates = []
            } else {
                if candidateIndex != nil { finish() }
                changeReading(to: reading + text)
            }
        case .delete:
            if reading.isEmpty {
                model.candidates = []
                proxy.deleteBackward()
            } else if candidateIndex != nil {
                candidateIndex = nil
                model.highlightedCandidate = nil
                showMarkedText(reading)
            } else {
                changeReading(to: String(reading.dropLast()))
            }
        case .move(let offset):
            if !reading.isEmpty { finish() }
            model.candidates = []
            proxy.adjustTextPosition(byCharacterOffset: offset)
        case .modifyKana:
            guard let previous = reading.last,
                  let replacement = KanaModifier.next(after: previous) else { return }
            changeReading(to: String(reading.dropLast()) + replacement)
        case .nextCandidate:
            if pendingPrediction != nil { updateCandidates(for: reading) }
            guard !model.candidates.isEmpty else { return }
            let index = ((candidateIndex ?? -1) + 1) % model.candidates.count
            candidateIndex = index
            model.highlightedCandidate = model.candidates[index]
            showMarkedText(model.candidates[index])
        case .chooseCandidate(let text):
            if pendingPrediction != nil { updateCandidates(for: reading) }
            guard model.candidates.contains(text) else { return }
            if reading.isEmpty {
                proxy.insertText(text)
                model.candidates = []
            } else {
                showMarkedText(text)
                finish(selected: text, suggestContinuation: true)
            }
        case .confirm:
            if reading.isEmpty {
                proxy.insertText("\n")
            } else {
                finish(suggestContinuation: true)
            }
        case .undo:
            if let cycle = tapCycle, !reading.isEmpty {
                let choices = cycle.key.tapChoices
                let index = (cycle.index + choices.count - 1) % choices.count
                changeReading(to: String(reading.dropLast()) + choices[index])
                tapCycle = (cycle.key, index, ProcessInfo.processInfo.systemUptime)
                return
            }
            guard !reading.isEmpty || !previousReading.isEmpty else { return }
            changeReading(to: previousReading)
        case .toggleAlphabet:
            if !reading.isEmpty { finish() }
            model.candidates = []
            model.isAlphabet.toggle()
        }
    }

    private func syncDocument() {
        let id = textDocumentProxy.documentIdentifier
        if documentID != id {
            documentID = id
            resetComposition()
        }
    }

    private func changeReading(to text: String) {
        previousReading = reading
        reading = text
        candidateIndex = nil
        model.highlightedCandidate = nil
        model.isComposing = !text.isEmpty
        showMarkedText(text)
        pendingPrediction?.cancel()
        pendingPrediction = nil
        guard !text.isEmpty else {
            model.candidates = []
            textDocumentProxy.unmarkText()
            prediction.reset()
            return
        }

        pendingPrediction = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(60))
            } catch {
                return
            }
            self?.updateCandidates(for: text)
        }
    }

    private func updateCandidates(for text: String) {
        pendingPrediction?.cancel()
        pendingPrediction = nil
        guard reading == text else { return }
        model.candidates = prediction.candidates(for: text)
    }

    private func showMarkedText(_ text: String) {
        textDocumentProxy.setMarkedText(
            text, selectedRange: NSRange(location: text.utf16.count, length: 0)
        )
    }

    private func finish(selected: String? = nil, suggestContinuation: Bool = false) {
        let committed = selected ?? model.highlightedCandidate ?? reading
        let nextWords = suggestContinuation ? prediction.following(committed: committed, reading: reading) : []
        textDocumentProxy.unmarkText()
        resetComposition()
        model.candidates = nextWords
    }

    private func resetComposition() {
        pendingPrediction?.cancel()
        pendingPrediction = nil
        tapCycle = nil
        if !reading.isEmpty { prediction.reset() }
        reading = ""
        previousReading = ""
        candidateIndex = nil
        model.highlightedCandidate = nil
        model.isComposing = false
        model.candidates = []
    }
}

@MainActor
@Observable
private final class BoardModel {
    var isInner = false
    var isLandscape = false
    var showsGlobe = false
    var showsTopGuide = false
    var isComposing = false
    var isAlphabet = false
    var candidates: [String] = []
    var highlightedCandidate: String?
}

private struct ExtensionBoard: View {
    let model: BoardModel
    weak var controller: KeyboardViewController?

    var body: some View {
        FlickBoard(
            isInner: model.isInner,
            isLandscape: model.isLandscape,
            isComposing: model.isComposing,
            isAlphabet: model.isAlphabet,
            candidates: model.candidates,
            highlightedCandidate: model.highlightedCandidate,
            globe: model.showsGlobe ? AnyView(GlobeButton(controller: controller)) : nil,
            showsTopGuide: model.showsTopGuide,
            onTopGuideChange: { controller?.setTopGuideVisible($0) },
            perform: { controller?.perform($0) }
        )
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct GlobeButton: UIViewRepresentable {
    weak var controller: KeyboardViewController?

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "globe"), for: .normal)
        button.accessibilityLabel = "キーボードを切り替え"
        if let controller {
            button.addTarget(controller, action: #selector(UIInputViewController.handleInputModeList(from:with:)), for: .allTouchEvents)
        }
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {}
}
