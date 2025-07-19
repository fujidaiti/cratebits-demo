# CratebitsDemo 開発Tips

このファイルには、開発中に発見した重要な技術的な知見とベストプラクティスを記録します。

## 目次
- [音声再生](#音声再生)
- [SwiftUI + Concurrency](#swiftui--concurrency)
- [クロスプラットフォーム対応](#クロスプラットフォーム対応)
- [MusicKit](#musickit)
- [デバッグ手法](#デバッグ手法)

---

## 音声再生

### AVAudioSession設定の重要性

**問題**: AVPlayerで音声が再生されない
**原因**: AVAudioSessionが未設定
**解決**: アプリ起動時にAVAudioSessionを適切に設定

```swift
// CratebitsDemoApp.swift
private func setupAudioSession() {
    #if os(iOS)
    do {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP])
        try audioSession.setActive(true)
    } catch {
        print("Failed to setup audio session: \(error)")
    }
    #endif
}
```

**重要ポイント**:
- **`.playback`カテゴリ**: 音楽再生専用、他アプリ音声を一時停止
- **`.ambient`カテゴリ**: 他アプリと混合、音量が小さくなる場合あり
- **Bluetoothオプション**: ワイヤレスヘッドフォン対応
- **macOSでは不要**: AVAudioSessionはiOS専用

### MusicKit vs AVPlayer の違い

| 機能 | MusicKit (ApplicationMusicPlayer) | AVPlayer |
|------|----------------------------------|----------|
| AVAudioSession | 自動設定 | 手動設定必要 |
| 用途 | Apple Music楽曲のフル再生 | プレビュー、カスタム音源 |
| サブスクリプション | 必要 | 不要（プレビューURL） |

---

## SwiftUI + Concurrency

### @Published プロパティの背景スレッド警告

**問題**: "Publishing changes from background threads is not allowed"
**原因**: async関数内で@Publishedプロパティを直接更新
**解決**: クラス全体に`@MainActor`を適用

```swift
// ❌ 個別対応（冗長）
func updateData() async {
    await MainActor.run {
        self.isLoading = true
    }
}

// ✅ クラス全体対応（推奨）
@MainActor
class MyService: ObservableObject {
    @Published var isLoading = false
    
    func updateData() async {
        isLoading = true  // 自動的にメインスレッドで実行
    }
}
```

**ベストプラクティス**:
- UI関連のObservableObjectクラスには`@MainActor`を適用
- レガシーな`DispatchQueue.main.async`は避ける
- Swift Concurrencyの現代的なアプローチを採用

---

## クロスプラットフォーム対応

### iOS/macOS 固有機能の分岐

多くのSwiftUI機能がプラットフォーム固有のため、適切な分岐が必要：

```swift
// Navigation Bar (iOS専用)
#if os(iOS)
.navigationBarTitleDisplayMode(.large)
#endif

// Toolbar配置
#if os(iOS)
ToolbarItem(placement: .navigationBarTrailing) { ... }
#else
ToolbarItem(placement: .primaryAction) { ... }
#endif

// TabView スタイル (TikTok風ページング)
#if os(iOS)
.tabViewStyle(.page(indexDisplayMode: .never))
#endif

// UIApplication (iOS専用)
#if os(iOS)
import UIKit
// UIApplication.openSettingsURLString など
#endif
```

**注意が必要な機能**:
- `AVAudioSession` (iOS専用)
- `UIApplication` (iOS専用)
- `.navigationBarTitleDisplayMode` (iOS専用)
- `.page` TabViewStyle (iOS専用)

---

## MusicKit

### プレビューURL取得のベストプラクティス

```swift
// Song/Trackからプレビューを取得
guard let previewAssets = song.previewAssets, !previewAssets.isEmpty else {
    // プレビューが利用できない場合の処理
    return
}

guard let previewURL = previewAssets.first?.url else {
    // URLが取得できない場合の処理
    return
}
```

**重要な点**:
- `previewAssets`は配列（複数品質が含まれる可能性）
- プレビューが存在しない楽曲もある
- Developer Token が必要（ユーザーログインは不要）

### アルバム楽曲取得の正しい方法

**❌ 非効率な方法（検索ベース）**:
```swift
// 検索APIを使った回りくどいアプローチ
let searchRequest = MusicCatalogSearchRequest(term: albumName, types: [Song.self])
let response = try await searchRequest.response()
let filteredSongs = response.songs.filter { /* 複雑なフィルタリング */ }
```

**✅ 効率的な方法（IDベース）**:
```swift
// アルバムIDから直接楽曲を取得
let albumRequest = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: MusicItemID(albumID))
let albumResponse = try await albumRequest.response()
let detailedAlbum = try await albumData.with([.tracks])

// アルバムの実際の楽曲にアクセス
if let tracks = detailedAlbum.tracks {
    for track in tracks {
        print(track.title) // 正確な楽曲名
    }
}
```

**重要な知見**:
- **`.with([.tracks])`**: アルバムオブジェクトに楽曲情報を含める
- **1回のAPIコール**: 検索+フィルタリングより効率的
- **正確性**: アルバムIDでの確実な関連付け
- **Apple公式パターン**: UsingMusicKitToIntegrateWithAppleMusicサンプルと同じアプローチ

### よくある間違いパターン

1. **検索に頼りすぎ**: IDがあるなら直接取得が基本
2. **関連付け判定の複雑化**: `song.albums?.contains`より`.with([.tracks])`
3. **フォールバック不備**: API失敗時の適切な代替処理
4. **楽曲名の汚染**: "Album Name - Track 1"形式ではなく純粋な楽曲名を取得

### アルバム・アーティストプレビューの実装知見

**問題**: アルバム・アーティストのプレビューが再生されない
**根本原因**: `MusicPlayerService.playPreviewInstantly()`がトラック以外を処理していなかった

**解決アプローチ**:
```swift
// アルバム/アーティストの場合、最初のピックアップ楽曲を再生
if (item.type == .album || item.type == .artist), 
   let pickedTracks = item.pickedTracks, 
   !pickedTracks.isEmpty {
    print("[Preview Debug] Playing first picked track for \(item.type.displayName): \(item.name)")
    await playPreviewInstantly(for: pickedTracks[0])
    return
}
```

**重要な設計パターン**:
1. **再帰的な処理**: アルバム→ピックアップ楽曲[0]→再度`playPreviewInstantly()`呼び出し
2. **型チェックの重要性**: `item.type == .track`でガードしてからプレビュー処理
3. **ピックアップ楽曲の活用**: アルバム/アーティストは代表楽曲でプレビュー

**つまずきポイント**:
- アルバム/アーティストの場合の処理が完全に欠落していた
- `playPreviewInstantly()`メソッドがトラック専用の実装になっていた
- `pickedTracks`が設定されていても、それを活用する仕組みがなかった

**教訓**:
- UIで表示される全てのアイテムタイプに対応した処理が必要
- プレビュー機能は楽曲レベルでの実装が基本
- アルバム/アーティストは代表楽曲を通じてプレビューを提供する設計が有効

---

## デバッグ手法

### AVPlayer デバッグの包括的アプローチ

音声再生問題の診断には複数の監視ポイントが重要：

```swift
// 状態監視
player.addObserver(self, forKeyPath: "status", options: [.new], context: nil)
player.addObserver(self, forKeyPath: "error", options: [.new], context: nil)
player.addObserver(self, forKeyPath: "rate", options: [.new], context: nil)

// デバッグ情報出力
print("AVPlayer status: \(player.status.rawValue)")
print("AVPlayer rate: \(player.rate)")  // 0=停止, 1=通常再生
print("Volume: \(player.volume)")

// 遅延チェック
DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
    // 1秒後の状態確認
}
```

### AVPlayerオブザーバー管理のつまずきポイント

**ランタイムエラー**: `NSRangeException` - "Cannot remove an observer for the key path 'status' from AVPlayer because it is not registered as an observer"

**根本原因**: 
1. `PreviewCacheManager`で作成されたキャッシュプレイヤー
2. `MusicPlayerService`で作成された一時プレイヤー
両方で同じプレイヤーインスタンスのオブザーバー管理が重複

**解決策**:
```swift
// プレイヤーの作成元を判別するフラグ
private var isUsingCachedPlayer = false

// オブザーバー削除時の分岐
if !isUsingCachedPlayer {
    player.removeObserver(self, forKeyPath: "status")
    player.removeObserver(self, forKeyPath: "error")
    player.removeObserver(self, forKeyPath: "rate")
}
```

**重要な設計原則**:
1. **責任の明確化**: オブザーバーの追加・削除は同じクラスが担当
2. **フラグ管理**: プレイヤーの所有権を明確にする
3. **ライフサイクル管理**: deinitでの確実なクリーンアップ

**教訓**:
- 複数のクラスでAVPlayerを共有する場合は所有権管理が重要
- オブザーバーパターンでは「誰が追加して誰が削除するか」を明確にする
- キャッシュ機能導入時は既存のリソース管理パターンとの整合性を確認

### URL有効性チェック

プレビューURLが取得できても、実際にアクセス可能か確認：

```swift
let (_, response) = try await URLSession.shared.data(from: url)
if let httpResponse = response as? HTTPURLResponse {
    print("HTTP Status: \(httpResponse.statusCode)")
}
```

---

---

## Apple Music ライブラリ操作

### MusicLibrary.add() のプラットフォーム制限

**重要な発見**: `MusicLibrary.shared.add()` はiOS専用でmacOSでは利用不可

```swift
#if os(iOS)
try await MusicLibrary.shared.add(song)
#else
print("Adding to library is not supported on macOS")
#endif
```

**プラットフォーム固有の機能**:
- **iOS**: フル機能（追加・削除・検索）
- **macOS**: 読み取り専用（ライブラリ検索のみ）

### ライブラリ操作のベストプラクティス

```swift
// 1. 認証状態の確認
let status = await MusicAuthorization.request()
guard status == .authorized else { return false }

// 2. アイテム取得
let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: itemID)
let response = try await request.response()

// 3. プラットフォーム分岐でライブラリ操作
#if os(iOS)
try await MusicLibrary.shared.add(song)
#endif
```

**注意点**:
- アーティストは直接ライブラリ追加不可（楽曲単位で追加）
- macOSでは `MusicLibrary` の削除機能も未対応
- 認証エラーの適切なハンドリングが重要

### Apple Music認証とライブラリ操作のつまずきポイント

**コンパイルエラー**: `'add' is unavailable in macOS`

**根本原因**: MusicKitの`MusicLibrary.shared.add()`メソッドがiOS専用

**解決策**:
```swift
#if os(iOS)
try await MusicLibrary.shared.add(song)
#else
print("Adding to library is not supported on macOS")
return false
#endif
```

**発見した制限事項**:
- **iOS**: フル機能（追加・削除・検索）
- **macOS**: 読み取り専用（ライブラリ検索のみ）
- **watchOS/tvOS**: さらに機能制限の可能性

**クロスプラットフォーム対応のベストプラクティス**:
1. 機能実装前にプラットフォーム制限を調査
2. `#if os()` ディレクティブで適切に分岐
3. 制限がある場合は代替UXを提供（グレースフルデグラデーション）
4. ユーザーに分かりやすいメッセージを表示

**教訓**:
- Appleのフレームワークはプラットフォーム固有の制限が多い
- 特にユーザーデータに関わる機能（ライブラリ、カメラ、位置情報等）は要注意
- クロスプラットフォーム開発では各OSの機能差を前提とした設計が重要

---

## 今後の追加予定

- [ ] パフォーマンス最適化手法
- [ ] エラーハンドリング戦略
- [ ] テスト手法

---

*最終更新: 2025-07-19*