import SwiftUI
import PhotosUI

struct MessageInputAccessoryView: View {
    @Binding var showEmojiPicker: Bool
    @Binding var showGifPicker: Bool
    @Binding var showPhotoPicker: Bool
    let onAttachmentTap: () -> Void
    
    @State private var isExpanded = false
    
    var body: some View {
        HStack(spacing: 6) {
            // Main + button
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.blue)
                    .rotationEffect(.degrees(isExpanded ? 45 : 0))
            }
            
            // Sliding menu container
            if isExpanded {
                HStack(spacing: 8) {
                    // Attachment button
                    Button(action: {
                        onAttachmentTap()
                        withAnimation {
                            isExpanded = false
                        }
                    }) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                    }
                    
                    // Photo picker
                    Button(action: {
                        showPhotoPicker = true
                        withAnimation {
                            isExpanded = false
                        }
                    }) {
                        Image(systemName: "photo")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                    }
                    
                    // GIF button
                    Button(action: {
                        showGifPicker = true
                        withAnimation {
                            isExpanded = false
                        }
                    }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.blue.opacity(0.1))
                                .frame(width: 30, height: 24)
                            
                            Text("GIF")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.blue)
                        }
                    }
                    
                    // Emoji button
                    Button(action: {
                        showEmojiPicker.toggle()
                        withAnimation {
                            isExpanded = false
                        }
                    }) {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 18))
                            .foregroundColor(showEmojiPicker ? .orange : .blue)
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
        }
    }
}

// MARK: - Emoji Picker View
struct EmojiPickerView: View {
    let onEmojiSelected: (String) -> Void
    @Binding var isPresented: Bool
    
    let emojis = [
        "😀", "😃", "😄", "😁", "😆", "😅", "😂", "🤣", "😊", "😇",
        "🙂", "🙃", "😉", "😌", "😍", "🥰", "😘", "😗", "😙", "😚",
        "😋", "😛", "😜", "🤪", "😝", "🤑", "🤗", "🤭", "🤫", "🤔",
        "🤐", "🤨", "😐", "😑", "😶", "😏", "😒", "🙄", "😬", "🤥",
        "😔", "😪", "😴", "😷", "🤒", "🤕", "🤢", "🤮", "🥵", "🥶",
        "😎", "🤓", "🧐", "😕", "😟", "🙁", "😮", "😯", "😲", "😳",
        "🥺", "😦", "😧", "😨", "😰", "😥", "😢", "😭", "😱", "😖",
        "😣", "😞", "😓", "😩", "😫", "🥱", "😤", "😡", "😠", "🤬",
        "👍", "👎", "👊", "✊", "🤛", "🤜", "👏", "🙌", "👐", "🤲",
        "🤝", "🙏", "✍️", "💪", "🦾", "🦿", "🦵", "🦶", "👂", "🦻",
        "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💔",
        "🎉", "🎊", "🎈", "🎁", "🎀", "🏆", "🏅", "🥇", "🥈", "🥉",
        "⚽", "🏀", "🏈", "⚾", "🥎", "🏐", "🏉", "🎾", "🥏", "🎳",
        "🍕", "🍔", "🍟", "🌭", "🍿", "🥓", "🥚", "🧇", "🥞", "🧈",
        "☕", "🍵", "🥤", "🍶", "🍺", "🍻", "🥂", "🍷", "🥃", "🍸",
        "🚗", "🚕", "🚙", "🚌", "🚎", "🏎️", "🚓", "🚑", "🚒", "✈️"
    ]
    
    let columns = [
        GridItem(.adaptive(minimum: 40))
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Emojis")
                    .font(.headline)
                Spacer()
                Button(action: {
                    isPresented = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
            .padding()
            
            Divider()
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(emojis, id: \.self) { emoji in
                        Button(action: {
                            onEmojiSelected(emoji)
                        }) {
                            Text(emoji)
                                .font(.system(size: 30))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding()
            }
            .frame(height: 250)
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 5)
    }
}

// MARK: - GIF Picker View
struct GifPickerView: View {
    @Binding var isPresented: Bool
    let onGifSelected: (String) -> Void
    @State private var searchText = ""
    @State private var gifs: [GifItem] = []
    @State private var isLoading = false
    
    // Giphy API Configuration
    private let giphyAPIKey = "pHkSkJcH9UL5jvSjTFpPh8dRXxzX5iSO"
    private let giphyBaseURL = "https://api.giphy.com/v1/gifs"
    
    struct GifItem: Identifiable {
        let id: String
        let url: String
        let previewUrl: String
        let title: String
    }
    
    var body: some View {
        NavigationView {
            VStack {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Search GIFs...", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit {
                            searchGifs()
                        }
                }
                .padding()
                
                if isLoading {
                    Spacer()
                    ProgressView("Loading GIFs...")
                    Spacer()
                } else if gifs.isEmpty && !searchText.isEmpty {
                    Spacer()
                    VStack(spacing: 20) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No GIFs found")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Text("Try a different search term")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                            ForEach(gifs, id: \.id) { gif in
                                AsyncImage(url: URL(string: gif.previewUrl)) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .onTapGesture {
                                            onGifSelected(gif.url)
                                            isPresented = false
                                        }
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.gray.opacity(0.3))
                                        .overlay(
                                            ProgressView()
                                        )
                                }
                                .frame(height: 100)
                                .cornerRadius(8)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("GIFs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
        .onAppear {
            loadTrendingGifs()
        }
    }
    
    private func searchGifs() {
        guard !searchText.isEmpty else {
            loadTrendingGifs()
            return
        }
        
        isLoading = true
        gifs = []
        
        // Build search URL
        guard var components = URLComponents(string: "\(giphyBaseURL)/search") else { return }
        components.queryItems = [
            URLQueryItem(name: "api_key", value: giphyAPIKey),
            URLQueryItem(name: "q", value: searchText),
            URLQueryItem(name: "limit", value: "25"),
            URLQueryItem(name: "rating", value: "pg-13")
        ]
        
        guard let url = components.url else { return }
        
        // Fetch GIFs from Giphy
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let gifData = json["data"] as? [[String: Any]] else {
                    return
                }
                
                self.gifs = gifData.compactMap { gif in
                    guard let id = gif["id"] as? String,
                          let images = gif["images"] as? [String: Any],
                          let original = images["original"] as? [String: Any],
                          let originalUrl = original["url"] as? String,
                          let preview = images["fixed_width"] as? [String: Any],
                          let previewUrl = preview["url"] as? String,
                          let title = gif["title"] as? String else {
                        return nil
                    }
                    
                    return GifItem(
                        id: id,
                        url: originalUrl,
                        previewUrl: previewUrl,
                        title: title
                    )
                }
            }
        }.resume()
    }
    
    private func loadTrendingGifs() {
        isLoading = true
        gifs = []
        
        // Build trending URL
        guard var components = URLComponents(string: "\(giphyBaseURL)/trending") else { return }
        components.queryItems = [
            URLQueryItem(name: "api_key", value: giphyAPIKey),
            URLQueryItem(name: "limit", value: "25"),
            URLQueryItem(name: "rating", value: "pg-13")
        ]
        
        guard let url = components.url else { return }
        
        // Fetch trending GIFs from Giphy
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let gifData = json["data"] as? [[String: Any]] else {
                    return
                }
                
                self.gifs = gifData.compactMap { gif in
                    guard let id = gif["id"] as? String,
                          let images = gif["images"] as? [String: Any],
                          let original = images["original"] as? [String: Any],
                          let originalUrl = original["url"] as? String,
                          let preview = images["fixed_width"] as? [String: Any],
                          let previewUrl = preview["url"] as? String,
                          let title = gif["title"] as? String else {
                        return nil
                    }
                    
                    return GifItem(
                        id: id,
                        url: originalUrl,
                        previewUrl: previewUrl,
                        title: title
                    )
                }
            }
        }.resume()
    }
}