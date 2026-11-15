import Foundation

enum FlickDirection: Int, CaseIterable {
    case tap, left, up, right, down

    init(x: CGFloat, y: CGFloat) {
        guard max(abs(x), abs(y)) >= 18 else {
            self = .tap
            return
        }
        if abs(x) >= abs(y) {
            self = x < 0 ? .left : .right
        } else {
            self = y < 0 ? .up : .down
        }
    }

    var name: String {
        switch self {
        case .tap: "タップ"
        case .left: "左"
        case .up: "上"
        case .right: "右"
        case .down: "下"
        }
    }
}

/// Positions the single-character preview beside the key in the selected direction.
/// The text stays upright; only the location and the edge pointing at the key change.
struct FlickBubbleLayout {
    let body: CGRect
    let tip: CGPoint

    init(key: CGRect, bounds: CGRect, direction: FlickDirection) {
        var body = key.insetBy(dx: -2, dy: -2)
        let tip: CGPoint
        switch direction {
        case .left:
            body.origin.x -= key.width + 4
            tip = CGPoint(x: key.minX + key.width / 3, y: key.midY)
        case .right:
            body.origin.x += key.width + 4
            tip = CGPoint(x: key.maxX - key.width / 3, y: key.midY)
        case .down:
            body.origin.y += key.height + 4
            tip = CGPoint(x: key.midX, y: key.maxY - 8)
        case .tap, .up:
            body.origin.y -= key.height + 4
            tip = CGPoint(x: key.midX, y: key.minY + 8)
        }

        // Keep edge-row previews inside the keyboard extension's drawable area.
        body.size.width = min(body.width, bounds.width)
        body.size.height = min(body.height, bounds.height)
        body.origin.x = min(max(body.minX, bounds.minX), bounds.maxX - body.width)
        body.origin.y = min(max(body.minY, bounds.minY), bounds.maxY - body.height)
        self.body = body
        self.tip = tip
    }
}

enum FlickKey: String, CaseIterable, Codable {
    case a, ka, sa, ta, na, ha, ma, ya, ra, modifier, wa, punctuation

    var outputs: [String] {
        switch self {
        case .a: ["あ", "い", "う", "え", "お"]
        case .ka: ["か", "き", "く", "け", "こ"]
        case .sa: ["さ", "し", "す", "せ", "そ"]
        case .ta: ["た", "ち", "つ", "て", "と"]
        case .na: ["な", "に", "ぬ", "ね", "の"]
        case .ha: ["は", "ひ", "ふ", "へ", "ほ"]
        case .ma: ["ま", "み", "む", "め", "も"]
        case .ya: ["や", "「", "ゆ", "」", "よ"]
        case .ra: ["ら", "り", "る", "れ", "ろ"]
        case .modifier: ["小゛゜", "", "", "", ""]
        case .wa: ["わ", "を", "ん", "ー", "わ"]
        case .punctuation: ["、", "。", "？", "！", "、"]
        }
    }

    var tapChoices: [String] {
        switch self {
        case .ya: ["や", "ゆ", "よ"]
        case .wa, .punctuation: Array(outputs.dropLast())
        default: outputs.filter { !$0.isEmpty }
        }
    }

    var label: String {
        switch self {
        case .wa: "わ₋"
        case .punctuation: "、。?!"
        default: outputs[0]
        }
    }
}

enum KeyAction {
    case insert(String)
    case tapKana(FlickKey)
    case modifyKana
    case delete
    case move(Int)
    case nextCandidate
    case chooseCandidate(String)
    case confirm
    case undo
    case toggleAlphabet
}

enum KanaModifier {
    private static let cycles = [
        "あぁ", "いぃ", "うぅゔ", "えぇ", "おぉ",
        "かが", "きぎ", "くぐ", "けげ", "こご",
        "さざ", "しじ", "すず", "せぜ", "そぞ",
        "ただ", "ちぢ", "つっづ", "てで", "とど",
        "はばぱ", "ひびぴ", "ふぶぷ", "へべぺ", "ほぼぽ",
        "やゃ", "ゆゅ", "よょ", "わゎ"
    ]

    static func next(after character: Character) -> String? {
        for cycle in cycles {
            if let index = cycle.firstIndex(of: character) {
                let next = cycle.index(after: index)
                return String(cycle[next == cycle.endIndex ? cycle.startIndex : next])
            }
        }
        return nil
    }
}

enum DuoDisplay {
    static func isInner(nativeSize: CGSize) -> Bool {
        let shortSide = min(nativeSize.width, nativeSize.height)
        let longSide = max(nativeSize.width, nativeSize.height)
        #if targetEnvironment(simulator)
        // Device Hub also exposes the simulator's larger inner framebuffer.
        if shortSide == 2007 && longSide == 2853 { return true }
        #endif
        return shortSide == 1878 && longSide == 2670
    }
}
