import SwiftUI

struct AddActionSaveToFileSection: View {
    @Binding var saveToFileEnabled: Bool
    @Binding var saveToFileMode: SaveToFileMode
    @Binding var saveToFileDirectoryPath: String
    @Binding var saveToFileExistingFilePath: String
    @Binding var saveToFileTemplate: String
    @Binding var saveToFileSeparator: String
    @Binding var saveToFileExtension: String

    let defaultFileTemplate: String
    let defaultSeparator: String
    let fileTemplatePlaceholders: [String]
    let chooseDirectory: () -> Void
    let chooseExistingFile: () -> Void
    let abbreviatePath: (String) -> String

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: AppTheme.spacing) {
                HStack(spacing: AppTheme.spacing) {
                    Image(systemName: "doc.badge.arrow.up")
                        .foregroundStyle(.secondary)

                    Text("Save response to file")
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    StatusToggle(isOn: $saveToFileEnabled)
                }

                if saveToFileEnabled {
                    Picker("Mode", selection: $saveToFileMode) {
                        Text("New file").tag(SaveToFileMode.newFile)
                        Text("Append file").tag(SaveToFileMode.existingFile)
                    }
                    .pickerStyle(.segmented)

                    if saveToFileMode == .newFile {
                        HStack(spacing: AppTheme.spacing) {
                            Text("Directory:")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Text(saveToFileDirectoryPath.isEmpty ? "Not selected" : abbreviatePath(saveToFileDirectoryPath))
                                .font(.subheadline.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button("Choose...") {
                                chooseDirectory()
                            }
                            .buttonStyle(.bordered)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Filename template:")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            TextField(defaultFileTemplate, text: $saveToFileTemplate)
                                .textFieldStyle(.roundedBorder)
                                .font(.body.monospaced())

                            HStack(spacing: 6) {
                                ForEach(fileTemplatePlaceholders, id: \.self) { placeholder in
                                    Button(placeholder) {
                                        saveToFileTemplate += placeholder
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                    .font(.caption.monospaced())
                                }
                            }

                            Text("Preview: \(FileOutputService.shared.previewFilename(template: saveToFileTemplate, extension: saveToFileExtension))")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        HStack(spacing: AppTheme.spacing) {
                            Text("Extension:")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Picker("", selection: $saveToFileExtension) {
                                Text(".txt").tag(".txt")
                                Text(".md").tag(".md")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 160)
                        }
                    } else {
                        HStack(spacing: AppTheme.spacing) {
                            Text("File:")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Text(saveToFileExistingFilePath.isEmpty ? "Not selected" : abbreviatePath(saveToFileExistingFilePath))
                                .font(.subheadline.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button("Choose...") {
                                chooseExistingFile()
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Separator between entries:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TextField(defaultSeparator, text: $saveToFileSeparator)
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())

                        Text("Use \\n for newline, \\t for tab")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .groupBoxStyle(GlassGroupBoxStyle())
    }
}
