//
//  CacheControllerTests.swift
//  CratebitsDemoTests
//
//  Created by Claude on 2025/07/20.
//

import Testing
import Foundation
@testable import CratebitsDemo

// MARK: - Test Helpers

/// テスト用のListenNowItemファクトリ
struct TestItemFactory {
    
    /// テスト用の標準的なアイテムリストを生成
    static func createTestItems() -> [ListenNowItem] {
        // 単一トラック
        let track1 = ListenNowItem.singleTrack(
            appleMusicID: "1787556305",
            name: "Matter of Time",
            artist: "Vulfpeck"
        )
        
        // アルバム（3つのピックアップ楽曲）
        let albumTracks = [
            PickedTrack(appleMusicID: "1787556305", name: "Matter of Time", artist: "Vulfpeck"),
            PickedTrack(appleMusicID: "1787556307", name: "Can You Tell", artist: "Vulfpeck"),
            PickedTrack(appleMusicID: "1160119691", name: "El Chepe", artist: "Vulfpeck")
        ]
        let album = ListenNowItem.album(
            appleMusicID: "2000",
            name: "Vulfpeck Album",
            artist: "Vulfpeck",
            pickedTracks: albumTracks
        )
        
        // 単一トラック
        let track2 = ListenNowItem.singleTrack(
            appleMusicID: "1787556307",
            name: "Can You Tell",
            artist: "Vulfpeck"
        )
        
        // 単一トラック
        let track3 = ListenNowItem.singleTrack(
            appleMusicID: "1160119422",
            name: "Dean Town",
            artist: "Vulfpeck"
        )
        
        // 単一トラック
        let track4 = ListenNowItem.singleTrack(
            appleMusicID: "1160119691",
            name: "El Chepe",
            artist: "Vulfpeck"
        )
        
        return [track1, album, track2, track3, track4]
    }
    
    /// 小さなテストアイテムリストを生成
    static func createSmallTestItems() -> [ListenNowItem] {
        let track1 = ListenNowItem.singleTrack(
            appleMusicID: "1787556305",
            name: "Matter of Time",
            artist: "Vulfpeck"
        )
        
        let albumTracks = [
            PickedTrack(appleMusicID: "1787556307", name: "Can You Tell", artist: "Vulfpeck"),
            PickedTrack(appleMusicID: "1160119691", name: "El Chepe", artist: "Vulfpeck")
        ]
        let album = ListenNowItem.album(
            appleMusicID: "2000", 
            name: "Small Album",
            artist: "Vulfpeck",
            pickedTracks: albumTracks
        )
        
        return [track1, album]
    }
}

// MARK: - Cache Controller Tests

@MainActor
struct CacheControllerTests {
    
    // MARK: - Initial Cache Tests
    
    @Test("初期状態で適切にキャッシュが行われるか")
    func initialCacheStrategy() async throws {
        // Given: テストデータを準備
        let mockDataSource = MockCacheDataSource()
        mockDataSource.setupTestData()
        
        let storage = InMemoryCacheStorage()
        let controller = CacheController(
            dataSource: mockDataSource,
            storage: storage
        )
        
        let items = TestItemFactory.createTestItems()
        
        // When: 初期キャッシュを実行
        mockDataSource.clearFetchCalls()
        await controller.updateListenNowItems(items)
        
        // Then: 適切なアイテムがキャッシュされている
        #expect(controller.isCached("1787556305")) // 現在のトラック (page:0, track:0) + 次ページアルバムの1曲目（予測キャッシュ）
        // 仕様により次ページは1曲目のみ予測キャッシュ、2曲目はキャッシュされない
        
        // APIコール効率の検証
        let fetchCalls = mockDataSource.fetchCalls
        print("Initial cache API calls: \(fetchCalls)")
        #expect(fetchCalls.count == 1) // 1787556305のみ（重複なし）
        #expect(fetchCalls.contains("1787556305"))
        
        // カーソル位置が正しく設定されている
        #expect(controller.currentCursor.pageIndex == 0)
        #expect(controller.currentCursor.trackIndex == 0)
        
        print("✅ Initial cache test passed")
    }
    
    @Test("アルバムページにフォーカスがある場合の初期キャッシュ")
    func initialCacheForAlbumPage() async throws {
        // Given: アルバムページからスタート
        let mockDataSource = MockCacheDataSource()
        mockDataSource.setupTestData()
        
        let storage = InMemoryCacheStorage()
        let controller = CacheController(
            dataSource: mockDataSource,
            storage: storage
        )
        
        let items = TestItemFactory.createTestItems()
        print("DEBUG: Test items count: \(items.count)")
        print("DEBUG: Album item (index 1): \(items[1])")
        
        // When: ListenNowリストを設定してアルバムページ（index 1）にフォーカス移動
        mockDataSource.clearFetchCalls()
        await controller.updateListenNowItems(items)
        let initialFetchCalls = mockDataSource.fetchCalls.count
        print("DEBUG: After updateListenNowItems, cached keys: \(controller.cachedKeys)")
        print("DEBUG: Initial API calls: \(initialFetchCalls)")
        
        mockDataSource.clearFetchCalls()
        let albumCursor = ListenNowCursor(pageIndex: 1, trackIndex: 0)
        await controller.handleFocusChange(to: albumCursor)
        
        // 非同期処理の完了を待つ
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1秒待機
        
        // Then: アルバムのピックアップ楽曲がキャッシュされている
        print("DEBUG: Final cached keys: \(controller.cachedKeys)")
        print("DEBUG: Current cursor: \(controller.currentCursor)")
        
        // APIコール効率の検証
        let focusChangeFetchCalls = mockDataSource.fetchCalls
        print("DEBUG: Focus change API calls: \(focusChangeFetchCalls)")
        
        // アルバムのピックアップ楽曲がListenNowItemから正しく取得できるか確認
        let albumItem = items[1]
        print("DEBUG: Album tracks count: \(albumItem.trackCount)")
        for i in 0..<albumItem.trackCount {
            let track = albumItem.getPickedTrack(at: i)
            print("DEBUG: Track \(i): \(track.appleMusicID) - \(track.name)")
        }
        
        #expect(controller.isCached("1787556305")) // Current focus (immediate)
        #expect(controller.isCached("1787556307")) // Adjacent in carousel + next page (adjacent/prefetch)
        #expect(!controller.isCached("1160119691")) // NOT cached - too far in carousel
        
        // フォーカス変更時は1787556307のみが新規フェッチされるはず（1787556305は既にキャッシュ済み）
        #expect(focusChangeFetchCalls.count <= 2) // 1787556307 + 次ページ予測（もしあれば）
        
        // カーソル位置が正しく設定されている
        #expect(controller.currentCursor.pageIndex == 1)
        #expect(controller.currentCursor.trackIndex == 0)
        
        print("✅ Initial album cache test passed")
    }
    
    // MARK: - Focus Change Tests
    
    @Test("フォーカス変更時のキャッシュミス処理")
    func focusChangeCacheMiss() async throws {
        // Given: 初期状態をセットアップ
        let mockDataSource = MockCacheDataSource()
        mockDataSource.setupTestData()
        
        let storage = InMemoryCacheStorage()
        let controller = CacheController(
            dataSource: mockDataSource,
            storage: storage
        )
        
        let items = TestItemFactory.createTestItems()
        await controller.updateListenNowItems(items)
        
        // キャッシュされていない状態を確認
        #expect(!controller.isCached("1160119422")) // Dean Townはまだキャッシュされていない
        
        controller.clearEvents()
        mockDataSource.clearFetchCalls()
        
        // When: まだキャッシュされていないアイテムにフォーカス変更
        let targetCursor = ListenNowCursor(pageIndex: 3, trackIndex: 0) // Dean Town (index 3)
        await controller.handleFocusChange(to: targetCursor)
        
        // Then: 新しいダウンロードが実行され、アイテムがキャッシュされる
        let downloadEvents = controller.events.filter {
            if case .downloadStarted = $0 { return true }
            return false
        }
        
        #expect(!downloadEvents.isEmpty) // ダウンロードが開始
        #expect(mockDataSource.fetchCalls.contains("1160119422")) // Dean Townがフェッチされた
        #expect(controller.isCached("1160119422")) // フォーカス変更後にキャッシュされている
        
        print("✅ Cache miss test passed")
    }
    
    @Test("フォーカス変更時のキャッシュヒット処理")
    func focusChangeCacheHit() async throws {
        // Given: 事前にアイテムがキャッシュされている状態
        let mockDataSource = MockCacheDataSource()
        mockDataSource.setupTestData()
        
        let storage = InMemoryCacheStorage()
        let controller = CacheController(
            dataSource: mockDataSource,
            storage: storage
        )
        
        let items = TestItemFactory.createTestItems()
        await controller.updateListenNowItems(items)
        
        // 初期キャッシュの後、アルバムページに移動（既にキャッシュ済み）
        controller.clearEvents()
        mockDataSource.clearFetchCalls()
        
        // When: 既にキャッシュされているアルバムページにフォーカス変更
        await controller.handleFocusChange(to: ListenNowCursor(pageIndex: 1, trackIndex: 0)) // Album
        
        // Then: キャッシュヒットし、不要なダウンロードは発生しない
        let cachedItem = controller.getCachedItem(for: "1787556305")
        #expect(cachedItem != nil) // キャッシュヒット
        
        // 新しいフェッチは必要最小限のみ
        let fetchCallsCount = mockDataSource.fetchCalls.count
        #expect(fetchCallsCount <= 2) // 隣接/予測キャッシュのみ
        
        print("✅ Cache hit test passed")
    }
    
    @Test("隣接アイテムの事前ロード")
    func adjacentItemsPreloading() async throws {
        // Given: 初期状態
        let mockDataSource = MockCacheDataSource()
        mockDataSource.setupTestData()
        
        let storage = InMemoryCacheStorage()
        let controller = CacheController(
            dataSource: mockDataSource,
            storage: storage
        )
        
        let items = TestItemFactory.createTestItems()
        await controller.updateListenNowItems(items)
        
        controller.clearEvents()
        
        // When: 中間のアイテムにフォーカス変更
        await controller.handleFocusChange(to: ListenNowCursor(pageIndex: 2, trackIndex: 0)) // Track 2
        
        // Then: 隣接アイテムが事前ロードされる
        #expect(controller.isCached("1787556307")) // 現在のアイテム（Track 2）
        
        // 前後のアイテムもキャッシュされているか、または事前ロード対象
        let downloadEvents = controller.events.compactMap { event in
            if case .downloadStarted(let appleMusicID) = event {
                return appleMusicID
            }
            return nil
        }
        
        // 次のアイテム（nextTrack）がロード対象に含まれている
        #expect(downloadEvents.contains("1160119422") || controller.isCached("1160119422"))
        
        print("✅ Adjacent items preloading test passed")
    }
    
    // MARK: - Carousel Tests
    
    @Test("カルーセル内での隣接楽曲キャッシュ")
    func carouselAdjacentTracksCache() async throws {
        // Given: アルバムページのカルーセル
        let mockDataSource = MockCacheDataSource()
        mockDataSource.setupTestData()
        
        let storage = InMemoryCacheStorage()
        let controller = CacheController(
            dataSource: mockDataSource,
            storage: storage
        )
        
        let items = TestItemFactory.createTestItems()
        
        // When: アルバムページにフォーカス
        await controller.updateListenNowItems(items)
        let albumCursor = ListenNowCursor(pageIndex: 1, trackIndex: 0)
        await controller.handleFocusChange(to: albumCursor)
        
        // 非同期処理の完了を待つ
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1秒待機
        
        // Then: カルーセル内の楽曲が適切にキャッシュされている
        print("DEBUG: Carousel test cached keys: \(controller.cachedKeys)")
        print("DEBUG: Carousel test events: \(controller.events)")
        #expect(controller.isCached("1787556305")) // Current focus (immediate)
        #expect(controller.isCached("1787556307")) // Adjacent in carousel (adjacent)
        #expect(!controller.isCached("1160119691")) // NOT cached - too far in carousel
        
        print("✅ Carousel adjacent tracks cache test passed")
    }
    
    @Test("カルーセル内移動時の軽量キャッシュ処理")
    func carouselMovementCache() async throws {
        // Given: アルバムページにフォーカス済み
        let mockDataSource = MockCacheDataSource()
        mockDataSource.setupTestData()
        
        let storage = InMemoryCacheStorage()
        let controller = CacheController(
            dataSource: mockDataSource,
            storage: storage
        )
        
        let items = TestItemFactory.createTestItems()
        await controller.updateListenNowItems(items)
        await controller.handleFocusChange(to: ListenNowCursor(pageIndex: 1, trackIndex: 0))
        
        controller.clearEvents()
        mockDataSource.clearFetchCalls()
        
        // When: カルーセル内で2番目の楽曲に移動
        let carouselCursor = ListenNowCursor(pageIndex: 1, trackIndex: 1)
        await controller.handleCarouselFocusChange(to: carouselCursor)
        
        // Then: カルーセル移動用の軽量処理が実行される
        #expect(controller.currentCursor.pageIndex == 1)
        #expect(controller.currentCursor.trackIndex == 1)
        
        // 現在フォーカス中の楽曲がimmediate優先度で処理されている
        #expect(controller.isCached("1787556307")) // 現在の楽曲
        
        print("✅ Carousel movement cache test passed")
    }
    
    // MARK: - Cache Eviction Tests
    
    @Test("キャッシュ容量制限とLRU削除")
    func cacheEvictionLRU() async throws {
        // Given: 小さなキャッシュサイズ
        let mockDataSource = MockCacheDataSource()
        mockDataSource.setupTestData()
        
        let storage = InMemoryCacheStorage(maxCacheSize: 3) // 小さなキャッシュ
        let strategy = CacheStrategy(maxCacheSize: 3)
        let controller = CacheController(
            strategy: strategy,
            dataSource: mockDataSource,
            storage: storage
        )
        
        let items = TestItemFactory.createTestItems()
        
        // When: 初期キャッシュを実行
        await controller.updateListenNowItems(items)
        
        // Then: キャッシュサイズ制限が守られている
        #expect(controller.cachedKeys.count <= 3)
        
        // フォーカス変更時に古いアイテムが削除される
        await controller.handleFocusChange(to: ListenNowCursor(pageIndex: 4, trackIndex: 0)) // Track 3
        
        let evictionEvents = controller.events.filter {
            if case .cacheEvicted = $0 { return true }
            return false
        }
        
        #expect(!evictionEvents.isEmpty) // 削除が発生している
        #expect(controller.cachedKeys.count <= 3) // 制限が守られている
        
        print("✅ Cache eviction test passed")
    }
    
    // MARK: - Error Handling Tests
    
    @Test("ダウンロード失敗時の処理")
    func downloadFailureHandling() async throws {
        // Given: 失敗するデータソース
        let mockDataSource = MockCacheDataSource()
        mockDataSource.setFailure(for: "1787556305") // 現在のトラック（キャッシュ対象）を失敗させる
        
        let storage = InMemoryCacheStorage()
        let controller = CacheController(
            dataSource: mockDataSource,
            storage: storage
        )
        
        let items = TestItemFactory.createTestItems()
        
        // When: 失敗するアイテムを含む初期化
        await controller.updateListenNowItems(items)
        
        // Then: 失敗イベントが記録され、他のアイテムは正常にキャッシュされる
        let failureEvents = controller.events.filter {
            if case .downloadFailed(let appleMusicID, _) = $0 {
                return appleMusicID == "1787556305"
            }
            return false
        }
        
        #expect(!failureEvents.isEmpty) // 失敗イベントが記録されている
        #expect(!controller.isCached("1787556305")) // 失敗したアイテムはキャッシュされていない
        
        print("✅ Download failure handling test passed")
    }
    
    // MARK: - Performance Tests
    
    @Test("同時ダウンロードの処理")
    func concurrentDownloadHandling() async throws {
        // Given: 標準的なデータソース
        let mockDataSource = MockCacheDataSource()
        mockDataSource.setupTestData()
        
        let storage = InMemoryCacheStorage()
        let controller = CacheController(
            dataSource: mockDataSource,
            storage: storage
        )
        
        let items = TestItemFactory.createTestItems()
        
        // When: 複数アイテムを同時にダウンロード
        await controller.updateListenNowItems(items)
        await controller.handleFocusChange(to: ListenNowCursor(pageIndex: 1, trackIndex: 0)) // Album
        
        // 非同期処理の完了を待つ
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1秒待機
        
        // Then: 適切なアイテムが同時ダウンロードでキャッシュされている
        print("DEBUG: Concurrent test cached keys: \(controller.cachedKeys)")
        print("DEBUG: Concurrent test events: \(controller.events)")
        #expect(controller.isCached("1787556305")) // Current focus (immediate)
        #expect(controller.isCached("1787556307")) // Adjacent in carousel + next page (adjacent/prefetch)
        #expect(!controller.isCached("1160119691")) // NOT cached - too far in carousel
        
        print("✅ Concurrent download test passed")
    }
    
    // MARK: - API Call Efficiency Tests
    
    @Test("APIコール効率の検証 - 初期キャッシュ")
    func apiCallEfficiencyInitial() async throws {
        // Given: APIコール数をトラッキング
        let mockDataSource = MockCacheDataSource()
        mockDataSource.setupTestData()
        
        let storage = InMemoryCacheStorage()
        let controller = CacheController(
            dataSource: mockDataSource,
            storage: storage
        )
        
        let items = TestItemFactory.createTestItems()
        
        // When: 初期キャッシュを実行
        mockDataSource.clearFetchCalls()
        await controller.updateListenNowItems(items)
        
        // Then: 期待されるAPIコール数のみが実行される
        let fetchCalls = mockDataSource.fetchCalls
        print("DEBUG: Initial cache API calls: \(fetchCalls)")
        
        // 初期状態 (page 0, track 0) では現在のトラック1つのみキャッシュされる
        #expect(fetchCalls.count == 1)
        #expect(fetchCalls.contains("1787556305")) // 現在のトラック + 次ページアルバムの1曲目
        
        print("✅ API call efficiency initial test passed")
    }
    
    @Test("APIコール効率の検証 - フォーカス変更")
    func apiCallEfficiencyFocusChange() async throws {
        // Given: 初期状態でキャッシュ済み
        let mockDataSource = MockCacheDataSource()
        mockDataSource.setupTestData()
        
        let storage = InMemoryCacheStorage()
        let controller = CacheController(
            dataSource: mockDataSource,
            storage: storage
        )
        
        let items = TestItemFactory.createTestItems()
        await controller.updateListenNowItems(items)
        
        // When: アルバムページにフォーカス変更
        mockDataSource.clearFetchCalls()
        await controller.handleFocusChange(to: ListenNowCursor(pageIndex: 1, trackIndex: 0))
        
        // 非同期処理の完了を待つ
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Then: 必要最小限のAPIコールのみ実行される
        let fetchCalls = mockDataSource.fetchCalls
        print("DEBUG: Focus change API calls: \(fetchCalls)")
        
        // アルバムページ移動時は隣接楽曲 + 次ページ予測のみ
        // 1787556305は既にキャッシュ済みなので、1787556307のみ新規フェッチされる
        #expect(fetchCalls.count == 1)
        #expect(fetchCalls.contains("1787556307")) // カルーセル隣接 + 次ページ予測
        
        print("✅ API call efficiency focus change test passed")
    }
    
    @Test("APIコール効率の検証 - カルーセル内移動")
    func apiCallEfficiencyCarouselMovement() async throws {
        // Given: アルバムページでキャッシュ済み
        let mockDataSource = MockCacheDataSource()
        mockDataSource.setupTestData()
        
        let storage = InMemoryCacheStorage()
        let controller = CacheController(
            dataSource: mockDataSource,
            storage: storage
        )
        
        let items = TestItemFactory.createTestItems()
        await controller.updateListenNowItems(items)
        await controller.handleFocusChange(to: ListenNowCursor(pageIndex: 1, trackIndex: 0))
        
        // 非同期処理の完了を待つ
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // When: カルーセル内で次のトラックに移動
        mockDataSource.clearFetchCalls()
        await controller.handleCarouselFocusChange(to: ListenNowCursor(pageIndex: 1, trackIndex: 1))
        
        // 非同期処理の完了を待つ
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Then: カルーセル移動では新しいAPIコールは最小限
        let fetchCalls = mockDataSource.fetchCalls
        print("DEBUG: Carousel movement API calls: \(fetchCalls)")
        
        // カルーセル内移動では既にキャッシュされている楽曲が多いため、APIコールは少ないはず
        #expect(fetchCalls.count <= 1) // 隣接楽曲で未キャッシュがあれば最大1つ
        
        print("✅ API call efficiency carousel movement test passed")
    }
    
    @Test("APIコール効率の検証 - 重複回避")
    func apiCallEfficiencyDuplicateAvoidance() async throws {
        // Given: 同じアイテムが複数回要求される状況
        let mockDataSource = MockCacheDataSource()
        mockDataSource.setupTestData()
        
        let storage = InMemoryCacheStorage()
        let controller = CacheController(
            dataSource: mockDataSource,
            storage: storage
        )
        
        let items = TestItemFactory.createTestItems()
        
        // When: 同じ操作を複数回実行
        mockDataSource.clearFetchCalls()
        await controller.updateListenNowItems(items)
        await controller.updateListenNowItems(items) // 同じリストを再設定
        
        // 非同期処理の完了を待つ
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Then: 重複するAPIコールは回避される
        let fetchCalls = mockDataSource.fetchCalls
        print("DEBUG: Duplicate avoidance API calls: \(fetchCalls)")
        
        // 既にキャッシュされているアイテムは再フェッチされない
        let uniqueCalls = Set(fetchCalls)
        #expect(fetchCalls.count == uniqueCalls.count) // 重複するAPIコールがない
        
        print("✅ API call efficiency duplicate avoidance test passed")
    }
}
