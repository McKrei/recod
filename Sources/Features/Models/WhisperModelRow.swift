import SwiftUI

struct WhisperModelRow: View {
    let model: WhisperModel
    let isSelected: Bool
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: {
            if model.isDownloaded {
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
                    } else {
                        Circle()
                            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                            .frame(width: 16, height: 16)
                    }
                    
                    Text(model.name)
                        .font(.body)
                        .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.9))
                }
                
                Spacer()
                
                // Size
                Text(model.sizeDescription)
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
    
    private var actionSection: some View {
        HStack {
            if model.isDownloading {
                downloadingView
            } else if model.isDownloaded {
                DeleteIconButton(action: onDelete)
            } else {
                DownloadIconButton(action: onDownload)
            }
        }
    }
    
    private var downloadingView: some View {
        HStack(spacing: 6) {
            ProgressView(value: model.downloadProgress)
                .progressViewStyle(.circular)
                .controlSize(.mini)
            
            CancelIconButton(action: onCancel)
        }
    }
}

#Preview {
    VStack {
        WhisperModelRow(
            model: WhisperModel(type: .base, isDownloaded: true),
            isSelected: true,
            onSelect: {}, onDownload: {}, onCancel: {}, onDelete: {}
        )
        WhisperModelRow(
            model: WhisperModel(type: .small),
            isSelected: false,
            onSelect: {}, onDownload: {}, onCancel: {}, onDelete: {}
        )
        WhisperModelRow(
            model: WhisperModel(type: .medium, isDownloading: true, downloadProgress: 0.45),
            isSelected: false,
            onSelect: {}, onDownload: {}, onCancel: {}, onDelete: {}
        )
    }
    .padding()
    .frame(width: 400)
}
