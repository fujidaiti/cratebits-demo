//
//  MusicAuthService.swift
//  CratebitsDemo
//
//  Created by Claude on 2025/07/16.
//

import Foundation
import MusicKit
import Combine

/// MusicKit認証を管理するサービス
class MusicAuthService: ObservableObject {
    @Published var authorizationStatus: MusicAuthorization.Status = .notDetermined
    @Published var isAuthorized = false
    
    init() {
        authorizationStatus = MusicAuthorization.currentStatus
        isAuthorized = authorizationStatus == .authorized
    }
    
    /// Apple Music使用許可をリクエスト
    func requestAuthorization() async {
        let status = await MusicAuthorization.request()
        await MainActor.run {
            self.authorizationStatus = status
            self.isAuthorized = status == .authorized
        }
    }
    
    /// 認証状態をチェック
    func checkAuthorizationStatus() {
        let status = MusicAuthorization.currentStatus
        authorizationStatus = status
        isAuthorized = status == .authorized
    }
}