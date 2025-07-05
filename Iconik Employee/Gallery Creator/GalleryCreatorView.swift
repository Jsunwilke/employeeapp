import SwiftUI
import UIKit

/// A view for creating galleries in both Captura and Google Sheets
struct GalleryCreatorView: View {
    // Use the view model
    @StateObject private var viewModel = GalleryCreatorViewModel()
    
    // Environment
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.presentationMode) var presentationMode
    
    // State for UI interactions
    @State private var showingLoadingToast = false
    @State private var showingCopiedToast = false
    @State private var copiedItem = ""
    
    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Title
                    Text("Gallery Creator")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.top, 20)
                    
                    // Form fields
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Gallery Name")
                            .font(.headline)
                        
                        TextField("Enter gallery name", text: $viewModel.galleryName)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                            .disableAutocorrection(true)
                            .autocapitalization(.none)
                    }
                    .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Event Date")
                            .font(.headline)
                        
                        DatePicker("Select date", selection: $viewModel.eventDate, displayedComponents: .date)
                            .datePickerStyle(GraphicalDatePickerStyle())
                            .frame(maxHeight: 400)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)
                    
                    // Create button
                    Button(action: {
                        withAnimation {
                            showingLoadingToast = true
                        }
                        viewModel.createGallery()
                    }) {
                        if viewModel.isSubmitting {
                            HStack {
                                Text("Creating...")
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Text("Create Gallery")
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding()
                    .background(viewModel.galleryName.isEmpty || viewModel.isSubmitting ? Color.blue.opacity(0.5) : Color.blue)
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .disabled(viewModel.galleryName.isEmpty || viewModel.isSubmitting)
                    .onChange(of: viewModel.isSubmitting) { isSubmitting in
                        if !isSubmitting {
                            withAnimation {
                                showingLoadingToast = false
                            }
                        }
                    }
                    
                    // Status messages
                    if !viewModel.errorMessage.isEmpty {
                        errorView
                    }
                    
                    if !viewModel.successMessage.isEmpty {
                        successView
                    }
                }
                .padding(.bottom, 20)
            }
            
            // Toast notifications
            if showingLoadingToast && viewModel.isSubmitting {
                toastView(message: "Creating gallery...", icon: "hourglass")
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            if viewModel.isSubmitting {
                                // Keep toast visible if still submitting
                                showingLoadingToast = true
                            } else {
                                withAnimation {
                                    showingLoadingToast = false
                                }
                            }
                        }
                    }
            }
            
            if showingCopiedToast {
                toastView(message: "\(copiedItem) copied to clipboard", icon: "doc.on.clipboard")
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                showingCopiedToast = false
                            }
                        }
                    }
            }
        }
        .navigationTitle("Gallery Creator")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !viewModel.successMessage.isEmpty {
                    Button("Done") {
                        viewModel.resetForm()
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - SubViews
    
    private var errorView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.white)
                    .font(.title3)
                
                Text(viewModel.errorMessage)
                    .foregroundColor(.white)
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)
                
                Spacer()
            }
            
            Button(action: {
                withAnimation {
                    viewModel.errorMessage = ""
                }
            }) {
                Text("Dismiss")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(Color.white.opacity(0.3))
                    .cornerRadius(8)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding()
        .background(Color.red.opacity(0.9))
        .cornerRadius(10)
        .padding(.horizontal)
        .transition(.opacity)
    }
    
    private var successView: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
                
                Text(viewModel.successMessage)
                    .foregroundColor(.primary)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
            }
            
            divider
            
            if !viewModel.capturaGalleryID.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Captura Gallery ID:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text(viewModel.capturaGalleryID)
                            .font(.body)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        viewModel.copyGalleryID()
                        copiedItem = "Gallery ID"
                        withAnimation {
                            showingCopiedToast = true
                        }
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 18))
                            .padding(8)
                            .background(Color(.systemGray5))
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            if !viewModel.googleSheetID.isEmpty {
                divider
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Google Sheet ID:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text(viewModel.googleSheetID)
                            .font(.body)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        viewModel.copySheetID()
                        copiedItem = "Sheet ID"
                        withAnimation {
                            showingCopiedToast = true
                        }
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 18))
                            .padding(8)
                            .background(Color(.systemGray5))
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            divider
            
            // Next steps guidance
            Text("Next Steps:")
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.top, 4)
            
            Text("1. Open Captura and find your gallery")
                .font(.footnote)
            Text("2. Open the Google Sheet to prepare data")
                .font(.footnote)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
        .transition(.opacity)
    }
    
    private var divider: some View {
        Rectangle()
            .fill(Color(.systemGray4))
            .frame(height: 1)
    }
    
    private func toastView(message: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.white)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.white)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color.black.opacity(0.7))
        .cornerRadius(10)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .transition(.opacity)
    }
}

struct GalleryCreatorView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            GalleryCreatorView()
        }
    }
}
