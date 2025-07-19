//
//  UserDefaultsStorage.swift
//  CratebitsDemo
//
//  Created by Claude on 2025/07/16.
//

import Foundation
import Combine

/// UserDefaultsを使ったシンプルな永続化システム
class UserDefaultsStorage: ObservableObject {
    @Published var items: [ListenLaterItem] = []
    @Published var evaluations: [MusicEvaluation] = []
    @Published var listenNowQueue: [ListenLaterItem] = []
    
    private let itemsStorageKey = "listen_later_items"
    private let evaluationsStorageKey = "music_evaluations"
    private let listenNowQueueKey = "listen_now_queue"
    
    init() {
        loadItems()
        loadEvaluations()
        loadListenNowQueue()
        processSharedItems()
    }
    
    // MARK: - Listen Later Items
    
    /// アイテムを追加
    func addItem(_ item: ListenLaterItem) {
        // 重複チェック
        if !items.contains(where: { $0.appleMusicID == item.appleMusicID && $0.type == item.type }) {
            items.append(item)
            saveItems()
        }
    }
    
    /// アイテムを削除
    func removeItem(id: String) {
        items.removeAll { $0.id == id }
        saveItems()
    }
    
    /// 指定したタイプのアイテムを取得
    func items(of type: ItemType) -> [ListenLaterItem] {
        return items.filter { $0.type == type }
    }
    
    /// アイテムをUserDefaultsに保存
    private func saveItems() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: itemsStorageKey)
        }
    }
    
    /// アイテムをUserDefaultsから読み込み
    private func loadItems() {
        if let data = UserDefaults.standard.data(forKey: itemsStorageKey),
           let decoded = try? JSONDecoder().decode([ListenLaterItem].self, from: data) {
            items = decoded
        }
    }
    
    // MARK: - Music Evaluations
    
    /// 評価を追加
    func addEvaluation(_ evaluation: MusicEvaluation) {
        // 同じアイテムの古い評価を削除
        evaluations.removeAll { $0.itemId == evaluation.itemId }
        evaluations.append(evaluation)
        saveEvaluations()
    }
    
    /// 指定したアイテムの評価を取得
    func evaluation(for itemId: String) -> MusicEvaluation? {
        return evaluations.first { $0.itemId == itemId }
    }
    
    /// 評価をUserDefaultsに保存
    private func saveEvaluations() {
        if let data = try? JSONEncoder().encode(evaluations) {
            UserDefaults.standard.set(data, forKey: evaluationsStorageKey)
        }
    }
    
    /// 評価をUserDefaultsから読み込み
    private func loadEvaluations() {
        if let data = UserDefaults.standard.data(forKey: evaluationsStorageKey),
           let decoded = try? JSONDecoder().decode([MusicEvaluation].self, from: data) {
            evaluations = decoded
        }
    }
    
    // MARK: - Listen Now Queue
    
    /// ListenNowキューを保存
    func saveListenNowQueue(_ queue: [ListenLaterItem]) {
        listenNowQueue = queue
        if let data = try? JSONEncoder().encode(queue) {
            UserDefaults.standard.set(data, forKey: listenNowQueueKey)
        }
    }
    
    /// ListenNowキューをクリア
    func clearListenNowQueue() {
        listenNowQueue.removeAll()
        UserDefaults.standard.removeObject(forKey: listenNowQueueKey)
    }
    
    /// ListenNowキューをUserDefaultsから読み込み
    private func loadListenNowQueue() {
        if let data = UserDefaults.standard.data(forKey: listenNowQueueKey),
           let decoded = try? JSONDecoder().decode([ListenLaterItem].self, from: data) {
            listenNowQueue = decoded
        }
    }
    
    // MARK: - Utility
    
    /// 全データをクリア
    func clearAllData() {
        items.removeAll()
        evaluations.removeAll()
        listenNowQueue.removeAll()
        UserDefaults.standard.removeObject(forKey: itemsStorageKey)
        UserDefaults.standard.removeObject(forKey: evaluationsStorageKey)
        UserDefaults.standard.removeObject(forKey: listenNowQueueKey)
    }
    
    // MARK: - Share Extension Integration
    
    /// 共有されたアイテムを処理
    private func processSharedItems() {
        let sharedItems = ShareHandlingService.getSharedItems()
        
        for sharedItem in sharedItems {
            addItem(sharedItem)
        }
        
        // 処理完了後、共有されたアイテムをクリア
        if !sharedItems.isEmpty {
            ShareHandlingService.clearSharedItems()
        }
    }
    
    /// 共有されたアイテムを手動で同期
    func syncSharedItems() {
        processSharedItems()
    }
}