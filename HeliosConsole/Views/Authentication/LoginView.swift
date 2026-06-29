//
//  LoginView.swift
//  HeliosConsole
//
//  Login view - Pure SwiftUI (uses Environment openURL instead of NSWorkspace)
//

import SwiftUI

struct LoginView: View {
    @ObservedObject var viewModel: AuthViewModel
    @Binding var showLogin: Bool
    
    @Environment(\.openURL) private var openURL
    
    @State private var email = ""
    @State private var showContent = false
    
    @FocusState private var emailFieldFocused: Bool
    
    var body: some View {
        ZStack {
            AnimatedBackgroundView(animate: .constant(true))
            
            VStack(spacing: 0) {
                backButton
                Spacer()
                loginCard
                Spacer()
            }
        }
        .onAppear {
            showContent = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                emailFieldFocused = true
            }
        }
    }
    
    // MARK: - Back Button
    
    @ViewBuilder
    private var backButton: some View {
        if !viewModel.hasSeenWelcome {
            HStack {
                Button(action: { showLogin = false }) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
            .padding(.horizontal, 40)
            .padding(.top, 40)
        }
    }
    
    // MARK: - Login Card
    
    private var loginCard: some View {
        VStack(spacing: 32) {
            headerSection
            errorSection
            emailInputSection
            continueButton
            helpSection
        }
        .frame(maxWidth: 480)
        .padding(48)
        .background(cardBackground)
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(0.3), radius: 40, x: 0, y: 20)
    }
    
    private var cardBackground: some View {
        Color.white.opacity(0.03)
            .background(.ultraThinMaterial.opacity(0.5))
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            logoHeader
            
            Text(viewModel.hasSeenWelcome ? "Welcome back" : "Sign in with your email")
                .font(.system(size: 16))
                .foregroundColor(.gray)
        }
        .opacity(showContent ? 1 : 0)
        .offset(y: showContent ? 0 : -20)
    }
    
    private var logoHeader: some View {
        HStack(spacing: 12) {
            Text("Helios")
                .font(.system(size: 36, weight: .semibold))
                .foregroundColor(.white)
            
            Text("Console")
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(brandGradient)
                .cornerRadius(10)
        }
    }
    
    private var brandGradient: some View {
        LinearGradient(
            colors: [Color.blue, Color.cyan],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    // MARK: - Error Section
    
    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage = viewModel.errorMessage {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                
                Text(errorMessage)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: {
                    withAnimation { viewModel.errorMessage = nil }
                }) {
                    Image(systemName: "xmark")
                        .foregroundColor(.gray)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color.orange.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
            .cornerRadius(12)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
    
    // MARK: - Email Input Section
    
    private var emailInputSection: some View {
        VStack(spacing: 20) {
            emailField
            infoText
        }
        .opacity(showContent ? 1 : 0)
        .offset(y: showContent ? 0 : 20)
    }
    
    private var emailField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Email Address")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
            
            HStack(spacing: 12) {
                Image(systemName: "envelope.fill")
                    .foregroundColor(.gray)
                    .frame(width: 20)
                
                TextField("", text: $email, prompt: Text("you@example.com").foregroundColor(.gray.opacity(0.5)))
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
                    .disableAutocorrection(true)
                    .focused($emailFieldFocused)
                    .onSubmit { login() }
            }
            .padding(16)
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(emailFieldFocused ? Color.blue : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
    
    private var infoText: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.blue)
            
            Text("We'll retrieve or create your secure API credentials")
                .font(.system(size: 12))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Continue Button
    
    private var continueButton: some View {
        Button(action: login) {
            HStack {
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                    Text("Authenticating...")
                        .font(.system(size: 16, weight: .semibold))
                } else {
                    Text("Continue")
                        .font(.system(size: 16, weight: .semibold))
                    Image(systemName: "arrow.right")
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(brandGradient)
            .cornerRadius(12)
            .shadow(color: Color.blue.opacity(0.5), radius: 20, x: 0, y: 10)
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(viewModel.isLoading || !isValidEmail(email))
        .opacity(showContent ? 1 : 0)
        .offset(y: showContent ? 0 : 30)
    }
    
    // MARK: - Help Section
    
    private var helpSection: some View {
        HStack(spacing: 4) {
            Text("Need help?")
                .font(.system(size: 14))
                .foregroundColor(.gray)
            
            Button(action: openSupportURL) {
                Text("Contact support")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        }
        .opacity(showContent ? 1 : 0)
    }
    
    // MARK: - Actions
    
    private func login() {
        guard isValidEmail(email) else { return }
        viewModel.loginWithEmail(email)
    }
    
    /// Opens support URL using SwiftUI's Environment openURL action
    private func openSupportURL() {
        let urlString = MDMConfigurationManager.shared.configuration.supportURL ?? "https://support.yourcompany.com"
        if let url = URL(string: urlString) {
            openURL(url)
        }
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Login View") {
    @Previewable @State var showLogin = true
    LoginView(viewModel: AuthViewModel(), showLogin: $showLogin)
        .frame(width: 1000, height: 800)
        .preferredColorScheme(.dark)
}
#endif
