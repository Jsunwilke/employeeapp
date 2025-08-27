import SwiftUI
import WebKit

// MARK: - Animated GIF View using WKWebView
struct AnimatedGifView: UIViewRepresentable {
    let url: String
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.scrollView.isScrollEnabled = false
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.navigationDelegate = context.coordinator
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        guard let gifURL = URL(string: url) else { return }
        
        // Create HTML to display the GIF
        let html = """
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                body {
                    margin: 0;
                    padding: 0;
                    display: flex;
                    justify-content: center;
                    align-items: flex-start;
                    background: transparent;
                }
                img {
                    max-width: 100%;
                    height: auto;
                    display: block;
                    border-radius: 16px;
                }
            </style>
        </head>
        <body>
            <img src="\(gifURL.absoluteString)" />
        </body>
        </html>
        """
        
        webView.loadHTMLString(html, baseURL: nil)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        // Handle navigation if needed
    }
}

// MARK: - Enhanced GIF Message View
struct EnhancedGifMessageView: View {
    let url: String
    let isOwnMessage: Bool
    @State private var isLoading = true
    @State private var showError = false
    
    var body: some View {
        VStack {
            if showError {
                // Error state
                VStack {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                    Text("Failed to load GIF")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .frame(width: 200, height: 150)
                .background(Color(.systemGray6))
                .cornerRadius(16)
            } else {
                // Animated GIF display
                AnimatedGifView(url: url)
                    .frame(maxWidth: 250)
                    .frame(height: 250) // Square aspect ratio for most GIFs
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isOwnMessage ? Color.blue : Color(.systemGray5), lineWidth: 1)
                    )
                    .onAppear {
                        // Validate URL
                        if URL(string: url) == nil {
                            showError = true
                        }
                    }
                
                // Optional: Add a loading indicator
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                isLoading = false
                            }
                        }
                }
            }
        }
    }
}

// MARK: - Simple Image View for static images
struct ChatImageView: View {
    let url: String
    let isOwnMessage: Bool
    @State private var showFullScreen = false
    
    var body: some View {
        AsyncImage(url: URL(string: url)) { phase in
            switch phase {
            case .empty:
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 200, height: 150)
                    .overlay(
                        ProgressView()
                    )
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 250)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isOwnMessage ? Color.blue : Color(.systemGray5), lineWidth: 1)
                    )
                    .onTapGesture {
                        showFullScreen = true
                    }
            case .failure(_):
                VStack {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                    Text("Failed to load image")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .frame(width: 200, height: 150)
                .background(Color(.systemGray6))
                .cornerRadius(16)
            @unknown default:
                EmptyView()
            }
        }
        .fullScreenCover(isPresented: $showFullScreen) {
            FullScreenImageViewer(imageURL: url, isPresented: $showFullScreen)
        }
    }
}