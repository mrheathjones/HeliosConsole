//
//  StatusBadge.swift
//  Helios
//
//  Solid capsule badge for device status (Supervised, Managed, …). The
//  regular size sits in detail-view headers; compact fits list rows and
//  search result cards.
//

import SwiftUI

struct StatusBadge: View {
    enum Size {
        case regular
        case compact
    }

    let text: String
    let color: Color
    let size: Size

    init(_ text: String, color: Color, size: Size = .regular) {
        self.text = text
        self.color = color
        self.size = size
    }

    var body: some View {
        Text(text)
            .font(.system(size: size == .compact ? 9 : 11, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, size == .compact ? 6 : 10)
            .padding(.vertical, size == .compact ? 2 : 4)
            .background(Capsule().fill(color))
    }
}
