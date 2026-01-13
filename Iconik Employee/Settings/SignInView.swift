import SwiftUI

struct SignInView: View {
  @Binding var isSignedIn: Bool
  @EnvironmentObject var passwordResetVM: PasswordResetViewModel

  @State private var email = ""
  @State private var password = ""
  @State private var errorMessage = ""
  @State private var isLoading = false
  @State private var showingForgotPassword = false

  // AppStorage for user data (now including last name)
  @AppStorage("userOrganizationID") var storedUserOrganizationID: String = ""
  @AppStorage("userFirstName") var storedUserFirstName: String = ""
  @AppStorage("userLastName") var storedUserLastName: String = ""
  @AppStorage("userHomeAddress") var storedUserHomeAddress: String = ""
  @AppStorage("userCoordinates") var storedUserCoordinates: String = ""
  @AppStorage("userRole") var userRole: String = "employee"

  // Supabase services
  @StateObject private var authService = SupabaseAuthService()
  
  var body: some View {
    NavigationView {
      VStack(spacing: 20) {
        Text("Sign In")
          .font(.largeTitle)
          .padding(.top, 40)

        // Email/Password Sign In
        TextField("Email", text: $email)
          .textFieldStyle(RoundedBorderTextFieldStyle())
          .keyboardType(.emailAddress)
          .autocapitalization(.none)
          .disabled(isLoading)

        SecureField("Password", text: $password)
          .textFieldStyle(RoundedBorderTextFieldStyle())
          .disabled(isLoading)

        // Forgot password link
        HStack {
          Spacer()
          Button("Forgot password?") {
            showingForgotPassword = true
          }
          .font(.subheadline)
          .foregroundColor(.blue)
          .disabled(isLoading)
        }

        Button(action: signIn) {
          if isLoading {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .white))
          } else {
            Text("Sign In")
          }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(isLoading ? Color.gray : Color.blue)
        .foregroundColor(.white)
        .cornerRadius(8)
        .disabled(isLoading)

        NavigationLink(destination: CreateAccountView()) {
          Text("Don't have an account? Create one.")
            .foregroundColor(.blue)
        }
        .disabled(isLoading)

        if !errorMessage.isEmpty {
          Text(errorMessage)
            .foregroundColor(.red)
            .multilineTextAlignment(.center)
        }

        Spacer()
      }
      .padding()
    }
    .navigationViewStyle(StackNavigationViewStyle())
    .sheet(isPresented: $showingForgotPassword) {
      NavigationView {
        ForgotPasswordView(viewModel: passwordResetVM)
      }
    }
  }
  
  func signIn() {
    errorMessage = ""
    isLoading = true

    Task {
      do {
        // Sign in with Supabase
        try await authService.signIn(email: email, password: password)

        guard let userId = authService.currentUserId else {
          await MainActor.run {
            errorMessage = "Failed to get user ID"
            isLoading = false
          }
          return
        }

        // Fetch user profile from Supabase
        await fetchUserProfile(userId: userId)

      } catch {
        await MainActor.run {
          errorMessage = error.localizedDescription
          isLoading = false
        }
      }
    }
  }

  func fetchUserProfile(userId: String) async {
    do {
      // Fetch user profile from Supabase using UserProfileService
      // Note: UserProfileService will need to be migrated to use Supabase
      // For now, we'll fetch directly from Supabase

      struct UserProfile: Codable {
        let id: String
        let email: String?
        let first_name: String?
        let last_name: String?
        let home_address: String?
        let coordinates: String?
        let role: String?
        let organization_id: String?
      }

      let supabase = SupabaseManager.shared.client
      let profile: UserProfile = try await supabase
        .from("users")
        .select()
        .eq("id", value: userId)
        .single()
        .execute()
        .value

      // Save user data to AppStorage
      await MainActor.run {
        storedUserOrganizationID = profile.organization_id ?? ""
        storedUserFirstName = profile.first_name ?? ""
        storedUserLastName = profile.last_name ?? ""
        storedUserHomeAddress = profile.home_address ?? ""
        storedUserCoordinates = profile.coordinates ?? ""
        userRole = profile.role ?? "employee"

        isLoading = false
        isSignedIn = true
      }

    } catch {
      // Still sign in even if profile fetch fails
      await MainActor.run {
        isLoading = false
        isSignedIn = true
      }
    }
  }
}

struct SignInView_Previews: PreviewProvider {
  static var previews: some View {
    SignInView(isSignedIn: .constant(false))
      .environmentObject(PasswordResetViewModel())
  }
}

