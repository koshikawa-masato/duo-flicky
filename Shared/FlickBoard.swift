import SwiftUI

struct FlickBoard: View {
    private static let headerHeight: CGFloat = 40
    private static let rowHeight: CGFloat = 46
    private static let padding: CGFloat = 8
    private static let gap: CGFloat = 5
    static let height = headerHeight + 4 * rowHeight + 4 * gap + 2 * padding

    // How far above the board's top edge flick guides may draw in
    // landscape, where the top row sits flush with the frame. The
    // frame itself never resizes and reserves no margin; whether the
    // overflow actually renders depends on the presentation context
    // (it renders over a full-screen app; it was clipped in one
    // split-with-home-screen case), which the device checks map out.
    private static let landscapeGuideOverflow: CGFloat = 54

    static func innerHeight(landscape: Bool, showsTopGuide: Bool = false) -> CGFloat {
        landscape ? 225 : 286
    }

    // Phase 0 spike: in half placement the candidate panel folds into a
    // one-row header (like portrait), which needs this much extra height
    // in landscape.
    static let spikeHeaderHeight: CGFloat = 46

    static func boardHeight(
        isInner: Bool, isLandscape: Bool, showsTopGuide: Bool, placement: SpikePlacement
    ) -> CGFloat {
        guard isInner else { return height }
        return innerHeight(landscape: isLandscape, showsTopGuide: showsTopGuide)
            + (placement.isHalf && isLandscape ? spikeHeaderHeight : 0)
    }

    let isInner: Bool
    let isLandscape: Bool
    let isComposing: Bool
    let isAlphabet: Bool
    let candidates: [String]
    let highlightedCandidate: String?
    var globe: AnyView? = nil
    var showsTopGuide = false
    var debugText = ""
    var onTopGuideChange: (Bool) -> Void = { _ in }
    var placement: SpikePlacement = .full
    var onPlacementCycle: () -> Void = {}
    let perform: (KeyAction) -> Void

    // Drawing bounds for flick guides. In landscape they extend
    // above the board so the top row's up petal and bubble can float
    // over the app, as the user wants; the frame never moves and no
    // margin is reserved for this.
    private func guideDrawBounds(in size: CGSize) -> CGRect {
        guard isInner && isLandscape else { return CGRect(origin: .zero, size: size) }
        let overflow = Self.landscapeGuideOverflow
        return CGRect(x: 0, y: -overflow, width: size.width, height: size.height + overflow)
    }

    var body: some View {
        Group {
            if isInner {
                innerBoard
            } else {
                outerBoard
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.boardHeight(
            isInner: isInner, isLandscape: isLandscape,
            showsTopGuide: showsTopGuide, placement: placement
        ))
        .overlayPreferenceValue(FlickGuidePreference.self) { guides in
            let needsTopRoom = isInner && isLandscape && guides.contains(where: \.needsTopRoom)
            GeometryReader { geometry in
                if guides.contains(where: \.isHeld) {
                    Color(uiColor: .systemBackground).opacity(0.48)
                }
                ForEach(guides) { guide in
                    FlickGuide(
                        guide: guide, keyFrame: geometry[guide.anchor],
                        bounds: guideDrawBounds(in: geometry.size)
                    )
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: needsTopRoom, initial: true) { _, needed in
                onTopGuideChange(needed)
            }
        }
        .onDisappear { onTopGuideChange(false) }
        .overlay(alignment: .topLeading) {
            // Diagnostic readout (build 7, temporary).
            if !debugText.isEmpty {
                Text(debugText)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.red)
                    .padding(2)
                    .background(.black.opacity(0.55))
                    .allowsHitTesting(false)
            }
        }
    }

    private var innerBoard: some View {
        GeometryReader { geometry in
            let top: CGFloat = isLandscape ? 15 : 7
            let horizontalInset: CGFloat = isLandscape ? 7 : 17
            let bottom: CGFloat = isLandscape ? 0 : 4
            let height = Self.boardHeight(
                isInner: true, isLandscape: isLandscape,
                showsTopGuide: showsTopGuide, placement: placement
            )
            // Half placement folds the candidates into a header row in
            // both orientations, like the portrait layout already does.
            let header: CGFloat = placement.isHalf || !isLandscape ? Self.spikeHeaderHeight : 0
            let rowHeight = (height - top - bottom - header - 3 * Self.gap) / 4
            let fullWidth = max(0, geometry.size.width - 2 * horizontalInset)
            // Split View is 50/50 with a ~13pt divider between the panes.
            let width = placement.isHalf ? max(0, (fullWidth - 13) / 2) : fullWidth
            let keyWidth = placement.isHalf
                ? max(0, (width - 4 * Self.gap) / 5)
                : (isLandscape
                    ? max(0, (width - 5 * Self.gap) / 9.2)
                    : max(0, (width - 4 * Self.gap) / 5))

            // The side without keys gets no rendered surface at all
            // (a plain Spacer), which is the point of the spike: whether
            // the app underneath shows and receives touches there is
            // exactly what the real-device check has to answer.
            HStack(spacing: 0) {
                if placement == .rightHalf { Spacer(minLength: 0) }
                VStack(spacing: 0) {
                    if header > 0 {
                        candidateRow(candidates[...])
                            .frame(height: header)
                    }
                    HStack(spacing: Self.gap) {
                        controls(rowHeight: rowHeight)
                            .frame(width: keyWidth)
                        kanaKeys(rowHeight: rowHeight)
                            .frame(width: 3 * keyWidth + 2 * Self.gap)
                        if isLandscape && !placement.isHalf {
                            candidatePanel(rowHeight: rowHeight)
                                .frame(maxWidth: .infinity)
                        }
                        utilityKeys(rowHeight: rowHeight)
                            .frame(width: keyWidth)
                    }
                    .frame(height: height - top - bottom - header)
                }
                .frame(width: placement.isHalf ? width + 2 * horizontalInset : nil)
                .padding(.horizontal, horizontalInset)
                .padding(.top, top)
                if placement == .leftHalf { Spacer(minLength: 0) }
            }
            .frame(maxWidth: .infinity, alignment: placement == .rightHalf ? .trailing : .leading)
        }
    }

    private func utilityKeys(rowHeight: CGFloat) -> some View {
        VStack(spacing: Self.gap) {
            actionKey("カーソルを右へ", symbol: "arrow.right", action: .move(1))
                .frame(height: rowHeight)
            actionKey("入力を戻す", symbol: "arrow.counterclockwise", action: .undo)
                .frame(height: rowHeight)
            actionKey(isAlphabet ? "かな" : "ABC", action: .toggleAlphabet)
                .frame(height: rowHeight)
            HStack(spacing: Self.gap) {
                if let globe {
                    globe
                        .frame(maxWidth: .infinity)
                        .frame(height: rowHeight)
                        .background(keyColor, in: .rect(cornerRadius: 10))
                } else {
                    Color.clear.frame(height: rowHeight)
                }
                // Phase 0 spike: cycle 全幅 → 左半 → 右半 → 全幅.
                Button {
                    onPlacementCycle()
                } label: {
                    Text(placement.label)
                        .font(.caption2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(keyColor, in: .rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .frame(height: rowHeight)
                .accessibilityLabel("キーボード配置を切り替え、現在は\(placement.label)")
            }
        }
    }

    private var outerBoard: some View {
        VStack(spacing: Self.gap) {
            HStack(spacing: Self.gap) {
                if let globe {
                    globe.frame(width: 40, height: Self.headerHeight)
                }
                if candidates.isEmpty {
                    Spacer()
                } else {
                    candidateRow(candidates[...])
                        .frame(maxWidth: .infinity)
                }
                actionKey("カーソルを左へ", symbol: "chevron.left", action: .move(-1))
                    .frame(width: 44)
                actionKey("カーソルを右へ", symbol: "chevron.right", action: .move(1))
                    .frame(width: 44)
            }
            .frame(height: Self.headerHeight)

            HStack(spacing: Self.gap) {
                kanaKeys(rowHeight: Self.rowHeight)
                controls(rowHeight: Self.rowHeight)
                    .frame(width: 66)
            }
        }
        .frame(maxWidth: 360)
        .padding(Self.padding)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private var keyColor: Color {
        Color(uiColor: isInner ? .systemBackground : .tertiarySystemFill)
    }

    private func candidatePanel(rowHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<4) { row in
                let start = min(row * 6, candidates.count)
                let end = min(start + 6, candidates.count)
                candidateRow(candidates[start..<end])
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .bottom) {
                        if row < 3 { Divider() }
                    }
            }
        }
        .frame(height: 4 * rowHeight + 3 * Self.gap)
        .background(keyColor, in: .rect(cornerRadius: 10))
        .clipShape(.rect(cornerRadius: 10))
    }

    private func candidateRow(_ words: ArraySlice<String>) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(words, id: \.self) { word in
                    Button {
                        perform(.chooseCandidate(word))
                    } label: {
                        Text(word)
                            .font(.system(size: 19))
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 8)
                            .frame(minWidth: 38, maxHeight: .infinity)
                            .background(
                                highlightedCandidate == word ? Color.accentColor.opacity(0.2) : .clear
                            )
                    }
                    .buttonStyle(.plain)
                    .id(word)
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func kanaKeys(rowHeight: CGFloat) -> some View {
        let keys = FlickKey.allCases
        return VStack(spacing: Self.gap) {
            ForEach(0..<4) { row in
                HStack(spacing: Self.gap) {
                    ForEach(0..<3) { column in
                        let key = keys[row * 3 + column]
                        if isAlphabet {
                            let outputs = Self.alphabetKeys[row * 3 + column]
                            FlickTile(label: outputs[0], outputs: outputs, showsGuide: false) { direction in
                                let output = direction == .tap
                                    ? String(outputs[0].prefix(1)).lowercased()
                                    : outputs[direction.rawValue]
                                perform(.insert(output))
                            }
                            .frame(height: rowHeight)
                        } else {
                            FlickTile(label: key.label, outputs: key.outputs, isModifier: key == .modifier, isTopRow: row == 0) {
                                input(key, direction: $0)
                            }
                            .frame(height: rowHeight)
                        }
                    }
                }
            }
        }
    }

    private static let alphabetKeys = [
        ["@", "_", "-", "/", "1"], ["ABC", "b", "c", "!", "2"], ["DEF", "e", "f", "?", "3"],
        ["GHI", "h", "i", "+", "4"], ["JKL", "k", "l", "=", "5"], ["MNO", "n", "o", "*", "6"],
        ["PQRS", "q", "r", "s", "7"], ["TUV", "u", "v", "&", "8"], ["WXYZ", "x", "y", "z", "9"],
        ["7", "!", "?", "'", "9"], ["0", "(", ")", "+", "="], [".", ",", ":", ";", "\""]
    ]

    private func controls(rowHeight: CGFloat) -> some View {
        VStack(spacing: Self.gap) {
            actionKey("削除", symbol: "delete.left", action: .delete)
                .frame(height: rowHeight)
            actionKey(
                isComposing ? "次候補" : "空白",
                action: isComposing ? .nextCandidate : .insert(" ")
            )
                .frame(height: rowHeight)
            actionKey(isComposing ? "確定" : "改行", symbol: isComposing ? nil : "return", action: .confirm)
                .frame(height: 2 * rowHeight + Self.gap)
        }
    }

    private func actionKey(_ title: String, symbol: String? = nil, action: KeyAction) -> some View {
        Button {
            perform(action)
        } label: {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                } else {
                    Text(title).font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(keyColor, in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func input(_ key: FlickKey, direction: FlickDirection) {
        if key == .modifier {
            if direction == .tap { perform(.modifyKana) }
        } else if direction == .tap {
            perform(.tapKana(key))
        } else {
            let output = key.outputs[direction.rawValue]
            if !output.isEmpty { perform(.insert(output)) }
        }
    }
}

private struct FlickTile: View {
    let label: String
    let outputs: [String]
    var isModifier = false
    var showsGuide = true
    var isTopRow = false
    let onFlick: (FlickDirection) -> Void

    @State private var drag: CGSize?
    @State private var preview = Preview.waiting
    @State private var releasedFlick: (direction: FlickDirection, id: UUID)?

    private enum Preview {
        case waiting, flick, held
    }

    var body: some View {
        let direction = drag.map(direction(for:)) ?? releasedFlick?.direction ?? .tap
        let output = outputs[direction.rawValue]
        let showGuide = showsGuide && !isModifier && (
            (drag != nil && preview == .held)
            || ((preview == .flick || releasedFlick != nil) && direction != .tap && !output.isEmpty)
        )

        Text(!showsGuide && direction != .tap && !output.isEmpty ? output : label)
            .font(.system(size: label.count > 1 && label != "わ₋" ? 16 : 22, weight: .regular))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                drag != nil ? Color(uiColor: .systemGray3) : Color(uiColor: .systemBackground),
                in: .rect(cornerRadius: 8)
            )
            .overlay {
                FlickTouchSurface(
                    onTrack: { translation in
                        drag = translation
                        if let translation {
                            releasedFlick = nil
                            if preview == .waiting, self.direction(for: translation) != .tap {
                                preview = .flick
                            }
                        } else {
                            preview = .waiting
                        }
                    },
                    onRelease: { translation in
                        let selected = self.direction(for: translation)
                        if showsGuide, !isModifier, preview != .held,
                           selected != .tap, !outputs[selected.rawValue].isEmpty {
                            releasedFlick = (selected, UUID())
                        }
                        onFlick(selected)
                    }
                )
                .accessibilityHidden(true)
            }
            .anchorPreference(key: FlickGuidePreference.self, value: .bounds) { anchor in
                showGuide ? [FlickGuideState(
                    id: label, anchor: anchor, outputs: outputs,
                    selection: direction, isHeld: preview == .held, isTopRow: isTopRow
                )] : []
            }
            .task(id: drag != nil) {
                guard drag != nil, showsGuide, !isModifier else { return }
                do {
                    try await Task.sleep(for: .milliseconds(220))
                    if drag != nil, preview == .waiting { preview = .held }
                } catch {}
            }
            .task(id: releasedFlick?.id) {
                guard let id = releasedFlick?.id else { return }
                do {
                    try await Task.sleep(for: .milliseconds(80))
                    if releasedFlick?.id == id { releasedFlick = nil }
                } catch {}
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isModifier ? "小文字・濁点・半濁点" : label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onFlick(.tap) }
            .accessibilityActions {
                ForEach(Array(FlickDirection.allCases.dropFirst()), id: \.self) { direction in
                    let output = outputs[direction.rawValue]
                    if !output.isEmpty {
                        Button("\(direction.name)へフリックして\(output)") { onFlick(direction) }
                    }
                }
            }
    }

    private func direction(for translation: CGSize) -> FlickDirection {
        FlickDirection(x: translation.width, y: translation.height)
    }
}

private struct FlickGuideState: Identifiable {
    let id: String
    let anchor: Anchor<CGRect>
    let outputs: [String]
    let selection: FlickDirection
    let isHeld: Bool
    let isTopRow: Bool

    var needsTopRoom: Bool { isTopRow && (isHeld || selection == .up) }
}

private struct FlickGuidePreference: PreferenceKey {
    static var defaultValue: [FlickGuideState] { [] }

    static func reduce(value: inout [FlickGuideState], nextValue: () -> [FlickGuideState]) {
        value.append(contentsOf: nextValue())
    }
}

private struct FlickGuide: View {
    let guide: FlickGuideState
    let keyFrame: CGRect
    let bounds: CGRect

    var body: some View {
        if guide.isHeld {
            heldGuide
        } else {
            flickBubble
        }
    }

    private var flickBubble: some View {
        let layout = FlickBubbleLayout(
            key: keyFrame, bounds: bounds, direction: guide.selection
        )
        let body = layout.body
        let fill = Color(uiColor: .systemGray4)

        return ZStack(alignment: .topLeading) {
            Path { path in
                // The pointer faces back toward the originating key, while the
                // body appears on the side selected by the finger movement.
                guard !body.contains(layout.tip) else { return }
                switch guide.selection {
                case .left:
                    path.move(to: CGPoint(x: body.maxX - 3, y: body.minY))
                    path.addLine(to: CGPoint(x: body.maxX - 3, y: body.maxY))
                case .right:
                    path.move(to: CGPoint(x: body.minX + 3, y: body.minY))
                    path.addLine(to: CGPoint(x: body.minX + 3, y: body.maxY))
                case .down:
                    path.move(to: CGPoint(x: body.minX, y: body.minY + 3))
                    path.addLine(to: CGPoint(x: body.maxX, y: body.minY + 3))
                case .tap, .up:
                    path.move(to: CGPoint(x: body.minX, y: body.maxY - 3))
                    path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - 3))
                }
                path.addLine(to: layout.tip)
                path.closeSubpath()
            }
            .fill(fill)

            Text(guide.outputs[guide.selection.rawValue])
                .font(.system(size: min(28, body.height * 0.72)))
                .foregroundStyle(Color.primary)
                .frame(width: body.width, height: body.height)
                .background(fill, in: .rect(cornerRadius: 3))
                .position(x: body.midX, y: body.midY)
        }
    }

    private var heldGuide: some View {
        ForEach(FlickDirection.allCases, id: \.self) { direction in
            let output = guide.outputs[direction.rawValue]
            let rect = frame(for: direction)
            if !output.isEmpty, !rect.isEmpty {
                let isSelected = direction == guide.selection && direction != .tap
                let isHoldingCenter = direction == .tap && guide.selection == .tap
                let fill = isSelected ? UIColor.systemBlue : isHoldingCenter ? .systemGray3 : .systemBackground
                Text(output)
                    .font(.system(size: min(23, rect.height * 0.72)))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .frame(width: rect.width, height: rect.height)
                    .background(
                        Color(uiColor: fill),
                        in: .rect(cornerRadius: 8)
                    )
                    .position(x: rect.midX, y: rect.midY)
            }
        }
    }

    private func frame(for direction: FlickDirection) -> CGRect {
        let offset = offset(for: direction)
        let proposed = keyFrame.offsetBy(
            dx: offset.width * (keyFrame.width + 4),
            dy: offset.height * (keyFrame.height + 4)
        )
        return proposed.intersection(bounds)
    }

    private func offset(for direction: FlickDirection) -> CGSize {
        switch direction {
        case .tap: .zero
        case .left: CGSize(width: -1, height: 0)
        case .up: CGSize(width: 0, height: -1)
        case .right: CGSize(width: 1, height: 0)
        case .down: CGSize(width: 0, height: 1)
        }
    }
}


private struct FlickTouchSurface: UIViewRepresentable {
    let onTrack: (CGSize?) -> Void
    let onRelease: (CGSize) -> Void

    func makeUIView(context: Context) -> Surface { Surface() }

    func updateUIView(_ view: Surface, context: Context) {
        view.onTrack = onTrack
        view.onRelease = onRelease
    }

    final class Surface: UIControl {
        var onTrack: ((CGSize?) -> Void)?
        var onRelease: ((CGSize) -> Void)?
        private var origin: CGPoint = .zero

        override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            origin = touch.location(in: self)
            onTrack?(.zero)
            return true
        }

        override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            onTrack?(translation(of: touch))
            return true
        }

        override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
            if let touch { onRelease?(translation(of: touch)) }
            onTrack?(nil)
        }

        override func cancelTracking(with event: UIEvent?) {
            onTrack?(nil)
        }

        private func translation(of touch: UITouch) -> CGSize {
            let point = touch.location(in: self)
            return CGSize(width: point.x - origin.x, height: point.y - origin.y)
        }
    }
}
