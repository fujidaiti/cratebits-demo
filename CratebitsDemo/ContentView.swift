//
//  ContentView.swift
//  CratebitsDemo
//
//  Created by Daichi Fujita on 2025/07/16.
//

import SwiftUI
import MusicKit
#if os(iOS)
import UIKit
#endif

struct ContentView: View {
    @StateObject private var authService = MusicAuthService()
    @EnvironmentObject var storage: UserDefaultsStorage
    @EnvironmentObject var musicPlayer: MusicPlayerService
    
    var body: some View {
        Group {
            if authService.isAuthorized {
                MainTabView()
                    .environmentObject(authService)
            } else {
                WelcomeView(authService: authService)
            }
        }
        .onAppear {
            authService.checkAuthorizationStatus()
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // アプリがフォアグラウンドに戻った時に共有アイテムを同期
            storage.syncSharedItems()
        }
        #endif
    }
}

/// メインのタブビュー
struct MainTabView: View {
    @EnvironmentObject var storage: UserDefaultsStorage
    @EnvironmentObject var musicPlayer: MusicPlayerService
    
    var body: some View {
        TabView {
            ListenNowView()
                .tabItem {
                    Label("Listen Now", systemImage: "play.circle")
                }
            
            ListenLaterView()
                .tabItem {
                    Label("Listen Later", systemImage: "bookmark")
                }
            
            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}

#Preview {
    ContentView()
}
