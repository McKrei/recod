# Import/Export History & Dictionary Backup Plan

**Goal:** Implement a feature to export and import user data (transcriptions and replacement rules) into a JSON format to prevent data loss and allow transferring between machines.

## 1. Data Transfer Objects (DTO) and `DataBackupService`
- Create `DataBackupService.swift` in `Sources/Core/Services`.
- Define `BackupPayload`, `RecordingDTO`, and `ReplacementRuleDTO` structs. 
- Use DTOs to decouple the backup JSON format from `SwiftData` `@Model` classes, allowing easier migrations in the future.
- **Export Logic:** Fetch all `Recording` objects with non-empty transcriptions and all `ReplacementRule` objects. Map to DTOs. Serialize to `Data` via `JSONEncoder` with `.iso8601` date strategy.
- **Import Logic:** Deserialize `Data` via `JSONDecoder`. Map DTOs back to `SwiftData` models.
- **Duplicate Prevention:**
  - *Recording:* Check for identical `id` or identical `createdAt` + `transcription`.
  - *Rule:* Check for identical `id` or case-insensitive match on `textToReplace` + `replacementText`.
- **Chronological Insertion:** Ensure the imported `Recording` uses the original `createdAt` date from the DTO.
- **File Deletion Flag:** Since audio is not exported, imported recordings must have `isFileDeleted = true` and a dummy `filename` to satisfy model requirements.

## 2. UI Integration in `GeneralSettingsView`
- Add a new `GroupBox` for "Data Backup".
- Add an "Export Data" button that presents an `NSSavePanel` (default filename: `Recod_Backup_YYYY-MM-DD.json`).
- Add an "Import Data" button that presents an `NSOpenPanel`.
- Display an alert summarizing the import result (e.g., "Imported 10 transcriptions. Skipped 2 duplicates.").
- Handle and display potential parsing/file system errors.

## 3. Testing
- Create `DataBackupServiceTests.swift` in `Tests/`.
- Test `exportData`: Ensure the generated JSON contains the expected DTO structure.
- Test `importData`: Ensure imported items are added to `ModelContext` with the correct `isFileDeleted` flag and original dates.
- Test `importData` (Duplicates): Ensure importing the same payload twice does not duplicate records in the `ModelContext`.