# MusicKit基本的な使い方

このドキュメントは既存コードから抽出したMusicKitの基本的な使い方をまとめています。

## 1. 認証・権限管理

### 現在の権限状態を確認
```swift
let authorizationStatus = MusicAuthorization.currentStatus
```

### 権限をリクエスト
```swift
let musicAuthorizationStatus = await MusicAuthorization.request()
```

### 権限状態の種類
- `.notDetermined`: 未決定
- `.denied`: 拒否
- `.restricted`: 制限あり
- `.authorized`: 許可済み

## 2. カタログ検索API

### 基本的な検索
```swift
var searchRequest = MusicCatalogSearchRequest(term: searchTerm, types: [Album.self])
searchRequest.limit = 5
let searchResponse = try await searchRequest.response()

// 結果の取得
let albums = searchResponse.albums
```

### 検索可能な型
- `Album.self`: アルバム
- `Song.self`: 楽曲
- `Artist.self`: アーティスト
- `Playlist.self`: プレイリスト

## 3. リソース取得API

### ID指定での取得
```swift
let albumsRequest = MusicCatalogResourceRequest<Album>(matching: \.id, memberOf: albumIDs)
let albumsResponse = try await albumsRequest.response()
let albums = albumsResponse.items
```

### 複数ID一括取得の検証結果
- **✅ 一括取得可能**: `MusicCatalogResourceRequest`では複数のIDを配列で指定して一度のAPIコールで取得可能
- **⚠️ 型別制約**: Album、Song、Artistなどは**型ごと**に分けてAPIコールする必要がある
- **性能**: 複数ID指定でのレスポンス時間は効率的
- **部分取得**: 存在しないIDが含まれていても、存在するIDのアイテムは正常に取得される

```swift
// 例：複数アルバムを一括取得
let selectedAlbumIDs: [MusicItemID] = [id1, id2, id3, ...]
let albumsRequest = MusicCatalogResourceRequest<Album>(matching: \.id, memberOf: selectedAlbumIDs)
let albumsResponse = try await albumsRequest.response()
// albumsResponse.items には存在するアルバムがすべて含まれる
```

### UPC（バーコード）での取得
```swift
let albumsRequest = MusicCatalogResourceRequest<Album>(matching: \.upc, equalTo: barcode)
let albumsResponse = try await albumsRequest.response()
```

### 関連データの取得
```swift
let detailedAlbum = try await album.with([.artists, .tracks])
```

## 4. 音楽再生

### プレイヤーの取得
```swift
private let player = ApplicationMusicPlayer.shared
```

### 再生キューの設定
```swift
// アルバム全体を再生
player.queue = [album]

// トラックリストから特定の曲を開始
player.queue = ApplicationMusicPlayer.Queue(for: tracks, startingAt: track)
```

### 再生制御
```swift
try await player.play()
player.pause()
```

### 再生状態の監視
```swift
@ObservedObject private var playerState = ApplicationMusicPlayer.shared.state

private var isPlaying: Bool {
    return (playerState.playbackStatus == .playing)
}
```

## 5. サブスクリプション管理

### サブスクリプション状態の監視
```swift
for await subscription in MusicSubscription.subscriptionUpdates {
    // サブスクリプション状態が変更された時の処理
}
```

### 再生権限の確認
```swift
let canPlayCatalogContent = musicSubscription?.canPlayCatalogContent ?? false
```

### サブスクリプション申し込みの提供
```swift
let canBecomeSubscriber = musicSubscription?.canBecomeSubscriber ?? false
```

## 6. エラーハンドリング

### 基本的なエラーハンドリング
```swift
do {
    let searchResponse = try await searchRequest.response()
    // 成功時の処理
} catch {
    print("Search request failed with error: \(error).")
    // エラー時の処理
}
```

## 7. MainActorでのUI更新

### UIの安全な更新
```swift
@MainActor
private func updateUI(with data: SomeData) {
    withAnimation {
        self.someProperty = data
    }
}
```

## 8. Apple Music HTTP API（混合種別対応）

### MusicKitの制約とHTTP APIによる解決

MusicKitの`MusicCatalogResourceRequest`は型ごとに分けてAPIコールする必要がありますが、Apple Music HTTP APIを直接使用することで**混合種別の一括逆引き**が可能になります。

### DeveloperToken取得
```swift
import MusicKit

class AppleMusicHTTPClient: ObservableObject {
    private let tokenProvider = DefaultMusicTokenProvider()
    private var cachedToken: String?
    private var tokenExpiration: Date?
    
    private func getDeveloperToken() async throws -> String {
        if let cachedToken = cachedToken,
           let expiration = tokenExpiration,
           Date() < expiration {
            return cachedToken
        }
        
        let token = try await tokenProvider.developerToken(options: [])
        self.cachedToken = token
        self.tokenExpiration = Date().addingTimeInterval(3600) // 1時間キャッシュ
        return token
    }
}
```

### 混合種別ID一括取得の実装
```swift
func fetchMixedResources(ids: [String], searchResults: [MixedSearchResult]) async throws -> MixedResourceResponse {
    let token = try await getDeveloperToken()
    let storefront = try await MusicDataRequest.currentCountryCode
    
    // IDsを種別ごとに分類
    let idsByType = Dictionary(grouping: searchResults.filter { ids.contains($0.id) }) { $0.type }
    
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.music.apple.com"
    components.path = "/v1/catalog/\(storefront)"
    
    var queryItems: [URLQueryItem] = []
    
    // 種別ごとに正しいパラメータ形式で設定
    if let albumItems = idsByType[.albums], !albumItems.isEmpty {
        let albumIds = albumItems.map { $0.id }.joined(separator: ",")
        queryItems.append(URLQueryItem(name: "ids[albums]", value: albumIds))
    }
    
    if let songItems = idsByType[.songs], !songItems.isEmpty {
        let songIds = songItems.map { $0.id }.joined(separator: ",")
        queryItems.append(URLQueryItem(name: "ids[songs]", value: songIds))
    }
    
    if let artistItems = idsByType[.artists], !artistItems.isEmpty {
        let artistIds = artistItems.map { $0.id }.joined(separator: ",")
        queryItems.append(URLQueryItem(name: "ids[artists]", value: artistIds))
    }
    
    queryItems.append(URLQueryItem(name: "include", value: "artists,albums"))
    components.queryItems = queryItems
    
    guard let url = components.url else {
        throw HTTPAPIError.invalidURL
    }
    
    var request = URLRequest(url: url)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    let (data, response) = try await URLSession.shared.data(for: request)
    
    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
        throw HTTPAPIError.apiError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, 
                                   message: "HTTP request failed")
    }
    
    return try JSONDecoder().decode(MixedResourceResponse.self, from: data)
}
```

### HTTP APIの正しいクエリパラメータ形式

```
https://api.music.apple.com/v1/catalog/jp?ids[albums]=123,456&ids[songs]=789&include=artists,albums
```

