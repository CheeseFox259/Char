import Foundation
import CharCore
import CharPlatform

let arguments = CommandLine.arguments
guard arguments.count == 3, ["integration", "skin"].contains(arguments[1]) else {
    FileHandle.standardError.write(Data("Usage: swift run char-package-check <integration|skin> <package-directory>\n".utf8))
    exit(2)
}
let source = URL(fileURLWithPath: arguments[2], isDirectory: true)
do {
    if arguments[1] == "skin" {
        let manifest = try PetSkinStore.validatePackage(at: source)
        print("VALID skin: \(manifest.id), \(manifest.clips.count) clips")
    } else {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("char-package-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = try IntegrationPluginStore(directory: temporary)
        // Validate using production import, without conflicting with default protocols.
        // The user's actual catalog still decides duplicate/conflicting capabilities.
        for entry in store.entries { try store.setEnabled(false, for: entry.id) }
        let entry = try store.importPackage(at: source)
        print("VALID integration: \(entry.id)")
        print("Temporary catalog only; installed catalog conflicts are checked on import.")
    }
} catch {
    FileHandle.standardError.write(Data("INVALID: \(error)\n".utf8))
    exit(1)
}
