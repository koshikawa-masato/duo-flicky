# Duo Flicky

iPhone Duoの内側画面で、縦持ち・横持ちともにかなフリックを左手で打てるようにするiOS 27.1以降向けのキーボード拡張です。

SwiftUIとUIKitで実装した独立した日本語キーボードです。開発中のため、純正キーボードとの見た目や操作感には差があります。

内側画面ではかな12キーと削除・空白・改行を左側に、候補欄を横持ちでは右側に4段、縦持ちでは上に1段で表示します。候補欄では変換候補をタップして確定できます。「次候補」で候補を切り替え、「確定」で入力します。キーの並びとフリック方向は一般的なかな12キーと同じです。外側画面でDuo Flickyを選んだ場合は中央に配置します。

横持ちでは吹き出し用の上部空白を常設せず、上段の上フリック・長押しガイドを表示する間だけ描画領域を広げます。キーの大きさと画面上の位置を保ち、表示終了後に通常の高さへ戻します。拡張キーボードは自分の領域の上端を越えて描画できないため、純正とは異なり、この間は利用中アプリの表示領域も変わることがあります（[Appleの仕様](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html)）。

## ビルドとインストール

iOS 27.1以降のSDKを含むXcodeと、実機へのインストールに使うApple開発用署名が必要です。

1. このリポジトリをcloneし、Xcodeで `DuoFlicky.xcodeproj` を開きます。Swift Package Managerが依存パッケージを取得します。
2. 実機では `DuoFlicky` と `DuoFlickyKeyboard` の両ターゲットの **Signing & Capabilities** で自分の署名チームを選び、自動署名を有効にします。Bundle Identifierは自分の固有の値に変更し、拡張側をアプリ側の値に `.keyboard` を付けたものにします。
3. `DuoFlicky` スキームと実行先のDuoを選び、Runでインストールします。
4. Duoの設定 → 一般 → キーボード → キーボード → 新しいキーボードを追加から **Duo Flicky** を追加します。
5. 試し入力欄やメモで、地球儀キーから **Duo Flicky** を選びます。

署名情報は含まれていません。手動署名の場合は、必要に応じてビルド設定 `DUO_FLICKY_PROFILE` に自分のプロビジョニングプロファイルを指定してください。

シミュレーター用の署名なしビルドは次のコマンドで実行できます。

```sh
xcodebuild \
  -project DuoFlicky.xcodeproj \
  -scheme DuoFlicky \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Xcodeプロジェクトは同梱しているため、通常は生成作業は不要です。プロジェクトを再生成する場合は [XcodeGen](https://github.com/yonaskolb/XcodeGen) で `project.yml` を使用します。

## 日本語変換

フルアクセスは不要です。変換には [AzooKeyKanaKanjiConverter](https://github.com/azooKey/AzooKeyKanaKanjiConverter) の端末内辞書を使います。候補と順位は純正キーボードと異なります。

依存パッケージのバージョンは `Package.resolved` に固定しています。各依存パッケージと辞書のライセンスは、それぞれの配布元を参照してください。
