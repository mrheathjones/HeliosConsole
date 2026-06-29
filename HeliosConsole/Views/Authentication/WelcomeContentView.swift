//
//  WelcomeContentView.swift
//  test
//
//  Created by heath on 1/19/26.
//


import SwiftUI

struct WelcomeContentView: View {
    @Binding var showLogin: Bool
    @State private var showContent = false
    @State private var floatingOffset: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color.cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                        .shadow(color: Color.blue.opacity(0.5), radius: 30, x: 0, y: 10)
                        .offset(y: floatingOffset)
                    
                    Image(systemName: "cube.transparent.fill")
                        .font(.system(size: 60, weight: .light))
                        .foregroundColor(.white)
                        .offset(y: floatingOffset)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                        floatingOffset = -10
                    }
                }
                
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Text("Helios")
                            .font(.system(size: 48, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text("Console")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 6)
                            .background(
                                LinearGradient(
                                    colors: [Color.blue, Color.cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                    }
                    
                    Text("Device Management Made Simple")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(.gray)
                }
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 20)
            }
            
            VStack(spacing: 16) {
                FeatureRow(icon: "shield.checkered", title: "Enterprise Security", description: "Advanced protection for your devices")
                FeatureRow(icon: "chart.bar.fill", title: "Real-time Analytics", description: "Monitor your fleet instantly")
                FeatureRow(icon: "gearshape.2.fill", title: "Automated Management", description: "Set it and forget it")
            }
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 30)
            
            Spacer()
            
            VStack(spacing: 16) {
                Button(action: {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        showLogin = true
                    }
                }) {
                    HStack {
                        Text("Get Started")
                            .font(.system(size: 16, weight: .semibold))
                        Image(systemName: "arrow.right")
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
                
                Button(action: {}) {
                    Text("Learn More")
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
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 40)
            .padding(.bottom, 60)
        }
        .frame(maxWidth: 600)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                showContent = true
            }
        }
    }
}
