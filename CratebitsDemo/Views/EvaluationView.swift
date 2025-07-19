//
//  EvaluationView.swift
//  CratebitsDemo
//
//  Created by Claude on 2025/07/16.
//

import SwiftUI

/// 音楽評価のためのビュー
struct EvaluationView: View {
    let item: ListenLaterItem
    @EnvironmentObject var storage: UserDefaultsStorage
    @Environment(\.dismiss) private var dismiss
    @State private var selectedEvaluation: EvaluationType?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // アイテム情報
                itemInfoSection
                
                // 評価ボタン
                evaluationButtonsSection
                
                // 現在の評価
                currentEvaluationSection
                
                Spacer()
            }
            .padding()
            .navigationTitle("Evaluate")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveEvaluation()
                    }
                    .disabled(selectedEvaluation == nil)
                }
                #else
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveEvaluation()
                    }
                    .disabled(selectedEvaluation == nil)
                }
                #endif
            }
        }
        .onAppear {
            // 既存の評価を読み込み
            if let evaluation = storage.evaluation(for: item.id) {
                selectedEvaluation = evaluation.evaluation
            }
        }
    }
    
    /// アイテム情報セクション
    private var itemInfoSection: some View {
        VStack {
            Image(systemName: iconName)
                .font(.system(size: 60))
                .foregroundColor(iconColor)
            
            Text(item.displayText)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
            
            Text(item.type.displayName)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    /// 評価ボタンセクション
    private var evaluationButtonsSection: some View {
        VStack(spacing: 16) {
            Text("How do you feel about this?")
                .font(.headline)
            
            VStack(spacing: 12) {
                ForEach(EvaluationType.allCases, id: \.self) { evaluation in
                    EvaluationButton(
                        evaluation: evaluation,
                        isSelected: selectedEvaluation == evaluation
                    ) {
                        selectedEvaluation = evaluation
                    }
                }
            }
        }
    }
    
    /// 現在の評価セクション
    private var currentEvaluationSection: some View {
        Group {
            if let currentEvaluation = storage.evaluation(for: item.id) {
                VStack {
                    Text("Previous Evaluation")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Image(systemName: currentEvaluation.evaluation.systemImage)
                            .foregroundColor(.orange)
                        
                        Text(currentEvaluation.evaluation.displayName)
                            .font(.body)
                        
                        Text("(\(currentEvaluation.date, formatter: dateFormatter))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }
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
    
    /// 評価を保存
    private func saveEvaluation() {
        guard let evaluation = selectedEvaluation else { return }
        
        let musicEvaluation = MusicEvaluation(
            itemId: item.id,
            evaluation: evaluation,
            dateEvaluated: Date()
        )
        
        storage.addEvaluation(musicEvaluation)
        dismiss()
    }
}

/// 評価ボタン
struct EvaluationButton: View {
    let evaluation: EvaluationType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: evaluation.systemImage)
                    .font(.title2)
                
                Text(evaluation.displayName)
                    .font(.headline)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.1) : Color.secondary.opacity(0.1))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

/// 日付フォーマッター
private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter
}()

#Preview {
    EvaluationView(item: ListenLaterItem.track(name: "Sample Track", artist: "Sample Artist"))
        .environmentObject(UserDefaultsStorage())
}