//
//  WelcomeView.swift
//  CratebitsDemo
//
//  Created by Claude on 2025/07/16.
//

import SwiftUI
import MusicKit
#if os(iOS)
import UIKit
#endif

/// アプリの紹介とMusicKit認証を行うビュー
struct WelcomeView: View {
    @ObservedObject var authService: MusicAuthService
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        VStack(spacing: 20) {
            // アプリタイトル
            Text("Cratebits")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top)
            
            // サブタイトル
            Text("あなたの音楽を再発見")
                .font(.title2)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
            
            // 説明文
            explanatoryText
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // 追加の説明文（認証が拒否された場合）
            if let secondaryText = secondaryExplanatoryText {
                secondaryText
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 認証ボタン
            if authService.authorizationStatus == .notDetermined || authService.authorizationStatus == .denied {
                Button(action: handleButtonPressed) {
                    Text(buttonText)
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
            }
            
            Spacer()
        }
        .padding()
    }
    
    /// 説明文
    private var explanatoryText: Text {
        switch authService.authorizationStatus {
        case .restricted:
            return Text("このiPhoneではApple Musicの使用が制限されています。")
        default:
            return Text("CratebitsはApple Musicと連携して、あなたの音楽体験を向上させます。")
        }
    }
    
    /// 追加の説明文
    private var secondaryExplanatoryText: Text? {
        switch authService.authorizationStatus {
        case .denied:
            return Text("設定からCratebitsにApple Musicへのアクセスを許可してください。")
        default:
            return nil
        }
    }
    
    /// ボタンのテキスト
    private var buttonText: String {
        switch authService.authorizationStatus {
        case .notDetermined:
            return "続ける"
        case .denied:
            return "設定を開く"
        default:
            return "続ける"
        }
    }
    
    /// ボタンが押された時の処理
    private func handleButtonPressed() {
        switch authService.authorizationStatus {
        case .notDetermined:
            Task {
                await authService.requestAuthorization()
            }
        case .denied:
            #if os(iOS)
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                openURL(settingsURL)
            }
            #endif
        default:
            break
        }
    }
}

#Preview {
    WelcomeView(authService: MusicAuthService())
}