//
//  ListenLaterView.swift
//  CratebitsDemo
//
//  Created by Claude on 2025/07/16.
//

import SwiftUI

/// Listen Later機能のメインビュー
struct ListenLaterView: View {
    @EnvironmentObject var storage: UserDefaultsStorage
    @EnvironmentObject var musicPlayer: MusicPlayerService
    @State private var selectedType: ItemType?
    @State private var searchText = ""
    @State private var showingAddItem = false
    
    /// フィルタリングされたアイテム
    var filteredItems: [ListenLaterItem] {
        var items = storage.items
        
        // タイプでフィルタリング
        if let type = selectedType {
            items = items.filter { $0.type == type }
        }
        
        // 検索テキストでフィルタリング
        if !searchText.isEmpty {
            items = items.filter { $0.displayText.localizedCaseInsensitiveContains(searchText) }
        }
        
        return items.sorted { $0.dateAdded > $1.dateAdded }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                // タイプフィルター
                typeFilterPicker
                
                // アイテムリスト
                itemList
            }
            .navigationTitle("Listen Later")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink(destination: ListenNowView()) {
                        HStack {
                            Image(systemName: "play.circle.fill")
                            Text("Listen Now")
                        }
                        .foregroundColor(.blue)
                    }
                    .disabled(filteredItems.isEmpty)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        showingAddItem = true
                    }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    Button("Add") {
                        showingAddItem = true
                    }
                }
                #endif
            }
            .searchable(text: $searchText, prompt: "Search items")
            .sheet(isPresented: $showingAddItem) {
                AddItemView()
            }
        }
    }
    
    /// タイプフィルターのPicker
    private var typeFilterPicker: some View {
        Picker("Filter by Type", selection: $selectedType) {
            Text("All").tag(ItemType?.none)
            ForEach(ItemType.allCases, id: \.self) { type in
                Text(type.displayName).tag(type as ItemType?)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }
    
    /// アイテムリスト
    private var itemList: some View {
        List {
            if filteredItems.isEmpty {
                emptyStateView
            } else {
                ForEach(filteredItems) { item in
                    ListenLaterItemRow(item: item)
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) {
                                storage.removeItem(id: item.id)
                            }
                        }
                }
            }
        }
        .listStyle(PlainListStyle())
    }
    
    /// 空状態のビュー
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bookmark.slash")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            Text("No items in Listen Later")
                .font(.title2)
                .foregroundColor(.gray)
            Text("Add music to get started")
                .font(.body)
                .foregroundColor(.secondary)
            
            VStack(spacing: 12) {
                Button("Add Item") {
                    showingAddItem = true
                }
                .buttonStyle(.borderedProminent)
                
                Text("or go to the Search tab to find music")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .listRowBackground(Color.clear)
    }
}

/// Listen Laterアイテムの行
struct ListenLaterItemRow: View {
    let item: ListenLaterItem
    @EnvironmentObject var storage: UserDefaultsStorage
    
    var body: some View {
        HStack {
            // アイコン
            Image(systemName: iconName)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 30)
            
            // 情報
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayText)
                    .font(.headline)
                    .lineLimit(2)
                
                Text(item.type.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Added: \(item.dateAdded, formatter: dateFormatter)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 評価表示（参考情報として表示のみ）
            if let evaluation = storage.evaluation(for: item.id) {
                Image(systemName: evaluation.evaluation.systemImage)
                    .foregroundColor(evaluation.evaluation.color)
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
}

/// 新しいアイテムを追加するビュー
struct AddItemView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var storage: UserDefaultsStorage
    @State private var itemType: ItemType = .track
    @State private var name = ""
    @State private var artist = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section("Item Type") {
                    Picker("Type", selection: $itemType) {
                        ForEach(ItemType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("Details") {
                    TextField(itemType == .artist ? "Artist Name" : "Name", text: $name)
                    
                    if itemType != .artist {
                        TextField("Artist", text: $artist)
                    }
                }
                
                Section {
                    Button("Add to Listen Later") {
                        addItem()
                    }
                    .disabled(name.isEmpty || (itemType != .artist && artist.isEmpty))
                }
            }
            .navigationTitle("Add Item")
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
                #else
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                #endif
            }
        }
    }
    
    private func addItem() {
        let item: ListenLaterItem
        
        switch itemType {
        case .track:
            item = ListenLaterItem.track(name: name, artist: artist)
        case .album:
            item = ListenLaterItem.album(name: name, artist: artist)
        case .artist:
            item = ListenLaterItem.artist(name: name)
        }
        
        storage.addItem(item)
        dismiss()
    }
}

/// 日付フォーマッター
private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .none
    return formatter
}()

#Preview {
    ListenLaterView()
        .environmentObject(UserDefaultsStorage())
        .environmentObject(MusicPlayerService())
}