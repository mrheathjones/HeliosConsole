//
//  FilterToggle.swift
//  Helios
//
//  Tinted on/off chip used for list tag filters.
//

import SwiftUI

struct FilterToggle: View {
    let label: String
    @Binding var isOn: Bool
    let color: Color

    init(_ label: String, isOn: Binding<Bool>, color: Color) {
        self.label = label
        self._isOn = isOn
        self.color = color
    }

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundColor(isOn ? color : .gray)

                Text(label)
                    .font(.system(size: 12, weight: isOn ? .medium : .regular))
                    .foregroundColor(isOn ? .white : .gray)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isOn ? color.opacity(0.2) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isOn ? color.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
