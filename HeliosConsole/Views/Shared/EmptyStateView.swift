//
//  EmptyStateView.swift
//  Helios
//
//  Centered icon + message shown when a section or list has nothing to show.
//

import SwiftUI

struct EmptyStateView: View {
    let message: String
    let icon: String

    init(_ message: String, icon: String) {
        self.message = message
        self.icon = icon
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.gray.opacity(0.4))

            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}
