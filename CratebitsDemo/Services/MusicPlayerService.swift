//
//  MusicPlayerService.swift
//  CratebitsDemo
//
//  Created by Claude on 2025/07/16.
//

import Foundation
import MusicKit
import Combine
import AVFoundation

/// MusicKit音楽プレイヤーサービス
@MainActor
class MusicPlayerService: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var currentTrack: String?
    @Published var playbackStatus: String = "Stopped"
    @Published var isPreviewMode = false
    @Published var previewTimeRemaining: Int = 30
    @Published var debugMessage: String = ""
    @Published var currentPreviewItem: ListenLaterItem?
    @Published var isCacheInitializing: Bool = false
    
    private let player = ApplicationMusicPlayer.shared
    private var previewPlayer: AVPlayer?
    private var previewTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // 新しいキャッシュコントローラー
    private let cacheController: CacheController
    
    // 現在のプレビュー情報
    private var currentPreviewURL: URL?
    private var shouldLoopPreview = false
    private var isUsingCachedPlayer = false
    
    override init() {
        // キャッシュコントローラーを初期化
        let dataSource = MusicKitCacheDataSource()
        let storage = AVPlayerCacheStorage()
        self.cacheController = CacheController(
            dataSource: dataSource,
            storage: storage
        )
        
        super.init()
        
        // プレイヤー状態の監視
        player.state.objectWillChange
            .sink { [weak self] in
                self?.updatePlaybackStatus()
            }
            .store(in: &cancellables)
        
        updatePlaybackStatus()
    }
    
    /// トラックを再生
    func playTrack(_ track: Track) async {
        do {
            player.queue = ApplicationMusicPlayer.Queue(for: [track])
            try await player.play()
            self.currentTrack = track.title
            self.updatePlaybackStatus()
        } catch {
            print("再生エラー: \(error)")
            self.playbackStatus = "Error: \(error.localizedDescription)"
        }
    }
    
    /// ソングを再生
    func playSong(_ song: Song) async {
        do {
            player.queue = ApplicationMusicPlayer.Queue(for: [song])
            try await player.play()
            self.currentTrack = song.title
            self.updatePlaybackStatus()
        } catch {
            print("再生エラー: \(error)")
            self.playbackStatus = "Error: \(error.localizedDescription)"
        }
    }
    
    /// アルバムを再生
    func playAlbum(_ album: Album) async {
        do {
            player.queue = ApplicationMusicPlayer.Queue(for: [album])
            try await player.play()
            self.currentTrack = album.title
            self.updatePlaybackStatus()
        } catch {
            print("再生エラー: \(error)")
            self.playbackStatus = "Error: \(error.localizedDescription)"
        }
    }
    
    /// 複数のトラックを再生
    func playTracks(_ tracks: [Track]) async {
        guard !tracks.isEmpty else { return }
        
        player.queue = ApplicationMusicPlayer.Queue(for: tracks, startingAt: tracks.first)
        do {
            try await player.play()
            self.currentTrack = tracks.first?.title
            self.updatePlaybackStatus()
        } catch {
            print("再生エラー: \(error)")
            self.playbackStatus = "Error: \(error.localizedDescription)"
        }
    }
    
    /// 再生を一時停止
    func pause() {
        player.pause()
        updatePlaybackStatus()
    }
    
    /// 再生を停止
    func stop() {
        player.stop()
        currentTrack = nil
        updatePlaybackStatus()
    }
    
    /// 再生を再開
    func resume() async {
        do {
            try await player.play()
            updatePlaybackStatus()
        } catch {
            print("再生再開エラー: \(error)")
            playbackStatus = "Error: \(error.localizedDescription)"
        }
    }
    
    /// 次のトラックにスキップ
    func skipToNext() async {
        do {
            try await player.skipToNextEntry()
            updatePlaybackStatus()
        } catch {
            print("スキップエラー: \(error)")
        }
    }
    
    /// 前のトラックに戻る
    func skipToPrevious() async {
        do {
            try await player.skipToPreviousEntry()
            updatePlaybackStatus()
        } catch {
            print("前の曲エラー: \(error)")
        }
    }
    
    /// 再生状態を更新
    private func updatePlaybackStatus() {
        let state = player.state
        isPlaying = state.playbackStatus == .playing
        
        switch state.playbackStatus {
        case .stopped:
            playbackStatus = "Stopped"
        case .paused:
            playbackStatus = "Paused"
        case .playing:
            playbackStatus = "Playing"
        case .seekingForward:
            playbackStatus = "Seeking Forward"
        case .seekingBackward:
            playbackStatus = "Seeking Backward"
        case .interrupted:
            playbackStatus = "Interrupted"
        @unknown default:
            playbackStatus = "Unknown"
        }
    }
    
    // MARK: - Preview Methods
    
    /// ソングの30秒プレビューを再生
    func playPreview(_ song: Song) async {
        await MainActor.run {
            self.debugMessage = "Debug: 検索中 - Song: \(song.title), ID: \(song.id)"
            print("[Preview Debug] Song: \(song.title), ID: \(song.id)")
            print("[Preview Debug] PreviewAssets count: \(song.previewAssets?.count ?? 0)")
        }
        
        guard let previewAssets = song.previewAssets, !previewAssets.isEmpty else {
            await MainActor.run {
                self.playbackStatus = "No preview assets found"
                self.debugMessage = "Error: previewAssetsがnullまたは空"
                print("[Preview Error] No preview assets for song: \(song.title)")
            }
            return
        }
        
        guard let previewURL = previewAssets.first?.url else {
            await MainActor.run {
                self.playbackStatus = "No preview URL found"
                self.debugMessage = "Error: previewURLがnull"
                print("[Preview Error] Preview asset exists but no URL for song: \(song.title)")
            }
            return
        }
        
        await MainActor.run {
            self.debugMessage = "Debug: URL取得成功 - \(previewURL.absoluteString)"
            print("[Preview Debug] Preview URL found: \(previewURL.absoluteString)")
        }
        
        await playPreview(from: previewURL, title: song.title, itemId: song.id.rawValue)
    }
    
    /// トラックの30秒プレビューを再生
    func playPreview(_ track: Track) async {
        await MainActor.run {
            self.debugMessage = "Debug: 検索中 - Track: \(track.title), ID: \(track.id)"
            print("[Preview Debug] Track: \(track.title), ID: \(track.id)")
            print("[Preview Debug] PreviewAssets count: \(track.previewAssets?.count ?? 0)")
        }
        
        guard let previewAssets = track.previewAssets, !previewAssets.isEmpty else {
            await MainActor.run {
                self.playbackStatus = "No preview assets found"
                self.debugMessage = "Error: previewAssetsがnullまたは空"
                print("[Preview Error] No preview assets for track: \(track.title)")
            }
            return
        }
        
        guard let previewURL = previewAssets.first?.url else {
            await MainActor.run {
                self.playbackStatus = "No preview URL found"
                self.debugMessage = "Error: previewURLがnull"
                print("[Preview Error] Preview asset exists but no URL for track: \(track.title)")
            }
            return
        }
        
        await MainActor.run {
            self.debugMessage = "Debug: URL取得成功 - \(previewURL.absoluteString)"
            print("[Preview Debug] Preview URL found: \(previewURL.absoluteString)")
        }
        
        await playPreview(from: previewURL, title: track.title, itemId: track.id.rawValue)
    }
    
    /// プレビューURLから30秒プレビューを再生
    private func playPreview(from url: URL, title: String, itemId: String) async {
        print("[Preview Debug] Starting preview playback for: \(title)")
        print("[Preview Debug] URL: \(url.absoluteString)")
        
        stopPreview()
        isPreviewMode = true
        shouldLoopPreview = false  // 通常のプレビューはループしない
        previewTimeRemaining = 30
        currentTrack = title
        currentPreviewURL = url
        playbackStatus = "Preview Playing"
        debugMessage = "Debug: プレイヤー初期化中..."
        print("[Preview Debug] Set shouldLoopPreview = false for normal preview")
        
        // URLの有効性をチェック
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                print("[Preview Debug] HTTP Status: \(httpResponse.statusCode)")
                self.debugMessage = "Debug: HTTP Status \(httpResponse.statusCode)"
                
                if httpResponse.statusCode != 200 {
                    self.playbackStatus = "Preview URL unavailable (\(httpResponse.statusCode))"
                    self.debugMessage = "Error: HTTP \(httpResponse.statusCode) - URLが無効"
                    self.stopPreview()
                    return
                }
            }
        } catch {
            print("[Preview Error] URL check failed: \(error)")
            self.playbackStatus = "Preview URL check failed"
            self.debugMessage = "Error: URLチェック失敗 - \(error.localizedDescription)"
            self.stopPreview()
            return
        }
        
        previewPlayer = AVPlayer(url: url)
        
        // AVPlayerの状態を監視
        if let player = previewPlayer {
            isUsingCachedPlayer = false
            player.addObserver(self, forKeyPath: "status", options: [.new], context: nil)
            player.addObserver(self, forKeyPath: "error", options: [.new], context: nil)
            player.addObserver(self, forKeyPath: "rate", options: [.new], context: nil)
            
            self.debugMessage = "Debug: AVPlayer初期化完了、再生開始..."
            
            // AVPlayer項目の詳細情報を出力
            print("[Preview Debug] AVPlayer current item: \(player.currentItem?.description ?? "nil")")
            print("[Preview Debug] AVPlayer status: \(player.status.rawValue)")
            print("[Preview Debug] AVPlayer rate: \(player.rate)")
            
            // 音量設定を確認
            player.volume = 1.0
            print("[Preview Debug] AVPlayer volume set to: \(player.volume)")
            
            player.play()
            print("[Preview Debug] AVPlayer.play() called")
            
            // 新しいキャッシュシステムは自動でキャッシュするため、手動保存は不要
            
            // 少し待ってから状態を再確認
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                print("[Preview Debug] After 1s - Status: \(player.status.rawValue), Rate: \(player.rate)")
                if let item = player.currentItem {
                    print("[Preview Debug] Current item status: \(item.status.rawValue)")
                    if let error = item.error {
                        print("[Preview Error] Current item error: \(error)")
                    }
                }
            }
        }
        
        // 30秒タイマーを開始
        startPreviewTimer()
    }
    
    /// プレビュータイマーを開始
    private func startPreviewTimer() {
        // 既存のタイマーがあれば停止
        previewTimer?.invalidate()
        previewTimer = nil
        
        // プレビューモードでない場合はタイマーを開始しない
        guard isPreviewMode else {
            print("[Preview Debug] Not in preview mode, not starting timer")
            return
        }
        
        print("[Preview Debug] Starting preview timer - mode: \(isPreviewMode), shouldLoop: \(shouldLoopPreview)")
        previewTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self = self else { 
                    timer.invalidate()
                    return 
                }
                
                // プレビューモードでない場合はタイマーを停止
                guard self.isPreviewMode else {
                    timer.invalidate()
                    self.previewTimer = nil
                    return
                }
                
                // タイマーが現在のタイマーでない場合は停止（重複防止）
                guard timer == self.previewTimer else {
                    timer.invalidate()
                    return
                }
                
                self.previewTimeRemaining -= 1
                
                if self.previewTimeRemaining <= 0 {
                    // プレビューモード中はループ再生
                    if self.shouldLoopPreview {
                        print("[Preview Debug] Restarting preview (loop mode)")
                        self.restartCurrentPreview()
                    } else {
                        print("[Preview Debug] Stopping preview after 30s")
                        self.stopPreview()
                    }
                }
            }
        }
    }
    
    /// プレビュー再生を停止
    func stopPreview() {
        print("[Preview Debug] stopPreview() called - timeRemaining: \(previewTimeRemaining), shouldLoop: \(shouldLoopPreview)")
        
        if let player = previewPlayer {
            player.pause()
            // 自分で作成したプレイヤーのみオブザーバーを削除
            if !isUsingCachedPlayer {
                player.removeObserver(self, forKeyPath: "status")
                player.removeObserver(self, forKeyPath: "error")
                player.removeObserver(self, forKeyPath: "rate")
                // 自分で作成したプレイヤーのみnilにする
                previewPlayer = nil
            } else {
                // キャッシュプレイヤーの場合は参照のみ解除、プレイヤー自体は保持
                previewPlayer = nil
                print("[Preview Debug] Cache player preserved, only reference cleared")
            }
        }
        
        // タイマーを確実に停止
        if let timer = previewTimer {
            print("[Preview Debug] Invalidating existing timer")
            timer.invalidate()
        } else {
            print("[Preview Debug] No timer to invalidate")
        }
        previewTimer = nil
        
        isPreviewMode = false
        shouldLoopPreview = false
        previewTimeRemaining = 30
        currentPreviewItem = nil
        currentPreviewURL = nil
        isUsingCachedPlayer = false
        playbackStatus = "Stopped"
        debugMessage = "Debug: プレビュー停止"
        print("[Preview Debug] Preview stopped - cleanup complete")
    }
    
    /// プレビューモードかどうかを確認
    var isInPreviewMode: Bool {
        return isPreviewMode && previewPlayer != nil
    }
    
    /// AVPlayer状態変更の監視
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if let player = object as? AVPlayer, player == previewPlayer {
            Task { @MainActor in
                switch keyPath {
                case "status":
                    let status = player.status
                    print("[Preview Debug] AVPlayer status changed: \(status.rawValue) (\(status))")
                    switch status {
                    case .readyToPlay:
                        self.debugMessage = "Debug: AVPlayer準備完了"
                        print("[Preview Debug] AVPlayer ready to play")
                    case .failed:
                        if let error = player.error {
                            self.debugMessage = "Error: AVPlayer失敗 - \(error.localizedDescription)"
                            self.playbackStatus = "Preview playback failed"
                            print("[Preview Error] AVPlayer failed: \(error)")
                        }
                        print("[Preview Debug] Calling stopPreview() due to AVPlayer failure")
                        self.stopPreview()
                    case .unknown:
                        self.debugMessage = "Debug: AVPlayer状態不明"
                        print("[Preview Debug] AVPlayer status unknown")
                    @unknown default:
                        print("[Preview Debug] AVPlayer unknown status: \(status)")
                        break
                    }
                case "rate":
                    let rate = player.rate
                    print("[Preview Debug] AVPlayer rate changed: \(rate)")
                    if rate > 0 {
                        self.debugMessage = "Debug: 再生中 (rate: \(rate))"
                        print("[Preview Debug] Audio is playing")
                    } else {
                        self.debugMessage = "Debug: 停止中 (rate: \(rate))"
                        print("[Preview Debug] Audio is paused/stopped")
                    }
                case "error":
                    if let error = player.error {
                        self.debugMessage = "Error: AVPlayerエラー - \(error.localizedDescription)"
                        self.playbackStatus = "Preview error"
                        print("[Preview Error] AVPlayer error: \(error)")
                        print("[Preview Debug] Calling stopPreview() due to AVPlayer error")
                        self.stopPreview()
                    }
                default:
                    break
                }
            }
        }
    }
    
    // MARK: - Enhanced Preview Methods
    
    /// 高速プレビュー開始（キャッシュ使用）
    func playPreviewInstantly(for item: ListenLaterItem) async {
        print("[Preview Debug] playPreviewInstantly called for: \(item.name) (type: \(item.type))")
        
        // 同じアイテムが既に再生中の場合はスキップ（重複防止）
        if let currentItem = currentPreviewItem, currentItem.id == item.id && isPreviewMode {
            print("[Preview Debug] Same item already playing, skipping duplicate call")
            return
        }
        
        stopPreview()
        currentPreviewItem = item
        isPreviewMode = true
        shouldLoopPreview = true  // プレビューモードでは常にループを有効
        currentTrack = item.name
        playbackStatus = "Preview Starting"
        print("[Preview Debug] Set shouldLoopPreview = true for preview mode")
        
        // アルバム/アーティストの場合、最初のピックアップ楽曲を再生
        if (item.type == .album || item.type == .artist), 
           let pickedTracks = item.pickedTracks, 
           !pickedTracks.isEmpty {
            print("[Preview Debug] Playing first picked track for \(item.type.displayName): \(item.name)")
            await playPreviewInstantly(for: pickedTracks[0])
            return
        }
        
        // トラックの場合の処理
        guard item.type == .track else {
            print("[Preview Debug] No preview available for item type: \(item.type)")
            stopPreview()
            return
        }
        
        // 🔑 CACHE KEY FIX: Ensure we use Apple Music ID for cache lookup
        // If the ListenLaterItem doesn't have appleMusicID, we need to get it
        var cacheKey: String
        if let appleMusicID = item.appleMusicID, !appleMusicID.isEmpty {
            cacheKey = appleMusicID
            print("[Cache Debug] ✅ Using Apple Music ID as cache key: '\(cacheKey)'")
        } else {
            // Fallback: If no Apple Music ID, we can't use cache (cache stores by Apple Music ID)
            print("[Cache Debug] ❌ No Apple Music ID available for cache lookup: '\(item.name)'")
            print("[Cache Debug] 🔄 Cache miss guaranteed - falling back to MusicKit API")
            await fallbackToMusicKitPreview(for: item)
            return
        }
        
        print("[Cache Debug] 📊 All cached keys: \(Array(await cacheController.cachedKeys).sorted())")
        
        // 新しいキャッシュシステムでキャッシュを確認
        let isCached = await cacheController.isCached(cacheKey)
        print("[Cache Debug] 📋 isCached('\(cacheKey)') = \(isCached)")
        
        if isCached {
            let cachedItem = await cacheController.getCachedItem(for: cacheKey)
            print("[Cache Debug] 📦 getCachedItem result: \(cachedItem != nil ? "Found" : "Not Found")")
            
            if let cachedItem = cachedItem {
                print("[Cache Debug] 🔧 Cached item ready: \(cachedItem.isReady)")
                
                if cachedItem.isReady {
                    print("[Cache Info] 🎯 CACHE HIT: Using cached player for \(item.name)")
                    
                    // AVPlayerStorageの場合はプレイヤーを直接取得
                    if let cachedPlayer = await getCachedPlayer(for: cacheKey) {
                        print("[Cache Debug] 🎬 Got cached player successfully")
                        
                        // キャッシュプレイヤーを即座に利用
                        previewPlayer = cachedPlayer
                        isUsingCachedPlayer = true
                        previewTimeRemaining = 30
                        
                        print("[Cache Info] ⚡ INSTANT PLAYBACK: Starting cached player immediately")
                        await cachedPlayer.seek(to: .zero)
                        cachedPlayer.play()
                        playbackStatus = "Preview Playing (Cached)"
                        
                        print("[Preview Debug] Starting timer for cached player")
                        startPreviewTimer()
                        
                        print("[Cache Info] ✅ CACHE PLAYBACK: Setup complete, no API calls needed")
                    } else {
                        print("[Cache Debug] ❌ Could not get cached player from storage")
                        await fallbackToMusicKitPreview(for: item)
                    }
                } else {
                    print("[Cache Debug] ⏳ Cached item not ready yet")
                    await fallbackToMusicKitPreview(for: item)
                }
            } else {
                print("[Cache Debug] ❌ getCachedItem returned nil despite isCached=true")
                await fallbackToMusicKitPreview(for: item)
            }
        } else {
            // キャッシュがない場合は通常の方法
            print("[Cache Info] ❌ CACHE MISS: No cache available for \(item.name), using MusicKit API")
            await fallbackToMusicKitPreview(for: item)
        }
    }
    
    /// MusicKitプレビューへのフォールバック処理
    private func fallbackToMusicKitPreview(for item: ListenLaterItem) async {
        if let appleMusicID = item.appleMusicID {
            print("[Preview Debug] Starting MusicKit request for Apple Music ID: \(appleMusicID)")
            do {
                let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(appleMusicID))
                let response = try await request.response()
                
                if let song = response.items.first {
                    print("[Preview Debug] Song retrieved, calling playPreview")
                    await self.playPreview(song)
                } else {
                    print("[Preview Debug] No song found for Apple Music ID: \(appleMusicID)")
                    stopPreview()
                }
            } catch {
                print("[Preview Error] Error loading song for preview: \(error)")
                stopPreview()
            }
        } else {
            print("[Preview Debug] No Apple Music ID available for item: \(item.name)")
            stopPreview()
        }
    }
    
    /// 現在のプレビューを再開
    private func restartCurrentPreview() {
        guard currentPreviewURL != nil else {
            stopPreview()
            return
        }
        
        print("[Preview Debug] Restarting preview")
        
        Task {
            await previewPlayer?.seek(to: .zero)
            previewPlayer?.play()
        }
        previewTimeRemaining = 30
        
        debugMessage = "Debug: プレビューを再開"
    }
    
    /// プレビュー自動モードに入る
    func enterPreviewMode() {
        shouldLoopPreview = true
        print("[Preview Debug] Entered preview auto mode")
    }
    
    /// プレビュー自動モードを終了
    func exitPreviewMode() {
        shouldLoopPreview = false
        stopPreview()
        print("[Preview Debug] Exited preview auto mode")
    }
    
    /// ListenNowリストの更新（新しいキューが生成された時）
    func updateListenNowItems(_ items: [ListenLaterItem]) {
        // Set cache initialization state on main actor
        Task { @MainActor in
            self.isCacheInitializing = true
        }
        
        // Use Task.detached to ensure heavy work runs on background thread
        Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            
            print("[Cache Debug] 🔄 UPDATE LIST: Converting \(items.count) ListenLaterItems to ListenNowItems")
            
            // ListenLaterItemをListenNowItemに変換
            let listenNowItems = items.compactMap { ListenNowItem.from($0) }
            print("[Cache Debug] 🔄 UPDATE LIST: Successfully converted to \(listenNowItems.count) ListenNowItems")
            
            for (index, item) in listenNowItems.enumerated() {
                print("[Cache Debug] 🔄 Item[\(index)]: \(item.name) - \(item.trackCount) tracks")
                for trackIndex in 0..<min(item.trackCount, 3) {
                    let track = item.getPickedTrack(at: trackIndex)
                    print("[Cache Debug] 🔄   Track[\(trackIndex)]: \(track.name) - ID: \(track.appleMusicID)")
                }
            }
            
            await self.cacheController.updateListenNowItems(listenNowItems)
            print("[Cache Debug] 🔄 UPDATE LIST: Cache controller notified")
            
            // Update cache initialization state on main actor
            Task { @MainActor in
                self.isCacheInitializing = false
            }
        }
    }
    
    /// フォーカス変更時のキャッシュ処理
    func handleFocusChange(to pageIndex: Int, trackIndex: Int = 0) {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            let cursor = ListenNowCursor(pageIndex: pageIndex, trackIndex: trackIndex)
            print("[Cache Debug] 🎯 FOCUS CHANGE: Moving to page \(pageIndex), track \(trackIndex)")
            await self.cacheController.handleFocusChange(to: cursor)
            print("[Cache Debug] 🎯 FOCUS CHANGE: Cache controller processed focus change")
        }
    }
    
    /// カルーセル内移動時のキャッシュ処理
    func handleCarouselFocusChange(to pageIndex: Int, trackIndex: Int) {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            let cursor = ListenNowCursor(pageIndex: pageIndex, trackIndex: trackIndex)
            print("[Cache Debug] 🎠 CAROUSEL CHANGE: Moving to page \(pageIndex), track \(trackIndex)")
            await self.cacheController.handleCarouselFocusChange(to: cursor)
            print("[Cache Debug] 🎠 CAROUSEL CHANGE: Cache controller processed carousel change")
        }
    }
    
    
    /// キャッシュをクリア
    func clearPreviewCache() {
        // 新しいキャッシュシステムには全削除機能がないため、個別実装が必要
        print("[Cache Info] Cache clear requested - new system doesn't support full clear")
    }
    
    /// キャッシュ状態をデバッグ出力
    func debugCacheStatus() {
        Task {
            let state = await cacheController.dumpState()
            print("[Cache Debug] Cache Controller State: \(state)")
        }
    }
    
    /// キャッシュからプレイヤーを取得（内部用）
    private func getCachedPlayer(for appleMusicID: String) async -> AVPlayer? {
        // AVPlayerCacheStorageの場合は直接プレイヤーを取得
        if let avStorage = cacheController.storage as? AVPlayerCacheStorage {
            return avStorage.getPlayer(for: appleMusicID)
        }
        
        // その他のストレージの場合は新しいプレイヤーを作成
        if let cachedItem = await cacheController.getCachedItem(for: appleMusicID) {
            return AVPlayer(url: cachedItem.item.previewURL)
        }
        
        return nil
    }

    deinit {
        // 自分で作成したプレイヤーのみオブザーバーを削除
        if let player = previewPlayer, !isUsingCachedPlayer {
            player.removeObserver(self, forKeyPath: "status")
            player.removeObserver(self, forKeyPath: "error")
            player.removeObserver(self, forKeyPath: "rate")
        }
    }
}