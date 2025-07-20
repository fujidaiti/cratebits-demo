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
    
    private let player = ApplicationMusicPlayer.shared
    private var previewPlayer: AVPlayer?
    private var previewTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // プレビューキャッシュマネージャー
    private let cacheManager = PreviewCacheManager()
    
    // 現在のプレビュー情報
    private var currentPreviewURL: URL?
    private var shouldLoopPreview = false
    private var isUsingCachedPlayer = false
    
    override init() {
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
            
            // 再生成功時にキャッシュに保存
            print("[Preview Debug] Caching successfully played track: \(title) (ID: \(itemId))")
            await cacheManager.cacheSuccessfulPlayback(url: url, itemId: itemId, title: title, player: player)
            
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
        
        // Apple Music IDをキャッシュキーとして使用
        let cacheKey = item.appleMusicID ?? item.id
        
        // キャッシュされたプレイヤーを最優先で確認
        if let cachedPlayer = cacheManager.getCachedPlayer(for: cacheKey) {
            print("[Cache Info] 🎯 CACHE HIT: Using cached player for \(item.name)")
            
            // キャッシュされたプレイヤーが準備完了かチェック
            guard cacheManager.isCached(itemId: cacheKey) else {
                print("[Cache Info] ⚠️ CACHE NOT READY: Cached player exists but not ready, fallback to normal preview")
                // キャッシュが準備完了でない場合は通常のプレビューへフォールバック
                if let appleMusicID = item.appleMusicID {
                    print("[Preview Debug] Starting MusicKit request for Apple Music ID: \(appleMusicID)")
                    Task {
                        do {
                            let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(appleMusicID))
                            let response = try await request.response()
                            
                            if let song = response.items.first {
                                print("[Preview Debug] Song retrieved, calling playPreview")
                                await self.playPreview(song)
                            } else {
                                print("[Preview Debug] No song found for Apple Music ID: \(appleMusicID)")
                                await MainActor.run {
                                    self.stopPreview()
                                }
                            }
                        } catch {
                            print("[Preview Error] Error loading song for preview: \(error)")
                            await MainActor.run {
                                self.stopPreview()
                            }
                        }
                    }
                } else {
                    print("[Preview Debug] No Apple Music ID available for item: \(item.name)")
                    stopPreview()
                }
                return
            }
            
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
            
            // キャッシュされたプレイヤーにはオブザーバーを追加しない（キャッシュマネージャーが管理）
            print("[Cache Info] ✅ CACHE PLAYBACK: Setup complete, no API calls needed")
        } else {
            // キャッシュがない場合は通常の方法
            print("[Cache Info] ❌ CACHE MISS: No cache available for \(item.name), using MusicKit API")
            
            if let appleMusicID = item.appleMusicID {
                print("[Preview Debug] Starting MusicKit request for Apple Music ID: \(appleMusicID)")
                Task {
                    do {
                        let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(appleMusicID))
                        let response = try await request.response()
                        
                        if let song = response.items.first {
                            print("[Preview Debug] Song retrieved, calling playPreview")
                            await self.playPreview(song)
                        } else {
                            print("[Preview Debug] No song found for Apple Music ID: \(appleMusicID)")
                            await MainActor.run {
                                self.stopPreview()
                            }
                        }
                    } catch {
                        print("[Preview Error] Error loading song for preview: \(error)")
                        await MainActor.run {
                            self.stopPreview()
                        }
                    }
                }
            } else {
                print("[Preview Debug] No Apple Music ID available for item: \(item.name)")
                stopPreview()
            }
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
    
    /// 効率的な隣接ページキャッシュ（現在+次ページのみ）
    func cacheAdjacentPages(items: [ListenLaterItem], currentIndex: Int) {
        print("[MusicPlayer Debug] cacheAdjacentPages called - index: \(currentIndex), items count: \(items.count)")
        cacheManager.preloadAdjacent(for: items, currentIndex: currentIndex)
        print("[MusicPlayer Debug] cacheAdjacentPages completed for index: \(currentIndex)")
    }
    
    /// 指定アイテム周辺のプレビューをキャッシュ（レガシー方式）
    func cachePreviewsAround(items: [ListenLaterItem], currentIndex: Int) {
        cacheManager.preloadPreviews(for: items, around: currentIndex)
    }
    
    /// カルーセル周辺の楽曲をキャッシュ
    func cacheCarouselTracks(_ tracks: [ListenLaterItem], around currentIndex: Int) {
        cacheManager.cacheCarouselTracks(tracks, around: currentIndex)
    }
    
    /// カルーセル隣接楽曲キャッシュ（現在+左右隣接のみ）
    func cacheCarouselAdjacent(_ tracks: [ListenLaterItem], currentIndex: Int) {
        cacheManager.cacheCarouselAdjacent(tracks, currentIndex: currentIndex)
    }
    
    /// アクティブなページのカルーセル隣接キャッシュ（ListenNowViewから呼び出し用）
    func cacheActiveCarouselAdjacent(_ tracks: [ListenLaterItem], currentIndex: Int) {
        print("[Cache Info] 🎠 ACTIVE carousel cache requested for index: \(currentIndex)")
        cacheCarouselAdjacent(tracks, currentIndex: currentIndex)
    }
    
    /// ピックアップ楽曲を一括キャッシュ
    func cachePickedTracks(_ pickedTracks: [ListenLaterItem]) {
        cacheManager.preloadPickedTracks(pickedTracks)
    }
    
    /// キャッシュをクリア
    func clearPreviewCache() {
        cacheManager.clearCache()
    }
    
    /// キャッシュ状態をデバッグ出力
    func debugCacheStatus() {
        cacheManager.debugCacheStatus()
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