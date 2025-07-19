//
//  CratebitsDemoApp.swift
//  CratebitsDemo
//
//  Created by Daichi Fujita on 2025/07/16.
//

import SwiftUI
import MusicKit
import AVFoundation

@main
struct CratebitsDemoApp: App {
    @StateObject private var storage = UserDefaultsStorage()
    @StateObject private var musicPlayer = MusicPlayerService()
    @StateObject private var libraryService = AppleMusicLibraryService()
    
    init() {
        setupAudioSession()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(storage)
                .environmentObject(musicPlayer)
                .environmentObject(libraryService)
                .toast() // ToastManagerを提供
        }
    }
    
    /// オーディオセッションの設定
    private func setupAudioSession() {
        #if os(iOS)
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP])
            try audioSession.setActive(true)
            print("[Audio Setup] Audio session configured successfully")
        } catch {
            print("[Audio Error] Failed to setup audio session: \(error)")
        }
        #else
        print("[Audio Setup] Audio session setup not required on macOS")
        #endif
    }
}
