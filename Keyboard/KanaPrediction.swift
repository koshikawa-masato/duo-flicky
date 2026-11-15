import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

@MainActor
final class KanaPrediction {
    private lazy var converter = KanaKanjiConverter.withDefaultDictionary()
    private let options: ConvertRequestOptions = {
        let documents = URL.documentsDirectory
        return ConvertRequestOptions(
            N_best: 18,
            requireJapanesePrediction: true,
            requireEnglishPrediction: false,
            keyboardLanguage: .ja_JP,
            learningType: .nothing,
            memoryDirectoryURL: documents,
            sharedContainerURL: documents,
            textReplacer: .withDefaultEmojiDictionary(),
            specialCandidateProviders: KanaKanjiConverter.defaultSpecialCandidateProviders,
            metadata: .init(versionString: "Duo Flicky")
        )
    }()

    func reset() {
        converter.stopComposition()
    }

    func following(committed: String, reading: String) -> [String] {
        guard let match = fullCandidates(for: reading).first(where: { $0.text == committed }) else { return [] }
        let results = converter.requestPostCompositionPredictionCandidates(leftSideCandidate: match, options: options)
        return Array(results.compactMap { result in
            if case .additional = result.type { return result.text }
            return nil
        }.prefix(24))
    }

    func candidates(for reading: String) -> [String] {
        guard !reading.isEmpty else { return [] }
        var seen = Set<String>()
        let words = fullCandidates(for: reading).map(\.text) + [reading]
        return Array(words.filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(24))
    }

    private func fullCandidates(for reading: String) -> [Candidate] {
        guard !reading.isEmpty else { return [] }

        var composition = ComposingText()
        composition.insertAtCursorPosition(reading, inputStyle: .direct)
        let result = converter.requestCandidates(composition, options: options)
        return result.mainResults.filter { candidate in
            guard candidate.inputable else { return false }
            var remainder = composition
            remainder.prefixComplete(composingCount: candidate.composingCount)
            return remainder.convertTarget.isEmpty
        }
    }
}
