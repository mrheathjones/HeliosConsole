//
//  BiometricPromptView.swift
//  test
//
//  Created by heath on 1/19/26.
//


import SwiftUI

struct BiometricPromptView: View {
    @ObservedObject var viewModel: AuthViewModel
    @State private var showError = false
    @State private var pulseAnimation = false
    
    var body: some View {
        ZStack {
            AnimatedBackgroundView(animate: .constant(true))
            
            VStack(spacing: 40) {
                Spacer()
                
                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.3), Color.cyan.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 140, height: 140)
                            .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                            .opacity(pulseAnimation ? 0.5 : 0.8)
                        
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue, Color.cyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 120)
                        
                        Image(systemName: viewModel.biometricManager.biometricType.icon)
                            .font(.system(size: 50, weight: .light))
                            .foregroundColor(.white)
                    }
                    .onAppear {
                        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                            pulseAnimation = true
                        }
                    }
                    
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Text("Helios")
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundColor(.white)
                            
                            Text("Console")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 4)
                                .background(
                                    LinearGradient(
                                        colors: [Color.blue, Color.cyan],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(10)
                        }
                        
                        Text("Unlock with \(viewModel.biometricManager.biometricType.displayName)")
                            .font(.system(size: 18))
                            .foregroundColor(.gray)
                    }
                }
                
                if let errorMessage = viewModel.errorMessage {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        
                        Text(errorMessage)
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                    }
                    .padding(16)
                    .background(Color.orange.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
                    .cornerRadius(12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.horizontal, 40)
                }
                
                Spacer()
                
                VStack(spacing: 16) {
                    Button(action: {
                        viewModel.authenticateWithBiometrics()
                    }) {
                        HStack {
                            Image(systemName: viewModel.biometricManager.biometricType.icon)
                            Text("Unlock")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: 400)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                colors: [Color.blue, Color.cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                        .shadow(color: Color.blue.opacity(0.5), radius: 20, x: 0, y: 10)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    
                    Button(action: {
                        withAnimation {
                            viewModel.showBiometricPrompt = false
                            viewModel.currentUser = nil
                            viewModel.clearSession()
                        }
                    }) {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.blue)
                            .frame(maxWidth: 400)
                            .frame(height: 56)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                viewModel.authenticateWithBiometrics()
            }
        }
    }
}
