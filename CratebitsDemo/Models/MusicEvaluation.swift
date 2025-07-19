//
//  MusicEvaluation.swift
//  CratebitsDemo
//
//  Created by Claude on 2025/07/16.
//

import Foundation
import SwiftUI

/// 音楽評価の種類
enum EvaluationType: String, CaseIterable, Codable {
    case like = "like"
    case notForMe = "not_for_me"
    case listenAgainLater = "listen_again_later"
    
    var displayName: String {
        switch self {
        case .like: return "Like"
        case .notForMe: return "Not For Me"
        case .listenAgainLater: return "Listen Again Later"
        }
    }
    
    var systemImage: String {
        switch self {
        case .like: return "heart.fill"
        case .notForMe: return "hand.thumbsdown.fill"
        case .listenAgainLater: return "clock.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .like: return .red
        case .notForMe: return .gray
        case .listenAgainLater: return .orange
        }
    }
}

/// 音楽の評価データ
struct MusicEvaluation: Identifiable, Codable {
    let id: String
    let itemId: String
    let itemType: ItemType
    let evaluation: EvaluationType
    let date: Date
    
    init(itemId: String, evaluation: EvaluationType, dateEvaluated: Date) {
        self.id = UUID().uuidString
        self.itemId = itemId
        self.itemType = .track // デフォルト値
        self.evaluation = evaluation
        self.date = dateEvaluated
    }
}