// Sources/Features/Models/Components/ModelRowView.swift

import SwiftUI

struct ModelRowView: View {
    let title: String
    let subtitle: String?
    let sizeDescription: String
    
    let isDownloaded: Bool
    let isDownloading: Bool
    let downloadProgress: Double
    let isSelected: Bool
    
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: {
            if isDownloaded {
                onSelect()
            }
        }) {
            HStack(spacing: 12) {
                // Name (Fixed width or flexible)
                HStack(spacing: 8) {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(Color.accentColor)
                            .clipShape(Circle())
                    } else if isDownloaded {
                        Image(systemName: "circle")
                            .foregroundStyle(.secondary.opacity(0.3))
                            .frame(width: 16, height: 16)
                    } else {
                        Circle()
                            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                            .frame(width: 16, height: 16)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.body)
                            .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.9))

                        if let subtitle = subtitle {
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                // Size
                Text(sizeDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)

                // Action
                actionSection
                    .frame(width: 60, alignment: .center)
            }
            .glassRowStyle(isSelected: isSelected, isHovering: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var actionSection: some View {
        HStack {
            if isDownloading {
                HStack(spacing: 6) {
                    ProgressView(value: downloadProgress)
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                    CancelIconButton(action: onCancel)
                }
            } else if isDownloaded {
                DeleteIconButton(action: onDelete)
            } else {
                DownloadIconButton(action: onDownload)
            }
        }
    }
}
