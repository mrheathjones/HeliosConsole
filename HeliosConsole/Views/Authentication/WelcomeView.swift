//
//  WelcomeView.swift
//  test
//
//  Created by heath on 1/19/26.
//


import SwiftUI

struct WelcomeView: View {
    @ObservedObject var viewModel: AuthViewModel
    @State private var showLogin = false
    @State private var animateGradient = false
    
    var body: some View {
        ZStack {
            AnimatedBackgroundView(animate: $animateGradient)
            
            if showLogin {
                LoginView(viewModel: viewModel, showLogin: $showLogin)
                    .onAppear {
                        viewModel.markWelcomeAsSeen()
                    }
            } else {
                WelcomeContentView(showLogin: $showLogin)
            }
        }
        .onAppear {
            animateGradient = true
        }
    }
}
