import SwiftUI

struct ParakeetModelRow: View {
    let model: ParakeetModel
    let isSelected: Bool
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ModelRowView(
            title: model.name,
            subtitle: nil, // model.type.languages
            sizeDescription: model.sizeDescription,
            isDownloaded: model.isDownloaded,
            isDownloading: model.isDownloading,
            downloadProgress: model.downloadProgress,
            isSelected: isSelected,
            onSelect: onSelect,
            onDownload: onDownload,
            onCancel: onCancel,
            onDelete: onDelete
        )
    }
}
