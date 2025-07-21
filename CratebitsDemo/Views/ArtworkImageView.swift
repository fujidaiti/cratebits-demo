//
//  ArtworkImageView.swift
//  CratebitsDemo
//
//  Created by Claude on 2025/07/21.
//

import SwiftUI

/// アートワーク画像を表示するビューコンポーネント
/// URLからアートワークを非同期に読み込み、フォールバック機能付き
struct ArtworkImageView: View {
    let artworkURL: URL?
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    let fallbackIcon: String
    let fallbackColor: Color
    
    init(
        artworkURL: URL?,
        width: CGFloat,
        height: CGFloat = 0,
        cornerRadius: CGFloat = 8,
        fallbackIcon: String = "music.note",
        fallbackColor: Color = .gray
    ) {
        self.artworkURL = artworkURL
        self.width = width
        self.height = height > 0 ? height : width
        self.cornerRadius = cornerRadius
        self.fallbackIcon = fallbackIcon
        self.fallbackColor = fallbackColor
    }
    
    var body: some View {
        Group {
            if let url = artworkURL {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: width, height: height)
                        .clipped()
                        .cornerRadius(cornerRadius)
                } placeholder: {
                    // ローディング中のプレースホルダー
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: width, height: height)
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.8)
                        )
                }
            } else {
                // フォールバック：システムアイコン
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(fallbackColor.opacity(0.1))
                    .frame(width: width, height: height)
                    .overlay(
                        Image(systemName: fallbackIcon)
                            .font(.system(size: width * 0.5))
                            .foregroundColor(fallbackColor)
                    )
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        // URL付きのプレビュー（実際のURL）
        ArtworkImageView(
            artworkURL: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/69/2e/8b/692e8b8c-2c35-3c91-9c8e-1d9e5a5d8c1e/dj.bqmzbtqy.jpg/300x300bb.jpg"),
            width: 80
        )
        
        // フォールバック（URLなし）
        ArtworkImageView(
            artworkURL: nil,
            width: 80,
            fallbackIcon: "square.stack",
            fallbackColor: .green
        )
        
        // 異なるサイズとスタイル
        ArtworkImageView(
            artworkURL: nil,
            width: 120,
            cornerRadius: 12,
            fallbackIcon: "person.fill",
            fallbackColor: .orange
        )
    }
    .padding()
}