//
//  ListenNowView.swift
//  CratebitsDemo
//
//  Created by Claude on 2025/07/16.
//

import SwiftUI
import MusicKit

/// Listen Now機能のメインビュー - TikTok風の音楽発見UI
struct ListenNowView: View {
    @EnvironmentObject var storage: UserDefaultsStorage
    @EnvironmentObject var musicPlayer: MusicPlayerService
    @EnvironmentObject var toastManager: ToastManager
    @StateObject private var playlistGenerator = PlaylistGenerationService()
    @StateObject private var libraryService = AppleMusicLibraryService()
    @State private var currentIndex: Int? = 0
    @State private var scrolledPageID: Int? // スクロール位置の実際の検知用
    @State private var debounceTask: Task<Void, Never>? // デバウンス処理用
    @State private var pageTrackIndexes: [Int: Int] = [:] // ページ別カルーセルインデックスの管理
    
    var body: some View {
        NavigationView {
            ZStack {
                if storage.listenNowQueue.isEmpty {
                    emptyStateView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    GeometryReader { geometry in
                        listenNowCarousel(geometry: geometry)
                    }
                    .ignoresSafeArea(.container, edges: .bottom)
                }
            }
            .navigationTitle("Listen Now")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("New Queue") {
                        generateNewQueue()
                    }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    Button("New Queue") {
                        generateNewQueue()
                    }
                }
                #endif
            }
        }
#if os(iOS)
        .navigationViewStyle(.stack)
        #endif
        .onAppear {
            print("[ListenNow Debug] 🚀 View appeared with queue count: \(storage.listenNowQueue.count)")
            // 既存のキューがある場合はキャッシュシステムを初期化（バックグラウンドで実行）
            if !storage.listenNowQueue.isEmpty {
                print("[ListenNow Debug] 🔄 Initializing cache with existing queue")
                musicPlayer.updateListenNowItems(storage.listenNowQueue)
                print("[ListenNow Debug] 🔄 Cache initialization started in background")
            } else {
                print("[ListenNow Debug] 📭 No existing queue found")
            }
        }
    }
    
    /// TikTok風の楽曲カルーセル表示（縦スクロール）
    private func listenNowCarousel(geometry: GeometryProxy) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(storage.listenNowQueue.indices, id: \.self) { index in
                        ListenNowCardView(
                            item: storage.listenNowQueue[index],
                            pageIndex: index,
                            onEvaluate: { evaluation in
                                handleEvaluation(evaluation, for: storage.listenNowQueue[index])
                            },
                            onPlay: {
                                playCurrentItem()
                            },
                            onPreview: { trackIndex in
                                playPreviewAndEnterMode(for: storage.listenNowQueue[index], trackIndex: trackIndex)
                            },
                            onTrackIndexChange: { trackIndex in
                                // カルーセルインデックス変更時にページ別状態を保存
                                pageTrackIndexes[index] = trackIndex
                                print("[ListenNow Debug] 💾 Saved track index \(trackIndex) for page \(index)")
                            },
                            initialTrackIndex: pageTrackIndexes[index] ?? 0
                        )
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .id(index)
                        .onAppear {
                            print("[ListenNow Debug] 👁 Card \(index) appeared: '\(storage.listenNowQueue[index].name)'")
                            // ページ初回表示時は保存されたカルーセル状態を復元、なければ0で初期化
                            if pageTrackIndexes[index] == nil {
                                pageTrackIndexes[index] = 0
                                print("[ListenNow Debug] 🎯 Initialized track index 0 for new page \(index)")
                            } else {
                                print("[ListenNow Debug] 🎯 Page \(index) has saved track index: \(pageTrackIndexes[index]!)")
                            }
                        }
                        .onDisappear {
                            print("[ListenNow Debug] 👁 Card \(index) disappeared: '\(storage.listenNowQueue[index].name)'")
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrolledPageID)
            .onChange(of: scrolledPageID) { oldPageID, newPageID in
                print("[ListenNow Debug] 🔍 scrolledPageID onChange triggered: \(String(describing: oldPageID)) -> \(String(describing: newPageID))")
                handlePageChange(to: newPageID)
            }
            .onAppear {
                // 初期表示時のscrolledPageIDを設定
                scrolledPageID = currentIndex
                print("[ListenNow Debug] 🚀 Carousel onAppear: set scrolledPageID to \(String(describing: currentIndex))")
            }
        }
    }
    
    /// ページ変更時の処理
    private func handlePageChange(to newPageID: Int?) {
        print("[ListenNow Debug] 🔄 handlePageChange called with pageID: \(String(describing: newPageID))")
        print("[ListenNow Debug] 🔄 Current preview mode status: \(musicPlayer.isPreviewMode)")
        print("[ListenNow Debug] 🔄 Queue count: \(storage.listenNowQueue.count)")
        
        guard let newPageID = newPageID, newPageID < storage.listenNowQueue.count else { 
            print("[ListenNow Debug] ❌ handlePageChange: Invalid pageID - newPageID: \(String(describing: newPageID)), queue count: \(storage.listenNowQueue.count)")
            return 
        }
        
        print("[ListenNow Debug] ✅ ScrolledPageID changed to: \(newPageID)")
        
        // currentIndexを即座に更新（UI応答性のため）
        let oldCurrentIndex = currentIndex
        currentIndex = newPageID
        print("[ListenNow Debug] 📍 Updated currentIndex from \(String(describing: oldCurrentIndex)) to \(newPageID)")
        
        let item = storage.listenNowQueue[newPageID]
        print("[ListenNow Debug] 📄 NAVIGATED TO PAGE \(newPageID): '\(item.name)' (type: \(item.type))")
        
        // プレビューモード中のみキャッシュシステムでフォーカス変更を処理
        if musicPlayer.isPreviewMode {
            print("[ListenNow Debug] 🎯 Preview mode active - Calling handleFocusChange(to: \(newPageID))")
            musicPlayer.handleFocusChange(to: newPageID)
            print("[ListenNow Debug] 🎯 handleFocusChange started in background")
        } else {
            print("[ListenNow Debug] 🎯 Preview mode inactive - Skipping handleFocusChange to avoid unnecessary preloading")
        }
        
        // プレビューモード中はデバウンス処理でプレビューを切り替え
        if musicPlayer.isPreviewMode {
            print("[ListenNow Debug] 🎧 ✅ Preview mode is ACTIVE, starting debounced preview for: \(item.name)")
            
            // 前のタスクをキャンセル
            debounceTask?.cancel()
            print("[ListenNow Debug] 🎧 ⏹ Cancelled previous debounce task")
            
            // 新しいデバウンスタスクを開始
            debounceTask = Task {
                do {
                    print("[ListenNow Debug] 🎧 ⏱ Starting 300ms debounce wait...")
                    try await Task.sleep(nanoseconds: 300_000_000) // 300ms待機
                    
                    if !Task.isCancelled {
                        print("[ListenNow Debug] 🎧 ✅ Debounce completed: Auto-switching preview to: \(item.name)")
                        
                        // ピックアップトラックがある場合は保存されたインデックスのトラックを再生
                        if let pickedTracks = item.pickedTracks, !pickedTracks.isEmpty {
                            let savedTrackIndex = pageTrackIndexes[newPageID] ?? 0
                            let trackToPlay = pickedTracks[min(savedTrackIndex, pickedTracks.count - 1)]
                            print("[ListenNow Debug] 🎧 🎵 Playing picked track [\(savedTrackIndex)]: \(trackToPlay.name)")
                            await musicPlayer.playPreviewInstantly(for: trackToPlay)
                        } else {
                            print("[ListenNow Debug] 🎧 🎵 Playing main item: \(item.name)")
                            await musicPlayer.playPreviewInstantly(for: item)
                        }
                        print("[ListenNow Debug] 🎧 ✅ Preview playback request sent")
                    } else {
                        print("[ListenNow Debug] 🎧 ❌ Debounce task was cancelled")
                    }
                } catch {
                    print("[ListenNow Debug] 🎧 ❌ Page preview switch task cancelled: \(error)")
                }
            }
        } else {
            print("[ListenNow Debug] 🎧 ❌ Preview mode is NOT active - no automatic preview switching")
        }
    }
    
    /// 空状態の表示
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note")
                .font(.system(size: 80))
                .foregroundColor(.gray)
            
            Text("Listen Now")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Add items to Listen Later to start discovering music")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            if !storage.items.isEmpty {
                Button("Generate Queue") {
                    generateNewQueue()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top)
            }
            
            // プレイヤー制御（再生中の場合のみ表示）
            if musicPlayer.isPlaying {
                playerControls
                    .padding(.top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    /// プレイヤー制御
    private var playerControls: some View {
        VStack {
            Text("Now Playing")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(musicPlayer.currentTrack ?? "Unknown")
                .font(.headline)
                .lineLimit(1)
            
            Text(musicPlayer.playbackStatus)
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                Button(action: { Task { await musicPlayer.skipToPrevious() } }) {
                    Image(systemName: "backward.fill")
                }
                
                Button(action: { 
                    if musicPlayer.isPlaying {
                        musicPlayer.pause()
                    } else {
                        Task { await musicPlayer.resume() }
                    }
                }) {
                    Image(systemName: musicPlayer.isPlaying ? "pause.fill" : "play.fill")
                }
                
                Button(action: { Task { await musicPlayer.skipToNext() } }) {
                    Image(systemName: "forward.fill")
                }
                
                Button(action: { musicPlayer.stop() }) {
                    Image(systemName: "stop.fill")
                }
            }
            .buttonStyle(.borderless)
            .font(.title2)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
        .padding(.horizontal)
    }
    
    /// 新しいキューを生成
    private func generateNewQueue() {
        let randomItems = playlistGenerator.generateRandomListenNow(from: storage.items, count: 10)
        
        Task {
            let expandedTracks = await playlistGenerator.expandMixedItemsToTracks(randomItems)
            
            await MainActor.run {
                storage.saveListenNowQueue(expandedTracks)
                currentIndex = 0
                toastManager.show("🎵 New queue generated!", type: .success)
            }
            
            // 新しいキューを音楽プレイヤーのキャッシュシステムに通知（バックグラウンドで実行）
            print("[ListenNow Debug] 🔄 About to call updateListenNowItems with \(expandedTracks.count) items")
            musicPlayer.updateListenNowItems(expandedTracks)
            print("[ListenNow Debug] 🔄 updateListenNowItems started in background")
        }
    }
    
    /// 現在のアイテムを再生
    private func playCurrentItem() {
        guard let index = currentIndex, index < storage.listenNowQueue.count else { return }
        let item = storage.listenNowQueue[index]
        
        if item.type == .track, let appleMusicID = item.appleMusicID {
            Task {
                do {
                    let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(appleMusicID))
                    let response = try await request.response()
                    
                    if let song = response.items.first {
                        await musicPlayer.playSong(song)
                        await MainActor.run {
                            toastManager.show("🎵 Now playing: \(song.title)", type: .success)
                        }
                    }
                } catch {
                    await MainActor.run {
                        toastManager.show("❌ Failed to play song", type: .error)
                    }
                    print("Error playing song: \(error)")
                }
            }
        } else {
            toastManager.show("⚠️ Full playback not implemented for \(item.type.displayName)", type: .warning)
        }
    }
    
    /// プレビューを開始してプレビューモードに入る
    private func playPreviewAndEnterMode(for item: ListenLaterItem, trackIndex: Int?) {
        print("[ListenNow Debug] 🎧 🚀 playPreviewAndEnterMode called for: \(item.name)")
        print("[ListenNow Debug] 🎧 🚀 trackIndex: \(String(describing: trackIndex))")
        print("[ListenNow Debug] 🎧 🚀 Entering preview mode...")
        
        musicPlayer.enterPreviewMode()
        
        print("[ListenNow Debug] 🎧 ✅ Preview mode entered, status: \(musicPlayer.isPreviewMode)")
        
        Task {
            // ピックアップトラックがある場合（アルバム・アーティスト）でtrackIndexが指定されている場合は、そのトラックを再生
            if let trackIndex = trackIndex,
               let pickedTracks = item.pickedTracks,
               trackIndex < pickedTracks.count {
                print("[ListenNow Debug] 🎧 🎵 Playing picked track [\(trackIndex)]: \(pickedTracks[trackIndex].name)")
                await musicPlayer.playPreviewInstantly(for: pickedTracks[trackIndex])
            } else {
                // 単一トラックまたはtrackIndexが未指定の場合は、元のアイテムを再生
                print("[ListenNow Debug] 🎧 🎵 Playing main item: \(item.name)")
                await musicPlayer.playPreviewInstantly(for: item)
            }
        }
    }
    
    /// アイテムのプレビューを再生
    private func playPreview(for item: ListenLaterItem) {
        guard let appleMusicID = item.appleMusicID else { 
            toastManager.show("❌ No Apple Music ID available", type: .error)
            return 
        }
        
        Task {
            do {
                switch item.type {
                case .track:
                    let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(appleMusicID))
                    let response = try await request.response()
                    
                    if let song = response.items.first {
                        await musicPlayer.playPreview(song)
                        await MainActor.run {
                            toastManager.show("🎧 Preview playing", type: .info)
                        }
                    }
                    
                case .album, .artist:
                    // アルバム/アーティストの場合は未実装
                    await MainActor.run {
                        toastManager.show("⚠️ Preview not implemented for \(item.type.displayName)", type: .warning)
                    }
                }
            } catch {
                await MainActor.run {
                    toastManager.show("❌ Failed to play preview", type: .error)
                }
                print("Error playing preview: \(error)")
            }
        }
    }
    
    /// 評価処理
    private func handleEvaluation(_ evaluation: EvaluationType, for item: ListenLaterItem) {
        // 評価をストレージに保存
        let musicEvaluation = MusicEvaluation(
            itemId: item.id,
            evaluation: evaluation,
            dateEvaluated: Date()
        )
        storage.addEvaluation(musicEvaluation)
        
        // 評価に応じた処理
        switch evaluation {
        case .like:
            // Like: Apple Musicライブラリに保存してListen Laterから削除
            Task {
                let success = await libraryService.addToLibrary(item)
                await MainActor.run {
                    if success {
                        storage.removeItem(id: item.id)
                        toastManager.show("👍 Added to Apple Music Library!", type: .success)
                    } else {
                        // macOSでは機能が制限されているため、Listen Laterから削除のみ行う
                        #if os(macOS)
                        storage.removeItem(id: item.id)
                        toastManager.show("👍 Liked! (Library save not supported on macOS)", type: .info)
                        #else
                        toastManager.show("❌ Failed to add to library. Check Apple Music authorization.", type: .error)
                        #endif
                    }
                }
            }
            
        case .notForMe:
            // Not For Me: Listen Laterから削除
            storage.removeItem(id: item.id)
            toastManager.show("👎 Removed from Listen Later", type: .success)
            
        case .listenAgainLater:
            // Listen Again Later: キューから削除のみ
            toastManager.show("⏰ Added back to Listen Later", type: .info)
        }
        
        // 次のアイテムに移動
        moveToNextItem()
    }
    
    /// 次のアイテムに移動
    private func moveToNextItem() {
        guard let index = currentIndex else { return }
        if index < storage.listenNowQueue.count - 1 {
            currentIndex = index + 1
        } else {
            // キューの最後に到達したらトーストで案内
            toastManager.show("🔄 End of queue. Tap 'New Queue' to generate more!", type: .info)
        }
    }
    
}


/// Listen Nowカード表示ビュー
struct ListenNowCardView: View {
    let item: ListenLaterItem
    let pageIndex: Int
    let onEvaluate: (EvaluationType) -> Void
    let onPlay: () -> Void
    let onPreview: (Int?) -> Void
    let onTrackIndexChange: ((Int) -> Void)? // カルーセルインデックス変更のコールバック
    let initialTrackIndex: Int // 初期トラックインデックス
    
    @EnvironmentObject var musicPlayer: MusicPlayerService
    @State private var currentTrackIndex = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // メインコンテンツ（従来の下部ボタンを除いた部分）
                VStack(spacing: 0) {
                    Spacer(minLength: 30)
                    
                    // アイテム情報表示
                    VStack(spacing: 20) {
                        // タイプアイコン
                        Image(systemName: iconName)
                            .font(.system(size: 80))
                            .foregroundColor(iconColor)
                        
                        // タイトル
                        Text(item.name)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                        
                        // アーティスト名
                        Text(item.artist)
                            .font(.title)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                        
                        // タイプ表示
                        Text(item.type.displayName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(10)
                    }
                    .padding(.horizontal, 60)
                    
                    Spacer(minLength: 30)
                    
                    // ピックアップ楽曲カルーセル（アルバム/アーティストの場合のみ）
                    if let pickedTracks = item.pickedTracks, !pickedTracks.isEmpty {
                        TrackCarouselView(
                            tracks: pickedTracks,
                            currentIndex: $currentTrackIndex,
                            onTrackPreview: { track in
                                // プレビューモード中は自動的にピックアップ楽曲のプレビューを再生
                                if musicPlayer.isPreviewMode {
                                    Task {
                                        await musicPlayer.playPreviewInstantly(for: track)
                                    }
                                }
                            },
                            onCarouselIndexChange: { trackIndex in
                                // カルーセル内移動時のキャッシュ処理（バックグラウンドで実行）
                                musicPlayer.handleCarouselFocusChange(to: pageIndex, trackIndex: trackIndex)
                                // 親ビューにトラックインデックス変更を通知
                                onTrackIndexChange?(trackIndex)
                            }
                        )
                        .frame(height: 180)
                        .padding(.bottom, 40)
                    }
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    LinearGradient(
                        colors: [Color.clear, iconColor.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                
                // TikTok風右側縦並びボタン列
                VStack(spacing: 24) {
                    // 評価ボタン
                    ForEach(EvaluationType.allCases, id: \.self) { evaluation in
                        Button(action: {
                            onEvaluate(evaluation)
                        }) {
                            VStack(spacing: 6) {
                                Image(systemName: evaluation.systemImage)
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                Text(evaluation.displayName)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(evaluation.color)
                            .frame(width: 60, height: 60)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                    
                    // 区切り線
                    Rectangle()
                        .fill(Color.gray.opacity(0.4))
                        .frame(width: 30, height: 1)
                    
                    // プレビューボタン
                    Button(action: { 
                        if musicPlayer.isPreviewMode {
                            // プレビューモード中の場合は終了
                            musicPlayer.exitPreviewMode()
                        } else {
                            // 非プレビューモードの場合は開始
                            if item.pickedTracks != nil {
                                onPreview(currentTrackIndex)
                            } else {
                                onPreview(nil)
                            }
                        }
                    }) {
                        VStack(spacing: 6) {
                            Image(systemName: musicPlayer.isPreviewMode ? "pause.circle.fill" : "play.circle.fill")
                                .font(.title2)
                                .fontWeight(.semibold)
                            Text("Preview")
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.orange)
                        .frame(width: 60, height: 60)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                    }
                    
                    // 再生ボタン
                    Button(action: onPlay) {
                        VStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.title2)
                                .fontWeight(.semibold)
                            Text("Play")
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.blue)
                        .frame(width: 60, height: 60)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                .position(x: geometry.size.width - 45, y: geometry.size.height / 2)
                .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // 初期トラックインデックスでカルーセル状態を初期化
            currentTrackIndex = initialTrackIndex
            print("[ListenNow Debug] 🎯 CardView initialized with track index: \(initialTrackIndex) for page \(pageIndex)")
        }
    }
    
    private var iconName: String {
        switch item.type {
        case .track: return "music.note"
        case .album: return "square.stack"
        case .artist: return "person.circle"
        }
    }
    
    private var iconColor: Color {
        switch item.type {
        case .track: return .blue
        case .album: return .green
        case .artist: return .purple
        }
    }
}


/// 楽曲の横スクロールカルーセルビュー
struct TrackCarouselView: View {
    let tracks: [ListenLaterItem]
    @Binding var currentIndex: Int
    let onTrackPreview: (ListenLaterItem) -> Void
    let onCarouselIndexChange: ((Int) -> Void)? // カルーセルインデックス変更時のコールバック（オプショナル）
    
    @EnvironmentObject var musicPlayer: MusicPlayerService
    @State private var scrolledID: Int?
    @State private var debounceTask: Task<Void, Never>?
    
    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let cardWidth = screenWidth * 0.6  // カード幅を少し小さく
            let spacing: CGFloat = 20
            let sideInset = (screenWidth - cardWidth) / 2  // 隣接カードが見えるためのインセット
            
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: spacing) {
                        ForEach(tracks.indices, id: \.self) { index in
                            TrackCardView(
                                track: tracks[index]
                            )
                            .frame(width: cardWidth)
                            .id(index)
                        }
                    }
                    .padding(.horizontal, sideInset)  // 左右にパディングを追加
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $scrolledID)
                .onChange(of: scrolledID) { _, newID in
                    guard let newID = newID, newID < tracks.count else { return }
                    
                    print("[Carousel Debug] ScrolledID changed to: \(newID)")
                    
                    // currentIndexを即座に更新（UI応答性のため）
                    currentIndex = newID
                    
                    // プレビューモード中はデバウンス処理でプレビューを切り替え
                    if musicPlayer.isPreviewMode {
                        // 前のタスクをキャンセル
                        debounceTask?.cancel()
                        
                        // 新しいデバウンスタスクを開始
                        debounceTask = Task {
                            do {
                                try await Task.sleep(nanoseconds: 300_000_000) // 300ms待機
                                
                                if !Task.isCancelled {
                                    print("[Carousel Debug] Debounced: Auto-switching preview to track: \(tracks[newID].name)")
                                    onTrackPreview(tracks[newID])
                                    
                                    print("[Carousel Debug] Debounced: Notifying parent of carousel index change: \(newID)")
                                    onCarouselIndexChange?(newID)
                                }
                            } catch {
                                // Task.sleep がキャンセルされた場合
                                print("[Carousel Debug] Debounce task cancelled")
                            }
                        }
                    }
                }
                .onAppear {
                    // 初期表示時のscrolledIDを設定
                    scrolledID = currentIndex
                    // 初期表示時のキャッシュとプレビュー
                    setupInitialState()
                }
                .onDisappear {
                    // ビューが消える時にデバウンスタスクをキャンセル
                    debounceTask?.cancel()
                }
            }
        }
    }
    
    
    
    /// 初期状態のセットアップ
    private func setupInitialState() {
        // プレビューモード中の場合、現在のトラックのプレビューを開始
        if musicPlayer.isPreviewMode && currentIndex < tracks.count {
            print("[Carousel Debug] Initial preview for track: \(tracks[currentIndex].name)")
            onTrackPreview(tracks[currentIndex])
            // プレビューモード中の場合のみキャッシュ処理を通知
            onCarouselIndexChange?(currentIndex)
        }
    }
}

/// 個別楽曲カードビュー
struct TrackCardView: View {
    let track: ListenLaterItem
    
    var body: some View {
        VStack {
            // 楽曲タイトルのみ表示
            Text(track.name)
                .font(.title3)
                .fontWeight(.medium)
                .lineLimit(4)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, minHeight: 100)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 30)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.08))
        )
    }
}

#Preview {
    ListenNowView()
        .environmentObject(UserDefaultsStorage())
        .environmentObject(MusicPlayerService())
        .environmentObject(ToastManager())
}