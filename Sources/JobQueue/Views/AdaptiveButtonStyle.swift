#if os(macOS)
//
//  AdaptiveButtonStyle.swift
//  Spokio
//
//  Created by Codex on 4/6/26.
//

import SwiftUI

enum AdaptiveButtonProminence {
    case subtle
    case primary
    case bordered
}

struct AdaptiveButtonStyle: ButtonStyle {
    var isActive = false
    var prominence: AdaptiveButtonProminence = .subtle
    var height: CGFloat = 24

    func makeBody(configuration: Configuration) -> some View {
        AdaptiveButtonStyleBody(
            configuration: configuration,
            isActive: isActive,
            prominence: prominence,
            height: height
        )
    }

    private struct AdaptiveButtonStyleBody: View {
        let configuration: ButtonStyle.Configuration
        let isActive: Bool
        let prominence: AdaptiveButtonProminence
        let height: CGFloat

        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .imageScale(.small)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(foregroundColor)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(height: height)
                .background(backgroundColor)
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(borderColor, lineWidth: borderWidth)
                }
                .contentShape(shape)
                .onHover { isHovered = $0 }
        }

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
        }

        private var backgroundColor: Color {
            switch prominence {
                case .subtle:
                    return subtleBackgroundColor
                case .primary:
                    return primaryBackgroundColor
                case .bordered:
                    return borderedBackgroundColor
            }
        }

        private var foregroundColor: Color {
            if !isEnabled {
                return .secondary
            }

            switch prominence {
                case .subtle:
                    return .primary
                case .primary:
                    return .white
                case .bordered:
                    return .primary
            }
        }

        private var borderColor: Color {
            guard prominence == .bordered else {
                return .clear
            }

            if !isEnabled {
                return Color.primary.opacity(0.08)
            }

            if configuration.isPressed {
                return Color.accentColor.opacity(0.42)
            }

            if isActive {
                return Color.accentColor.opacity(0.34)
            }

            if isHovered {
                return Color.accentColor.opacity(0.26)
            }

            return Color.primary.opacity(0.14)
        }

        private var borderWidth: CGFloat {
            prominence == .bordered ? 1 : 0
        }

        private var subtleBackgroundColor: Color {
            if !isEnabled {
                return Color.primary.opacity(0.04)
            }

            if configuration.isPressed {
                return Color.accentColor.opacity(0.22)
            }

            if isActive {
                return Color.accentColor.opacity(0.16)
            }

            if isHovered {
                return Color.accentColor.opacity(0.1)
            }

            return Color.primary.opacity(0.06)
        }

        private var primaryBackgroundColor: Color {
            if !isEnabled {
                return Color.primary.opacity(0.08)
            }

            if configuration.isPressed {
                return Color.accentColor.opacity(0.78)
            }

            if isHovered {
                return Color.accentColor.opacity(0.9)
            }

            return Color.accentColor
        }

        private var borderedBackgroundColor: Color {
            if !isEnabled {
                return .clear
            }

            if configuration.isPressed {
                return Color.accentColor.opacity(0.18)
            }

            if isActive {
                return Color.accentColor.opacity(0.12)
            }

            if isHovered {
                return Color.accentColor.opacity(0.08)
            }

            return .clear
        }
    }
}
#endif
