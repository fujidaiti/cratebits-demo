//
//  SettingsView.swift
//  CratebitsDemo
//
//  Created by Claude on 2025/07/16.
//

import SwiftUI
import MusicKit

/// 設定画面
struct SettingsView: View {
    @EnvironmentObject var storage: UserDefaultsStorage
    @EnvironmentObject var authService: MusicAuthService
    @State private var showingClearAlert = false
    
    var body: some View {
        NavigationView {
            Form {
                // Apple Music連携状態
                musicStatusSection
                
                // 統計情報
                statisticsSection
                
                // アクション
                actionsSection
                
                // アプリ情報
                aboutSection
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .alert("Clear All Data", isPresented: $showingClearAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) {
                    storage.clearAllData()
                }
            } message: {
                Text("This will remove all Listen Later items and evaluations. This action cannot be undone.")
            }
        }
    }
    
    /// Apple Music連携状態セクション
    private var musicStatusSection: some View {
        Section("Apple Music") {
            HStack {
                Image(systemName: "music.note")
                    .foregroundColor(.red)
                
                VStack(alignment: .leading) {
                    Text("Apple Music")
                        .font(.headline)
                    
                    Text(authorizationStatusText)
                        .font(.caption)
                        .foregroundColor(authorizationStatusColor)
                }
                
                Spacer()
                
                Image(systemName: authService.isAuthorized ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(authService.isAuthorized ? .green : .red)
            }
            
            if !authService.isAuthorized {
                Button("Request Authorization") {
                    Task {
                        await authService.requestAuthorization()
                    }
                }
            }
        }
    }
    
    /// 統計情報セクション
    private var statisticsSection: some View {
        Section("Statistics") {
            StatisticRow(title: "Total Items", value: "\(storage.items.count)")
            StatisticRow(title: "Tracks", value: "\(storage.items(of: .track).count)")
            StatisticRow(title: "Albums", value: "\(storage.items(of: .album).count)")
            StatisticRow(title: "Artists", value: "\(storage.items(of: .artist).count)")
            StatisticRow(title: "Evaluations", value: "\(storage.evaluations.count)")
        }
    }
    
    /// アクションセクション
    private var actionsSection: some View {
        Section("Actions") {
            Button("Sync Shared Items") {
                storage.syncSharedItems()
            }
            
            Button("Clear All Data", role: .destructive) {
                showingClearAlert = true
            }
            .disabled(storage.items.isEmpty && storage.evaluations.isEmpty)
            
            Button("Refresh Authorization Status") {
                authService.checkAuthorizationStatus()
            }
        }
    }
    
    /// アプリ情報セクション
    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("App Name")
                Spacer()
                Text("Cratebits")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Version")
                Spacer()
                Text("1.0.0")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Framework")
                Spacer()
                Text("MusicKit")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Platform")
                Spacer()
                Text("iOS")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    /// 認証状態のテキスト
    private var authorizationStatusText: String {
        switch authService.authorizationStatus {
        case .authorized:
            return "Connected"
        case .denied:
            return "Access Denied"
        case .notDetermined:
            return "Not Requested"
        case .restricted:
            return "Restricted"
        @unknown default:
            return "Unknown"
        }
    }
    
    /// 認証状態の色
    private var authorizationStatusColor: Color {
        switch authService.authorizationStatus {
        case .authorized:
            return .green
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return .orange
        @unknown default:
            return .gray
        }
    }
}

/// 統計情報の行
struct StatisticRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(UserDefaultsStorage())
        .environmentObject(MusicAuthService())
}