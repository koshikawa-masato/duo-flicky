import SwiftUI

@main
struct DuoFlickyApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                SetupView()
                    .navigationTitle("Duo Flicky")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

private struct SetupView: View {
    @State private var testText = ""

    var body: some View {
        Form {
            Section {
                Text("iPhone Duoの内側画面では、縦持ちでも横持ちでも、かなフリックキーを左手側に表示します。")
            }

            Section("キーボードを追加") {
                Text("設定 → 一般 → キーボード → キーボード → 新しいキーボードを追加 → Duo Flicky")
                Text("入力欄で地球儀キーから Duo Flicky を選びます。")
            }

            Section("試し入力") {
                TextField("ここをタップして入力", text: $testText, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
    }
}
