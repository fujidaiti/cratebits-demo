# Cratebits 実装状況レポート

## 概要

Flutter版QratemateをSwiftUI版Cratebitsに移植したプロジェクトの実装状況をまとめたドキュメントです。

**実装完了率：約85%**

## プロジェクト構造

```
CratebitsDemo/
├── CratebitsDemoApp.swift           # アプリエントリーポイント ✅
├── Models/
│   ├── ListenLaterItem.swift        # Listen Laterデータモデル ✅
│   └── MusicEvaluation.swift        # 評価データモデル ✅
├── Services/
│   ├── MusicAuthService.swift       # MusicKit認証 ✅
│   ├── MusicPlayerService.swift     # 音楽再生・プレビュー ✅
│   ├── ShareHandlingService.swift   # 共有機能 ✅
│   └── PlaylistGenerationService.swift # プレイリスト生成 ✅
├── Storage/
│   └── UserDefaultsStorage.swift    # UserDefaults永続化（ListenNowキュー含む） ✅
├── Views/
│   ├── ContentView.swift            # メインTabView ✅
│   ├── WelcomeView.swift            # 認証画面 ✅
│   ├── ListenLaterView.swift        # Listen Later画面 ✅
│   ├── ListenNowView.swift          # Listen Now画面（TikTok風UI） ✅
│   ├── SettingsView.swift           # 設定画面 ✅
│   ├── EvaluationView.swift         # 評価画面 ✅
│   └── Components/
│       └── ToastView.swift          # トースト通知システム ✅
└── Extensions/
    └── (未作成)
```

## 機能別実装状況

### ✅ 完全実装済み

#### 1. 基本アーキテクチャ
- **MusicKit認証システム**
  - `MusicAuthService.swift`でMusicKit認証を管理
  - `WelcomeView.swift`で認証UI提供
  - 認証状態の永続化と自動チェック
  
- **TabView構造**
  - Listen Now / Listen Later / Settings の3タブ
  - 各タブ間のナビゲーション
  - 環境変数による状態共有

- **データ永続化**
  - `UserDefaultsStorage.swift`でJSONベースの永続化
  - Listen Laterアイテムと評価履歴の保存
  - App Group対応（共有機能用）

#### 2. Listen Later機能
- **アイテム管理**
  - 曲/アルバム/アーティストの統合リスト表示
  - タイプ別フィルタリング（セグメントピッカー）
  - 検索機能（リアルタイム）
  - スワイプアクションによる削除

- **アイテム追加**
  - 手動追加機能（AddItemView）
  - Apple Music URLからの自動解析・追加
  - 重複チェック機能

- **UI/UX**
  - 標準的なList表示
  - アイテム種別アイコン・色分け
  - 空状態の適切な表示

#### 3. Listen Now機能（完全実装）
- **TikTok風UI**
  - 縦スクロールによるページング表示
  - 全画面表示（タブバー考慮）
  - スムーズなスクロールアニメーション

- **プレイリスト生成**
  - Listen Laterアイテムからのランダム選出
  - アルバム/アーティストからの楽曲展開
  - MusicKit `.with([.tracks])` パターンによる効率的なAPI使用

- **ピックアップ楽曲カルーセル**
  - アルバム/アーティスト内での横スクロールカルーセル
  - 隣接アイテムが見える表示
  - ScrollViewベースのスナップ機能

- **音楽再生・プレビュー**
  - ApplicationMusicPlayer（フル再生）
  - AVPlayer（30秒プレビュー）
  - プレビューモードの自動停止
  - 再生状態の詳細表示

- **キュー管理**
  - UserDefaultsでの永続化
  - 明示的な新キュー生成（自動生成停止）
  - アプリ再起動時の状態復元

- **トースト通知**
  - ユーザーアクションのフィードバック
  - 成功/エラー/警告/情報の4タイプ
  - 自動消去機能

#### 4. 評価機能（UI部分）
- **評価システム**
  - 3段階評価（Like/Not For Me/Listen Again Later）
  - 評価UI（EvaluationView）
  - 評価履歴の永続化
  - 評価状態の視覚表示

- **評価インターフェース**
  - Listen Laterアイテムから評価画面への遷移
  - Listen Now検索結果からの評価
  - 既存評価の表示・更新

#### 5. 設定機能
- **設定画面**
  - Apple Music認証状態表示
  - 統計情報（アイテム数、評価数）
  - データクリア機能
  - 共有アイテム同期機能

#### 6. 共有機能（Apple Music版特有）
- **Share Extension対応**
  - Apple Music URL解析機能
  - App Groupを使用したデータ共有
  - フォアグラウンド復帰時の自動同期

### ⚠️ 部分実装（改善が必要）

#### 1. 評価機能のアクション連携
**現在の実装：**
- 評価の記録・表示

**未実装部分：**
- Like評価 → Apple Musicライブラリ保存
- Not For Me評価 → Listen Laterから自動削除
- Listen Again Later評価 → 適切な処理

### ❌ 未実装（意図的に除外）

#### Spotify特有の機能
- Spotifyプレイリストとの同期
- Playlist Settings画面
- 複数のSpotifyプレイリスト管理
- Authorization Code with PKCEフロー

## 主要な実装ファイル詳細

### Models/ListenLaterItem.swift
```swift
enum ItemType: String, CaseIterable, Codable {
    case track, album, artist
}

struct ListenLaterItem: Identifiable, Codable {
    let id: String
    let type: ItemType
    let name: String
    let artist: String
    let dateAdded: Date
    let appleMusicID: String?
    
    // MusicKitとの連携用イニシャライザ
    init(from track: Track)
    init(from album: Album)
    init(from artist: Artist)
}
```

### Services/MusicAuthService.swift
```swift
class MusicAuthService: ObservableObject {
    @Published var authorizationStatus: MusicAuthorization.Status
    @Published var isAuthorized: Bool
    
    func requestAuthorization() async
    func checkAuthorizationStatus()
}
```

### Services/MusicPlayerService.swift
```swift
class MusicPlayerService: ObservableObject {
    @Published var isPlaying: Bool
    @Published var currentTrack: String?
    @Published var playbackStatus: String
    
    func playTrack(_ track: Track) async
    func playAlbum(_ album: Album) async
    func pause() / stop() / resume() async
}
```

### Storage/UserDefaultsStorage.swift
```swift
class UserDefaultsStorage: ObservableObject {
    @Published var items: [ListenLaterItem]
    @Published var evaluations: [MusicEvaluation]
    @Published var listenNowQueue: [ListenLaterItem]
    
    // CRUD操作
    func addItem(_ item: ListenLaterItem)
    func removeItem(id: String)
    func addEvaluation(_ evaluation: MusicEvaluation)
    
    // ListenNowキュー管理
    func saveListenNowQueue(_ queue: [ListenLaterItem])
    func clearListenNowQueue()
    
    // 共有機能
    func syncSharedItems()
    func clearAllData()
}
```

## 次に実装すべき機能（優先度順）

### 🔥 高優先度

#### 1. 評価機能のアクション連携
**ファイル：** `Views/ListenNowView.swift`の`handleEvaluation`関数拡張

**実装内容：**
```swift
// Like評価のアクション
case .like:
    // Apple Musicライブラリに保存
    try await MusicLibrary.shared.add(song, to: .songs)
    // Listen Laterから削除
    storage.removeItem(id: item.id)

// Not For Me評価のアクション  
case .notForMe:
    // Listen Laterから削除
    storage.removeItem(id: item.id)
```

### 🔶 中優先度

#### 2. 検索機能の復活
**実装内容：**
- Listen Now内での音楽検索機能
- 検索結果からのListen Later保存
- 検索結果からの直接再生

#### 3. UI/UX改善
**実装内容：**
- ダークモード対応
- アクセシビリティ向上
- より詳細な楽曲情報表示

### 🔷 低優先度

#### 4. 高度なプレイリスト生成
**実装内容：**
- ジャンル・気分ベースの選曲
- リスニング履歴を考慮したアルゴリズム
- 時間帯に応じた楽曲選出

## 技術的な課題と解決策

### 1. MusicKit制限事項
- **問題：** 物理デバイスでのみ動作
- **解決策：** 開発時はシミュレーター用のモック実装を併用

### 2. Apple Music サブスクリプション
- **問題：** Apple Music未加入ユーザーの制限
- **解決策：** プレビュー機能とサブスクリプション案内の適切な表示

### 3. パフォーマンス最適化
- **問題：** 大量データでの動作速度
- **解決策：** 遅延読み込み、ページネーション、画像キャッシュ

## 最新の実装成果（2025年7月19日）

### 完了した主要機能

#### 1. Listen Now TikTok風UI
- ✅ 縦スクロールページング実装
- ✅ 全画面表示（SafeArea考慮）
- ✅ スムーズなスクロールアニメーション（LazyVStack → VStack）

#### 2. 横スクロールカルーセル
- ✅ アルバム/アーティスト内ピックアップ楽曲表示
- ✅ 隣接アイテムが見える設計
- ✅ ScrollViewベースのスナップ機能
- ✅ 選択状態の視覚的ハイライト削除

#### 3. プレビュー機能強化
- ✅ AVPlayer使用の30秒プレビュー
- ✅ AVAudioSession適切な設定
- ✅ プレビューモード状態表示
- ✅ 自動停止タイマー機能

#### 4. キュー管理システム
- ✅ UserDefaultsでの永続化
- ✅ 自動再生成の停止（明示的生成のみ）
- ✅ アプリ再起動時の状態復元

#### 5. プレイリスト生成高度化
- ✅ MusicKit効率的API使用（`.with([.tracks])`）
- ✅ 検索ベースから直接IDベース取得に改善
- ✅ アルバム楽曲の正確な名前取得

#### 6. トースト通知システム
- ✅ 4タイプ通知（成功/エラー/警告/情報）
- ✅ 自動消去機能
- ✅ EnvironmentObject統合

### 技術的改善点

#### MusicKit最適化
- **Before**: 検索API → フィルタリング（非効率）
- **After**: 直接ID取得 → `.with([.tracks])`（効率的）

#### UI パフォーマンス
- **Before**: LazyVStack（要素が段階的に表示）
- **After**: VStack（スムーズなアニメーション）

#### 状態管理改善
- **Before**: ビューローカル状態（揮発性）
- **After**: 永続化されたグローバル状態

## 既知の不具合・改善点

### 1. 残存する実装課題
- 評価アクションの Apple Music ライブラリ連携
- Like/Not For Me での Listen Later 自動削除

### 2. エラーハンドリング
- ネットワークエラー時の適切な表示
- Apple Music認証失敗時の復旧処理
- 楽曲再生失敗時の代替処理

### 3. データ整合性
- 共有機能での重複アイテム処理
- 評価データの整合性チェック
- アプリ更新時のデータマイグレーション

## 開発環境・依存関係

### 必須要件
- Xcode 15.0+
- iOS 17.0+
- Apple Developer Program加入
- MusicKit App Service有効化

### 使用フレームワーク
- SwiftUI
- MusicKit
- Combine
- Foundation

### 外部依存関係
- なし（標準フレームワークのみ使用）

## テスト戦略

### 手動テスト項目

#### 1. 基本機能
- [ ] アプリ起動とMusicKit認証フロー
- [ ] タブ切り替え動作
- [ ] アプリのフォアグラウンド/バックグラウンド切り替え

#### 2. Listen Later機能
- [ ] アイテム手動追加（曲/アルバム/アーティスト）
- [ ] フィルタリング機能（タイプ別）
- [ ] 検索機能
- [ ] スワイプ削除
- [ ] 共有機能からの追加

#### 3. Listen Now機能
- [ ] Apple Music検索
- [ ] 検索結果からの再生
- [ ] Listen Laterへの保存
- [ ] 再生制御（再生/一時停止/停止/スキップ）

#### 4. 評価機能
- [ ] 評価画面の表示・操作
- [ ] 評価の保存・更新
- [ ] 評価状態の視覚表示

#### 5. 設定機能
- [ ] 統計情報の正確性
- [ ] データクリア機能
- [ ] 共有アイテム同期

#### 6. エラーハンドリング
- [ ] ネットワーク接続なしでの動作
- [ ] Apple Music未加入時の動作
- [ ] 不正なURLでの共有機能

### デバイステスト
- [ ] iPhone実機での動作確認（MusicKit要件）
- [ ] 異なる画面サイズでのUI確認
- [ ] iOS異なるバージョンでの互換性

## 今後の拡張予定

### 1. 機能拡張
- オフライン機能
- プレイリスト管理
- ソーシャル機能（楽曲共有）

### 2. UI/UX改善
- ダークモード対応
- アクセシビリティ向上
- アニメーション追加

### 3. パフォーマンス最適化
- Core Data移行
- 画像キャッシュ実装
- バックグラウンド処理最適化

---

*最終更新：2025年7月19日*
*実装完了率：約85%*

## アーキテクチャドキュメント

本プロジェクトの詳細な技術知見については `DEVELOPMENT_TIPS.md` を参照してください：

- MusicKit使用パターンとベストプラクティス
- SwiftUI + Concurrency の実装パターン  
- クロスプラットフォーム対応（iOS/macOS）
- AVAudioSession設定とデバッグ手法
- パフォーマンス最適化技術