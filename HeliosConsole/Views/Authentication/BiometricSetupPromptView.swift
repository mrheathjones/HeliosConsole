//
//  BiometricSetupPromptView.swift
//  test
//
//  Created by heath on 1/19/26.
//


import SwiftUI

struct BiometricSetupPromptView: View {
    @ObservedObject var viewModel: AuthViewModel
    @Binding var isPresented: Bool
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }
            
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.2), Color.cyan.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: viewModel.biometricManager.biometricType.icon)
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(.blue)
                }
                
                VStack(spacing: 8) {
                    Text("Enable \(viewModel.biometricManager.biometricType.displayName)?")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("Use \(viewModel.biometricManager.biometricType.displayName) for quick and secure access to your account.")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                VStack(spacing: 12) {
                    Button(action: {
                        viewModel.enableBiometricAuth()
                        isPresented = false
                    }) {
                        HStack {
                            Image(systemName: viewModel.biometricManager.biometricType.icon)
                            Text("Enable \(viewModel.biometricManager.biometricType.displayName)")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            LinearGradient(
                                colors: [Color.blue, Color.cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(10)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    
                    Button(action: {
                        isPresented = false
                    }) {
                        Text("Not Now")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(10)
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(32)
            .frame(width: 360)
            .background(
                Color.white.opacity(0.05)
                    .background(.ultraThinMaterial.opacity(0.8))
            )
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.5), radius: 40, x: 0, y: 20)
        }
    }
}
