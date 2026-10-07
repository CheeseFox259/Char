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
    /// Optional independent square software icon. Old v1 packages derive it from edgePeek.
    public let appIcon: String?
    public let features: PetSkinFeatures?
    public init(schemaVersion: Int = 1, id: String, name: String, canvasSize: PetSkinSize,
                anchor: PetSkinAnchor, clips: [String: PetSkinAnimation], appIcon: String? = nil, features: PetSkinFeatures? = nil) {
        self.schemaVersion = schemaVersion; self.id = id; self.name = name
        self.canvasSize = canvasSize; self.anchor = anchor; self.clips = clips; self.appIcon = appIcon; self.features = features
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

/// Main-thread owned store. Assets are immutable; scripts are read only by the isolated helper.
public final class PetSkinStore {
    public static let defaultID = "char.default"
    public static let defaultSkin = PetSkinManifest(id: defaultID, name: "Char", canvasSize: .init(width: 128, height: 128), anchor: .init(x: 0.5, y: 0.5), clips: [:])
    private let directory: URL
    private var packages: [String: URL] = [:]
    public private(set) var skins: [PetSkinManifest] = [defaultSkin]
    public private(set) var selectedSkin: PetSkinManifest = defaultSkin
    private struct CachedImage { let image: NSImage; let bytes: Int; var accessed: UInt64 }
    private var images: [String: CachedImage] = [:]
    private var cacheAccess: UInt64 = 0
    private let imageCacheBudget: Int
    public private(set) var cachedImageBytes = 0
    private func cachedImage(_ key: String) -> NSImage? {
        guard var entry = images[key] else { return nil }
        cacheAccess &+= 1; entry.accessed = cacheAccess; images[key] = entry; return entry.image
    }
    private func cache(_ image: NSImage, key: String) {
        let pixels = image.representations.map { max(1,$0.pixelsWide)*max(1,$0.pixelsHigh) }.max() ?? Int(image.size.width*image.size.height)
        let bytes = max(1,pixels)*4
        guard bytes <= imageCacheBudget else { return }
        if let old = images.removeValue(forKey: key) { cachedImageBytes -= old.bytes }
        while cachedImageBytes+bytes > imageCacheBudget,
              let oldest = images.min(by: { $0.value.accessed < $1.value.accessed })?.key {
            if let removed = images.removeValue(forKey: oldest) { cachedImageBytes -= removed.bytes }
        }
        cacheAccess &+= 1; images[key] = CachedImage(image: image,bytes: bytes,accessed: cacheAccess); cachedImageBytes += bytes
    }
    private func pruneImages(keeping prefix: String?) {
        images = prefix.map { value in images.filter { $0.key.hasPrefix(value) } } ?? [:]
        cachedImageBytes = images.values.reduce(0) { $0+$1.bytes }
    }
    public private(set) var behaviorEnabled = true
    public private(set) var selectedTheme: String?
    private struct Selection: Codable { let selectedID: String; var theme: String?; var behaviorEnabled: Bool? }

    public init(directory: URL, imageCacheBudget: Int = 32 * 1024 * 1024) throws {
        self.imageCacheBudget = max(0,imageCacheBudget)
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
           let selected = skins.first(where: { $0.id == saved.selectedID }) { selectedSkin = selected; behaviorEnabled = saved.behaviorEnabled ?? true; selectedTheme = saved.theme == "" ? nil : selected.features?.themes?[saved.theme ?? ""] != nil ? saved.theme : selected.features?.defaultTheme }
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
        let data = try JSONEncoder().encode(Selection(selectedID: id, theme: skin.features?.defaultTheme, behaviorEnabled: true))
        try data.write(to: directory.appendingPathComponent("selection.json"), options: .atomic)
        pruneImages(keeping: id+"/")
        selectedSkin = skin; behaviorEnabled = true; selectedTheme = skin.features?.defaultTheme
    }

    public func selectTheme(_ theme: String) throws {
        guard theme.isEmpty || selectedSkin.features?.themes?[theme] != nil else { throw PetSkinError.invalid("unknown theme") }
        try JSONEncoder().encode(Selection(selectedID: selectedSkin.id, theme: theme, behaviorEnabled: behaviorEnabled)).write(to: directory.appendingPathComponent("selection.json"), options: .atomic)
        if selectedTheme != (theme.isEmpty ? nil : theme) { pruneImages(keeping: nil) }
        selectedTheme = theme.isEmpty ? nil : theme
    }
    public func setBehaviorEnabled(_ enabled: Bool) throws {
        try JSONEncoder().encode(Selection(selectedID: selectedSkin.id,theme: selectedTheme ?? "",behaviorEnabled: enabled)).write(to: directory.appendingPathComponent("selection.json"),options: .atomic)
        behaviorEnabled = enabled
    }
    public func resourceURL(_ path: String) -> URL? { packages[selectedSkin.id]?.appendingPathComponent(path) }
    public func asset(_ path: String) -> NSImage? {
        let key = selectedSkin.id + "/" + path
        if let cached = cachedImage(key) { return cached }
        guard let url = resourceURL(path), let image = NSImage(contentsOf: url) else { return nil }
        cache(image,key: key); return image
    }
    public func image(clip: String, elapsed: TimeInterval, placement: String) -> NSImage? {
        let pose = selectedSkin.pose(placement: placement, theme: selectedTheme)
        guard let animation = pose.clips[clip], !animation.frames.isEmpty else { return nil }
        let time = elapsed.isFinite ? max(0,elapsed) : 0, duration = Double(animation.frames.count)/animation.fps
        let loop = clip == "idle" || selectedSkin.features?.loopingClips?.contains(clip) == true
        let index = loop ? Int(time.truncatingRemainder(dividingBy: duration)*animation.fps) % animation.frames.count : Int(min(Double(animation.frames.count-1),floor(time*animation.fps)))
        return asset(animation.frames[index])
    }

    public func delete(id: String) throws {
        guard id != Self.defaultID else { throw PetSkinError.cannotDeleteDefault }
        guard let url = packages[id] else { throw PetSkinError.unknownSkin }
        // Persist fallback first; a failed deletion leaves a usable selected skin.
        if selectedSkin.id == id { try select(id: Self.defaultID) }
        try FileManager.default.removeItem(at: url)
        packages.removeValue(forKey: id); skins.removeAll { $0.id == id }
        images = images.filter { !$0.key.hasPrefix(id + "/") }
        cachedImageBytes = images.values.reduce(0) { $0+$1.bytes }
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
        if let cached = cachedImage(key) { return cached }
        guard let image = NSImage(contentsOf: root.appendingPathComponent(frame)) else { return nil }
        cache(image,key: key)
        return image
    }

    public func icon(for id: String) -> NSImage? {
        guard let skin = skins.first(where: { $0.id == id }), let root = packages[id] else { return nil }
        let theme = id == selectedSkin.id ? selectedTheme : skin.features?.defaultTheme
        let key = id + "/@application-icon/" + (theme ?? "")
        if let cached = cachedImage(key) { return cached }
        let icon: NSImage?
        if let path = skin.pose(placement: "right", theme: theme).appIcon { icon = NSImage(contentsOf: root.appendingPathComponent(path)) }
        else if let frame = image(for: id, clip: .edgePeek, elapsed: .greatestFiniteMagnitude) {
            icon = PetIconArtwork.rightEdgeIcon(pet: frame, anchor: NSPoint(x: skin.anchor.x, y: 1 - skin.anchor.y))
        } else { icon = nil }
        if let icon { cache(icon,key: key) }
        return icon
    }

    public static func validatePackage(at root: URL) throws -> PetSkinManifest {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .fileSizeKey]
        let rootValues = try root.resourceValues(forKeys: keys)
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else { throw PetSkinError.invalid("package must be a real directory") }
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: Array(keys)) else { throw PetSkinError.invalid("unreadable package") }
        var totalBytes = 0, entries = 0
        var packagePNGs = Set<String>(), otherAssets = Set<String>()
        for case let url as URL in enumerator {
            entries += 1
            let values = try url.resourceValues(forKeys: keys)
            guard entries <= 2200, values.isSymbolicLink != true,
                  values.isDirectory == true || values.isRegularFile == true else { throw PetSkinError.invalid("links, special files or too many entries") }
            if values.isRegularFile == true {
                let relative = String(url.standardizedFileURL.resolvingSymlinksInPath().path.dropFirst(root.path.count + 1))
                if url.lastPathComponent == ".DS_Store", (values.fileSize ?? 0) <= 128*1024 { totalBytes += values.fileSize ?? 0; continue }
                guard relative == "manifest.json" || ["png","js","wav","aiff","m4a"].contains(url.pathExtension) else { throw PetSkinError.invalid("unsupported appearance asset: \(relative)") }
                if relative.hasSuffix(".png") { packagePNGs.insert(relative) }
                else if relative != "manifest.json" { otherAssets.insert(relative) }
            }
            totalBytes += values.fileSize ?? 0
            guard totalBytes <= 64 * 1024 * 1024 else { throw PetSkinError.invalid("package exceeds 64 MiB") }
        }
        let manifestURL = root.appendingPathComponent("manifest.json")
        let manifestData = try Data(contentsOf: manifestURL)
        guard manifestData.count <= 128 * 1024 else { throw PetSkinError.invalid("manifest exceeds 128 KiB") }
        try PetSkinJSONContract.validate(manifestData)
        let manifest = try JSONDecoder().decode(PetSkinManifest.self, from: manifestData)
        guard [1,2].contains(manifest.schemaVersion) else { throw PetSkinError.invalid("unsupported schema version") }
        guard manifest.id.range(of: "^[a-z][a-z0-9.-]{1,63}$", options: .regularExpression) != nil,
              !manifest.id.contains(".."), !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              manifest.name.count <= 80 else { throw PetSkinError.invalid("invalid identity") }
        let size = manifest.canvasSize
        guard (32...512).contains(size.width), (32...512).contains(size.height),
              manifest.anchor.x.isFinite, manifest.anchor.y.isFinite,
              (0...1).contains(manifest.anchor.x), (0...1).contains(manifest.anchor.y) else { throw PetSkinError.invalid("invalid canvas or anchor") }
        guard Set(PetSkinClip.allCases.map(\.rawValue)).isSubset(of: Set(manifest.clips.keys)),
              manifest.schemaVersion == 2 || (manifest.features == nil && otherAssets.isEmpty && Set(manifest.clips.keys) == Set(PetSkinClip.allCases.map(\.rawValue))) else { throw PetSkinError.invalid("seven base clips must be present; v1 allows no extra clips or features") }
        if manifest.schemaVersion == 2, !manifest.clips.keys.allSatisfy({ $0.range(of: "^[a-zA-Z][a-zA-Z0-9]{0,39}$",options: .regularExpression) != nil }) { throw PetSkinError.invalid("invalid clip name") }
        var uniqueFrames = Set<String>(), frameCount = 0
        for (clip, animation) in manifest.clips {
            guard animation.fps.isFinite, (1...60).contains(animation.fps), (2...120).contains(animation.frames.count) else { throw PetSkinError.invalid("invalid \(clip) duration or frame rate") }
            frameCount += animation.frames.count
            guard frameCount <= (manifest.schemaVersion == 1 ? 480 : 2048) else { throw PetSkinError.invalid("too many frame references") }
            for frame in animation.frames {
                guard safePNGPath(frame) else { throw PetSkinError.invalid("unsafe PNG path") }
                uniqueFrames.insert(frame)
            }
        }
        let extras = try manifest.features?.validate(base: manifest)
        frameCount += extras?.references ?? 0
        guard frameCount <= (manifest.schemaVersion == 1 ? 480 : 2048) else { throw PetSkinError.invalid("too many frame references") }
        uniqueFrames.formUnion(extras?.frames ?? [])
        guard otherAssets == (extras?.other ?? []) else { throw PetSkinError.invalid("unreferenced script or sound") }
        for path in otherAssets {
            guard safeAssetPath(path) else { throw PetSkinError.invalid("unsafe asset path") }
            let data = try Data(contentsOf: root.appendingPathComponent(path))
            if path.hasSuffix(".js") {
                guard data.count <= 128*1024, String(data: data, encoding: .utf8) != nil else { throw PetSkinError.invalid("script must be UTF-8 and at most 128 KiB") }
            } else {
                guard data.count <= 8*1024*1024, let sound = NSSound(contentsOf: root.appendingPathComponent(path), byReference: true), sound.duration > 0, sound.duration <= 30 else { throw PetSkinError.invalid("sound must decode and be at most 30s/8 MiB") }
            }
        }
        var referencedPNGs = uniqueFrames
        var pixels = uniqueFrames.count * size.width * size.height
        if let path = manifest.appIcon {
            guard safePNGPath(path) else { throw PetSkinError.invalid("unsafe appIcon path") }
            let iconSize = try pngSize(at: root.appendingPathComponent(path))
            guard iconSize.width == iconSize.height, [128, 256, 512, 1024].contains(iconSize.width) else {
                throw PetSkinError.invalid("appIcon must be square 128, 256, 512 or 1024 pixels")
            }
            if !uniqueFrames.contains(path) { pixels += iconSize.width * iconSize.height }
            referencedPNGs.insert(path)
        }
        for path in extras?.images ?? [] {
            guard safePNGPath(path) else { throw PetSkinError.invalid("unsafe image path") }
            let dimensions = try pngSize(at: root.appendingPathComponent(path))
            if manifest.features?.themes?.values.contains(where: { $0.appIcon == path }) == true {
                guard dimensions.width == dimensions.height && [128,256,512,1024].contains(dimensions.width) else { throw PetSkinError.invalid("theme appIcon must be square 128/256/512/1024") }
            }
            if !referencedPNGs.contains(path) { pixels += dimensions.width*dimensions.height }
            referencedPNGs.insert(path)
        }
        guard manifest.schemaVersion != 1 || (entries <= 600 && totalBytes <= 32*1024*1024 && manifestData.count <= 64*1024) else { throw PetSkinError.invalid("v1 package exceeds budget") }
        guard referencedPNGs == packagePNGs else { throw PetSkinError.invalid("missing or unreferenced PNG assets") }
        guard pixels <= 16_777_216 else { throw PetSkinError.invalid("more than 16 megapixels across images") }
        for frame in uniqueFrames {
            guard try pngSize(at: root.appendingPathComponent(frame)) == size else {
                throw PetSkinError.invalid("frame must match canvas: \(frame)")
            }
        }
        return manifest
    }

    private static func safeAssetPath(_ path: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !path.hasPrefix("/") && !path.contains("\\") && components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    private static func safePNGPath(_ path: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !path.hasPrefix("/") && !path.contains("\\") && path.hasSuffix(".png") &&
            components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    private static func pngSize(at url: URL) throws -> PetSkinSize {
        let data = try Data(contentsOf: url)
        let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        guard data.count >= 33, data.count <= 4 * 1024 * 1024,
              Array(data.prefix(8)) == signature, Array(data[12..<16]) == Array("IHDR".utf8),
              data[24] == 8, data[25] == 6,
              let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (32...1024).contains(width), (32...1024).contains(height),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width == width, image.height == height else {
            throw PetSkinError.invalid("asset must be a single 8-bit RGBA PNG, at most 1024 pixels: \(url.lastPathComponent)")
        }
        return PetSkinSize(width: width, height: height)
    }
}
