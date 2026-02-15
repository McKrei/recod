import SwiftUI
import SwiftData

struct HistoryStatsHeader: View {
    let recordings: [Recording]
    let onDeleteAll: () -> Void

    @State private var totalSize: Int64 = 0

    var body: some View {
        GroupBox {
            HStack {
                StatItem(label: "Files", value: "\(recordings.count)")

                Divider()
                    .frame(height: 20)

                StatItem(label: "Total Size", value: ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))

                Spacer()

                Button(role: .destructive, action: onDeleteAll) {
                    Text("Delete All Files")
                }
                .controlSize(.small)
            }
        }
        .groupBoxStyle(GlassGroupBoxStyle())
        .onAppear(perform: calculateSize)
        .onChange(of: recordings, calculateSize)
    }

    private func calculateSize() {
        // Access model properties on MainActor
        let fileURLs = recordings.map { $0.fileURL }

        Task.detached(priority: .background) {
            var size: Int64 = 0
            for url in fileURLs {
                if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let fileSize = attributes[.size] as? Int64 {
                    size += fileSize
                }
            }
            await MainActor.run {
                self.totalSize = size
            }
        }
    }
}

struct StatItem: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
