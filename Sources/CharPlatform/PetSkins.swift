import AppKit
import ImageIO

public enum PetSkinClip: String, Codable, CaseIterable {
    case idle, press, returnHome = "return", depart, arrive, edgePeek, edgeHide
}

public struct PetSkinSize: Codable, Equatable {
    public let width: Int
    public let height: Int
    public init(width: Int, height: Int) { self.width = width; self.height = height }
}

public struct PetSkinAnchor: Codable, Equatable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct PetSkinAnimation: Codable, Equatable {
    public let frames: [String]
    public let fps: Double
    public init(frames: [String], fps: Double) { self.frames = frames; self.fps = fps }
}

public struct PetSkinManifest: Codable, Identifiable, Equatable {
    public let schemaVersion: Int
    public let id: String
    public let name: String
    public let canvasSize: PetSkinSize
    /// Normalized coordinates, measured from the top left of the full canvas.
    public let anchor: PetSkinAnchor
    public let clips: [String: PetSkinAnimation]
    public init(schemaVersion: Int = 1, id: String, name: String, canvasSize: PetSkinSize,
                anchor: PetSkinAnchor, clips: [String: PetSkinAnimation]) {
        self.schemaVersion = schemaVersion; self.id = id; self.name = name
        self.canvasSize = canvasSize; self.anchor = anchor; self.clips = clips
    }
}

public enum PetSkinError: Error, LocalizedError {
    case invalid(String), duplicateID, cannotDeleteDefault, unknownSkin
    public var errorDescription: String? {
        switch self {
        case .invalid(let reason): return "Invalid pet skin: \(reason)"
        case .duplicateID: return "A pet skin with this ID is already installed."
        case .cannotDeleteDefault: return "The built-in pet cannot be deleted."
        case .unknownSkin: return "This pet skin is not installed."
        }
    }
}

/// Main-thread owned local store. Imported packages are data only; no executable content is loaded.
public final class PetSkinStore {
    public static let defaultID = "char.default"
    public static let defaultSkin = PetSkinManifest(id: defaultID, name: "Char", canvasSize: .init(width: 128, height: 128), anchor: .init(x: 0.5, y: 0.5), clips: [:])
    private let directory: URL
    private var packages: [String: URL] = [:]
    public private(set) var skins: [PetSkinManifest] = [defaultSkin]
    public private(set) var selectedSkin: PetSkinManifest = defaultSkin
    private var images: [String: NSImage] = [:]
    private struct Selection: Codable { let selectedID: String }

    public init(directory: URL) throws {
        self.directory = directory.standardizedFileURL
        let fm = FileManager.default
        try fm.createDirectory(at: self.directory, withIntermediateDirectories: true)
        for url in try fm.contentsOfDirectory(at: self.directory, includingPropertiesForKeys: nil)
            where url.pathExtension == "charpet" {
            // A damaged installed package must not prevent the built-in pet from loading.
            guard let manifest = try? Self.validatePackage(at: url),
                  manifest.id != Self.defaultID, packages[manifest.id] == nil else { continue }
            packages[manifest.id] = url; skins.append(manifest)
        }
        skins = [Self.defaultSkin] + skins.dropFirst().sorted { $0.id < $1.id }
        if let data = try? Data(contentsOf: self.directory.appendingPathComponent("selection.json")),
           let saved = try? JSONDecoder().decode(Selection.self, from: data),
           let selected = skins.first(where: { $0.id == saved.selectedID }) { selectedSkin = selected }
    }

    @discardableResult public func importPackage(at source: URL) throws -> PetSkinManifest {
        let manifest = try Self.validatePackage(at: source)
        guard !skins.contains(where: { $0.id == manifest.id }) else { throw PetSkinError.duplicateID }
        let fm = FileManager.default
        let staging = directory.appendingPathComponent(".import-\(UUID().uuidString).charpet")
        defer { try? fm.removeItem(at: staging) }
        try fm.copyItem(at: source, to: staging)
        // Validate the copied bytes before publishing: source changes during copy cannot bypass validation.
        let copied = try Self.validatePackage(at: staging)
        guard copied == manifest else { throw PetSkinError.invalid("package changed during import") }
        let target = directory.appendingPathComponent(manifest.id + ".charpet")
        guard !fm.fileExists(atPath: target.path) else { throw PetSkinError.duplicateID }
        try fm.moveItem(at: staging, to: target)
        packages[manifest.id] = target; skins.append(manifest)
        skins = [Self.defaultSkin] + skins.dropFirst().sorted { $0.id < $1.id }
        return manifest
    }

    public func select(id: String) throws {
        guard let skin = skins.first(where: { $0.id == id }) else { throw PetSkinError.unknownSkin }
        let data = try JSONEncoder().encode(Selection(selectedID: id))
        try data.write(to: directory.appendingPathComponent("selection.json"), options: .atomic)
        selectedSkin = skin
    }

    public func delete(id: String) throws {
        guard id != Self.defaultID else { throw PetSkinError.cannotDeleteDefault }
        guard let url = packages[id] else { throw PetSkinError.unknownSkin }
        // Persist fallback first; a failed deletion leaves a usable selected skin.
        if selectedSkin.id == id { try select(id: Self.defaultID) }
        try FileManager.default.removeItem(at: url)
        packages.removeValue(forKey: id); skins.removeAll { $0.id == id }
        images = images.filter { !$0.key.hasPrefix(id + "/") }
    }

    /// `idle` loops; interaction clips clamp to their last frame. Negative/nonfinite time starts at frame zero.
    /// The built-in skin returns nil because its vector renderer lives in the companion view.
    public func image(for id: String, clip: PetSkinClip, elapsed: TimeInterval) -> NSImage? {
        guard let skin = skins.first(where: { $0.id == id }), let root = packages[id],
              let animation = skin.clips[clip.rawValue], !animation.frames.isEmpty else { return nil }
        let safeTime = elapsed.isFinite ? max(0, elapsed) : 0
        let duration = Double(animation.frames.count) / animation.fps
        let index = clip == .idle
            ? Int((safeTime.truncatingRemainder(dividingBy: duration)) * animation.fps) % animation.frames.count
            : Int(min(Double(animation.frames.count - 1), floor(safeTime * animation.fps)))
        let frame = animation.frames[index], key = id + "/" + frame
        if let cached = images[key] { return cached }
        guard let image = NSImage(contentsOf: root.appendingPathComponent(frame)) else { return nil }
        images[key] = image
        return image
    }

    public static func validatePackage(at root: URL) throws -> PetSkinManifest {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .fileSizeKey]
        let rootValues = try root.resourceValues(forKeys: keys)
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else { throw PetSkinError.invalid("package must be a real directory") }
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: Array(keys)) else { throw PetSkinError.invalid("unreadable package") }
        var totalBytes = 0, entries = 0
        var packagePNGs = Set<String>()
        for case let url as URL in enumerator {
            entries += 1
            let values = try url.resourceValues(forKeys: keys)
            guard entries <= 600, values.isSymbolicLink != true,
                  values.isDirectory == true || values.isRegularFile == true else { throw PetSkinError.invalid("links, special files or too many entries") }
            if values.isRegularFile == true {
                let relative = String(url.standardizedFileURL.resolvingSymlinksInPath().path.dropFirst(root.path.count + 1))
                guard relative == "manifest.json" || relative.hasSuffix(".png") else { throw PetSkinError.invalid("only manifest.json and PNG assets are allowed: \(relative)") }
                if relative.hasSuffix(".png") { packagePNGs.insert(relative) }
            }
            totalBytes += values.fileSize ?? 0
            guard totalBytes <= 32 * 1024 * 1024 else { throw PetSkinError.invalid("package exceeds 32 MiB") }
        }
        let manifestURL = root.appendingPathComponent("manifest.json")
        let manifestData = try Data(contentsOf: manifestURL)
        guard manifestData.count <= 64 * 1024 else { throw PetSkinError.invalid("manifest exceeds 64 KiB") }
        let manifest = try JSONDecoder().decode(PetSkinManifest.self, from: manifestData)
        guard manifest.schemaVersion == 1 else { throw PetSkinError.invalid("unsupported schema version") }
        guard manifest.id.range(of: "^[a-z][a-z0-9.-]{1,63}$", options: .regularExpression) != nil,
              !manifest.id.contains(".."), !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              manifest.name.count <= 80 else { throw PetSkinError.invalid("invalid identity") }
        let size = manifest.canvasSize
        guard (32...512).contains(size.width), (32...512).contains(size.height),
              manifest.anchor.x.isFinite, manifest.anchor.y.isFinite,
              (0...1).contains(manifest.anchor.x), (0...1).contains(manifest.anchor.y) else { throw PetSkinError.invalid("invalid canvas or anchor") }
        guard Set(manifest.clips.keys) == Set(PetSkinClip.allCases.map(\.rawValue)) else { throw PetSkinError.invalid("exactly seven required clips must be present") }
        var uniqueFrames = Set<String>(), frameCount = 0
        for (clip, animation) in manifest.clips {
            guard animation.fps.isFinite, (1...60).contains(animation.fps), (2...120).contains(animation.frames.count) else { throw PetSkinError.invalid("invalid \(clip) duration or frame rate") }
            frameCount += animation.frames.count
            guard frameCount <= 480 else { throw PetSkinError.invalid("more than 480 frame references") }
            for frame in animation.frames {
                let components = frame.split(separator: "/", omittingEmptySubsequences: false)
                guard !frame.hasPrefix("/"), !frame.contains("\\"), components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                      frame.hasSuffix(".png") else { throw PetSkinError.invalid("unsafe PNG path") }
                uniqueFrames.insert(frame)
            }
        }
        guard uniqueFrames == packagePNGs else { throw PetSkinError.invalid("missing or unreferenced PNG assets") }
        guard uniqueFrames.count * size.width * size.height <= 16_777_216 else { throw PetSkinError.invalid("more than 16 megapixels across frames") }
        for frame in uniqueFrames {
            let url = root.appendingPathComponent(frame)
            let data = try Data(contentsOf: url)
            let signature: [UInt8] = [137,80,78,71,13,10,26,10]
            guard data.count >= 33, data.count <= 4 * 1024 * 1024,
                  Array(data.prefix(8)) == signature, Array(data[12..<16]) == Array("IHDR".utf8),
                  data[24] == 8, data[25] == 6,
                  let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  (properties[kCGImagePropertyPixelWidth] as? Int) == size.width,
                  (properties[kCGImagePropertyPixelHeight] as? Int) == size.height,
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width == size.width,
                  image.height == size.height else { throw PetSkinError.invalid("frame must be a single 8-bit RGBA PNG matching canvas: \(frame)") }
        }
        return manifest
    }
}
