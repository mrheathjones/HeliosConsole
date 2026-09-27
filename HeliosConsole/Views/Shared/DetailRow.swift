//
//  DetailRow.swift
//  Helios
//
//  Label/value row for a DetailCard. A nil value renders as "N/A".
//

import SwiftUI

struct DetailRow: View {
    let label: String
    let value: String?
    var monospaced: Bool = false

    init(_ label: String, _ value: String?, monospaced: Bool = false) {
        self.label = label
        self.value = value
        self.monospaced = monospaced
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.gray)
                .frame(width: 180, alignment: .leading)

            Text(value ?? "N/A")
                .font(.system(size: 13, weight: .medium, design: monospaced ? .monospaced : .default))
                .foregroundColor(.white)
                .textSelection(.enabled)

            Spacer()
        }
    }
}
