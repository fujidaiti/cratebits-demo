//
//  ToastView.swift
//  CratebitsDemo
//
//  Created by Claude on 2025/07/19.
//

import SwiftUI

/// トースト通知の種類
enum ToastType {
    case success
    case error
    case info
    case warning
    
    var color: Color {
        switch self {
        case .success: return .green
        case .error: return .red
        case .info: return .blue
        case .warning: return .orange
        }
    }
    
    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }
}

/// トースト通知の状態管理
class ToastManager: ObservableObject {
    @Published var isShowing = false
    @Published var message = ""
    @Published var type: ToastType = .info
    
    func show(_ message: String, type: ToastType = .info, duration: TimeInterval = 3.0) {
        self.message = message
        self.type = type
        
        withAnimation(.easeInOut(duration: 0.3)) {
            isShowing = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.isShowing = false
            }
        }
    }
    
    func hide() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isShowing = false
        }
    }
}

/// トースト通知ビュー
struct ToastView: View {
    @ObservedObject var toastManager: ToastManager
    
    var body: some View {
        VStack {
            Spacer()
            
            if toastManager.isShowing {
                HStack(spacing: 12) {
                    Image(systemName: toastManager.type.icon)
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .medium))
                    
                    Text(toastManager.message)
                        .foregroundColor(.white)
                        .font(.system(size: 14, weight: .medium))
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                    
                    Button(action: {
                        toastManager.hide()
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white.opacity(0.7))
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(toastManager.type.color.opacity(0.9))
                        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 100) // Safe area考慮
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
            }
        }
        .allowsHitTesting(toastManager.isShowing)
    }
}

/// ToastViewのModifier
struct ToastModifier: ViewModifier {
    @StateObject private var toastManager = ToastManager()
    
    func body(content: Content) -> some View {
        content
            .overlay(
                ToastView(toastManager: toastManager)
            )
            .environmentObject(toastManager)
    }
}

extension View {
    func toast() -> some View {
        self.modifier(ToastModifier())
    }
}

#Preview {
    VStack {
        Button("Show Success Toast") {
            // Preview用のダミー実装
        }
        .padding()
    }
    .toast()
}