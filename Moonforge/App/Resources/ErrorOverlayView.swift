//
//  ErrorOverlayView.swift
//  Moonforge
//
//  Created by Yauheni Kozich on 17.03.26.
//

import SwiftUI

// MARK: - Error Overlay View

/// Переиспользуемый view для отображения ошибок
struct ErrorOverlayView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("❌").font(.system(size: 50))
            Text("Ошибка").font(.title).foregroundColor(.red)
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: onRetry) {
                Text("Повторить")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .cornerRadius(8)
            }
            .frame(minHeight: 44) // HIG compliance
        }
        .padding(24)
        .background(Color(UIColor.systemBackground).opacity(0.85))
        .cornerRadius(16)
        .shadow(radius: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ошибка: \(message)")
        .accessibilityHint("Двойное нажатие для повторной попытки")
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }
}

// MARK: - Previews

#Preview("Error Overlay") {
    ErrorOverlayView(message: "Что-то пошло не так") {
    }
    .frame(maxWidth: 300, maxHeight: 300)
}
