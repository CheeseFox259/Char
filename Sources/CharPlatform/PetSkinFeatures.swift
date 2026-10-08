import AppKit

/// Optional v2 capabilities. All coordinates use normalized top-left canvas space.
public struct PetSkinFeatures: Codable, Equatable {
    public var variants: [String: PetSkinVariant]?
    public var themes: [String: PetSkinTheme]?
    public var defaultTheme: String?
    public var tracking: PetSkinTracking?
    public var bubbles: PetBubbleStyle?
    public var edgeBoundary: PetSkinEdgeBoundary?
    public var sounds: [String: PetSkinSound]?
    public var soundBindings: [String: String]?
    public var bindings: [String: [PetSkinAction]]?
    public var behavior: PetSkinBehavior?
    public var hitRegions: [PetSkinRegion]?
    public var script: String?
    public var loopingClips: [String]?
}
public struct PetSkinVariant: Codable, Equatable {
    public var clips: [String: PetSkinAnimation]?
    public var anchor: PetSkinAnchor?
    /// Explicit degrees replace the host edge rotation. Omit to rotate bottom-facing artwork automatically.
    public var rotation: Double?
    public var mirrorX: Bool?
    public var tracking: PetSkinTracking?
}
public struct PetSkinTheme: Codable, Equatable {
    public var name: String
    public var clips: [String: PetSkinAnimation]?
    public var variants: [String: PetSkinVariant]?
    public var tracking: PetSkinTracking?
    public var bubbles: PetBubbleStyle?
    public var appIcon: String?
}
public struct PetSkinRegion: Codable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var shape: String? // rect or ellipse
    public func contains(_ point: NSPoint) -> Bool {
        guard point.x >= x, point.y >= y, point.x <= x+width, point.y <= y+height else { return false }
        if shape == "ellipse" { return pow((point.x-x-width/2)/(width/2),2)+pow((point.y-y-height/2)/(height/2),2) <= 1 }
        return true
    }
}
public struct PetSkinTrackingLayer: Codable, Equatable {
    public var image: String
    public var rect: PetSkinRegion
    public var clipRegion: PetSkinRegion?
    public var travelX: Double?
    public var travelY: Double?
}
public struct PetSkinHead: Codable, Equatable {
    public var rect: PetSkinRegion
    /// center, n, ne, e, se, s, sw, w, nw. Missing directions use center.
    public var poses: [String: String]
}
public struct PetSkinTracking: Codable, Equatable {
    public var eyes: [PetSkinTrackingLayer]?
    public var head: PetSkinHead?
    public var states: [String: PetSkinTrackingState]?
}
public struct PetSkinTrackingState: Codable, Equatable {
    public var eyes: [PetSkinTrackingLayer]?
    public var head: PetSkinHead?
}
public struct PetSkinTrackingFrame: Codable, Equatable {
    /// Forward affine map [a,b,c,d,tx,ty], normalized top-left canvas coordinates.
    public var transform: [Double]?
    public var opacity: Double?
    public var state: String?
}
public extension PetSkinAnimation {
    func validateTrackingFrames() throws {
        guard let trackingFrames else { return }
        guard trackingFrames.count == frames.count else { throw PetSkinError.invalid("trackingFrames must match frames") }
        for frame in trackingFrames {
            if let t = frame.transform {
                guard t.count == 6, t.allSatisfy({ $0.isFinite && abs($0) <= 4 }) else { throw PetSkinError.invalid("invalid tracking affine transform") }
            }
            if let opacity = frame.opacity, !opacity.isFinite || !(0...1).contains(opacity) { throw PetSkinError.invalid("invalid tracking opacity") }
            if let state = frame.state, state.range(of: "^[a-zA-Z][a-zA-Z0-9]{0,39}$",options: .regularExpression) == nil { throw PetSkinError.invalid("invalid tracking state") }
        }
    }
}
public struct PetBubbleStyle: Codable, Equatable {
    public var shell: String?
    public var cliBadge: String?
    public var statusColors: [String: String]?
    public var fontName: String?
    public var fontSize: Double?
    public var hoverColor: String?
    public var hoverGlow: Double?
    public var hoverAmplitude: Double?
    public var hoverDuration: Double?
    public var shatterDuration: Double?
    public var shatterTravel: Double?
    public var shatterDivisions: Int?
    public var orbitDuration: Double?
    public var orbitCurve: String? // smooth or spring
}
/// Native, stationary light at the usable desktop edge. It never intercepts input.
public struct PetSkinEdgeBoundary: Codable, Equatable {
    public var width: Double? // Pet-size multiple; default 1.25.
    public var thickness: Double? // Points at 48pt pet size; default 1.2.
    public var opacity: Double? // Default 0.55.
    public var glowOpacity: Double? // Default 0.12.
    public var glowRadius: Double? // Points at 48pt pet size; default 4.
}
public struct PetSkinSound: Codable, Equatable {
    /// Core Audio containers; import still requires NSSound to decode the actual file.
    public static let supportedExtensions: Set<String> = ["wav", "wave", "aiff", "aif", "aifc", "m4a", "mp3", "aac", "caf", "flac"]
    public var file: String?
    public var files: [String]?
    public var paths: [String] { files ?? file.map { [$0] } ?? [] }
    public var volume: Double?
    public var cooldown: Double?
}
public struct PetSkinBehavior: Codable, Equatable {
    public var bubbleClick: String? // visit, ignore, none
    public var bubbleCapacity: Int?
    public var bubbleArcDegrees: Double?
    public var bubbleStartDegrees: Double?
    public var bubbleClockwise: Bool?
    public var click: String? // default, settings, return, none
    public var returnPolicy: String? // user, original, latest, disabled
    public var followFocus: Bool?
    public var edgeSnapDistance: Double?
    public var edgeInset: Double? // Pet-size fraction inside the usable desktop edge.
    public var collision: String? // clamp, free
    public var bubbleDistance: Double?
}
public struct PetSkinAction: Codable, Equatable {
    public var type: String
    public var value: String?
    public var steps: Int?
    public init(type: String, value: String? = nil, steps: Int? = nil) { self.type = type; self.value = value; self.steps = steps }
}
public struct PetSkinPose {
    public var clips: [String: PetSkinAnimation]
    public var anchor: PetSkinAnchor
    public var rotation: Double?
    public var mirrorX = false
    public var tracking: PetSkinTracking?
    public var bubbles: PetBubbleStyle?
    public var appIcon: String?
}
public extension PetSkinManifest {
    func pose(placement: String, theme: String?) -> PetSkinPose {
        var pose = PetSkinPose(clips: clips, anchor: anchor, tracking: features?.tracking, bubbles: features?.bubbles, appIcon: appIcon)
        func apply(_ variant: PetSkinVariant?) {
            guard let variant else { return }
            if let clips = variant.clips { pose.clips.merge(clips) { _, new in new } }
            if let anchor = variant.anchor { pose.anchor = anchor }
            if let rotation = variant.rotation { pose.rotation = rotation }
            if let mirror = variant.mirrorX { pose.mirrorX = mirror }
            if let tracking = variant.tracking { pose.tracking = tracking }
        }
        apply(features?.variants?[placement])
        if let theme, let data = features?.themes?[theme] {
            if let clips = data.clips { pose.clips.merge(clips) { _, new in new } }
            if let tracking = data.tracking { pose.tracking = tracking }
            if let bubbles = data.bubbles { pose.bubbles = bubbles }
            if let icon = data.appIcon { pose.appIcon = icon }
            apply(data.variants?[placement])
        }
        return pose
    }
}

extension PetSkinFeatures {
    static let events: Set<String> = ["select", "theme", "hoverEnter", "hoverLeave", "dragStart", "dragEnd", "click", "attention", "attentionNotified", "attentionEscalated", "spaceChanged", "return", "placement"]
    func validate(base: PetSkinManifest) throws -> (frames: Set<String>, images: Set<String>, other: Set<String>, references: Int) {
        func require(_ condition: Bool, _ reason: String) throws { if !condition { throw PetSkinError.invalid(reason) } }
        func range(_ value: Double?, _ bounds: ClosedRange<Double>) throws {
            if let value { try require(value.isFinite && bounds.contains(value), "v2 numeric value out of range") }
        }
        func region(_ r: PetSkinRegion) throws {
            try require([r.x,r.y,r.width,r.height].allSatisfy(\.isFinite) && r.x >= 0 && r.y >= 0 && r.width > 0 && r.height > 0 && r.x+r.width <= 1 && r.y+r.height <= 1 && [nil,"rect","ellipse"].contains(r.shape), "invalid normalized region")
        }
        var frames = Set<String>(), images = Set<String>(), other = Set<String>(), references = 0
        func clips(_ values: [String: PetSkinAnimation]?) throws {
            for (name, clip) in values ?? [:] {
                try require(name.range(of: "^[a-zA-Z][a-zA-Z0-9]{0,39}$", options: .regularExpression) != nil, "invalid clip name")
                try require(clip.fps.isFinite && (1...60).contains(clip.fps) && (2...120).contains(clip.frames.count), "invalid v2 clip")
                try clip.validateTrackingFrames()
                frames.formUnion(clip.frames); references += clip.frames.count
            }
        }
        func trackingLayers(_ eyes: [PetSkinTrackingLayer]?, _ head: PetSkinHead?) throws {
            try require((eyes?.count ?? 0) <= 8, "too many tracking layers")
            for eye in eyes ?? [] { images.insert(eye.image); try region(eye.rect); if let clip = eye.clipRegion { try region(clip) }; try range(eye.travelX, 0...0.15); try range(eye.travelY, 0...0.15) }
            if let head {
                try region(head.rect)
                try require(head.poses["center"] != nil && Set(head.poses.keys).isSubset(of: ["center","n","ne","e","se","s","sw","w","nw"]), "head requires center and only eight directions")
                images.formUnion(head.poses.values)
            }
        }
        func tracking(_ value: PetSkinTracking?) throws {
            try trackingLayers(value?.eyes,value?.head)
            try require((value?.states?.count ?? 0) <= 16,"too many tracking states")
            for (id,state) in value?.states ?? [:] {
                try require(id.range(of: "^[a-zA-Z][a-zA-Z0-9]{0,39}$",options: .regularExpression) != nil,"invalid tracking state name")
                try trackingLayers(state.eyes,state.head)
            }
        }
        func bubbles(_ b: PetBubbleStyle?) throws {
            if let path = b?.shell { images.insert(path) }; if let path = b?.cliBadge { images.insert(path) }
            let colors = Array(b?.statusColors?.values ?? [:].values) + [b?.hoverColor].compactMap { $0 }
            try require(colors.allSatisfy { $0.range(of: "^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$",options: .regularExpression) != nil }, "colors must be #RRGGBB or #RRGGBBAA")
            try require(Set(b?.statusColors?.keys ?? [:].keys).isSubset(of: ["pending","running","issue","interaction","ended"]), "unknown status color")
            try require((b?.fontName?.count ?? 0) <= 80, "font name too long")
            try range(b?.fontSize, 8...14); try range(b?.hoverGlow, 0...0.5); try range(b?.hoverAmplitude, 0...0.2); try range(b?.hoverDuration, 0.4...4)
            try range(b?.shatterDuration, 0.15...1); try range(b?.shatterTravel, 0...40); try range(b?.orbitDuration, 0.12...0.7)
            try require(b?.shatterDivisions == nil || (1...4).contains(b!.shatterDivisions!), "invalid fragment count")
            try require([nil,"smooth","spring"].contains(b?.orbitCurve), "invalid orbit curve")
        }
        func variants(_ values: [String: PetSkinVariant]?) throws {
            try require(Set(values?.keys ?? [:].keys).isSubset(of: ["desktop","left","right","top","bottom"]), "unknown placement variant")
            for v in values?.values ?? [:].values {
                try clips(v.clips); try tracking(v.tracking); try range(v.rotation, -360...360)
                if let a = v.anchor { try range(a.x, 0...1); try range(a.y, 0...1) }
            }
        }
        try variants(self.variants); try tracking(self.tracking); try bubbles(self.bubbles)
        try range(edgeBoundary?.width, 0.5...2); try range(edgeBoundary?.thickness, 0.5...3)
        try range(edgeBoundary?.opacity, 0...1); try range(edgeBoundary?.glowOpacity, 0...0.3)
        try range(edgeBoundary?.glowRadius, 0...10)
        try require((themes?.count ?? 0) <= 12, "too many themes")
        for (id,t) in themes ?? [:] {
            try require(id.range(of: "^[a-z][a-z0-9-]{0,39}$",options: .regularExpression) != nil && !t.name.isEmpty && t.name.count <= 80, "invalid theme")
            try clips(t.clips); try variants(t.variants); try tracking(t.tracking); try bubbles(t.bubbles)
            if let icon = t.appIcon { images.insert(icon) }
        }
        try require(defaultTheme == nil || themes?[defaultTheme!] != nil, "unknown default theme")
        for theme in [String?](arrayLiteral: nil) + (themes?.keys.map { Optional($0) } ?? []) {
            for placement in ["desktop","left","right","top","bottom"] {
                let pose = base.pose(placement: placement,theme: theme)
                for animation in pose.clips.values {
                    for frame in animation.trackingFrames ?? [] {
                        if let state = frame.state { try require(pose.tracking?.states?[state] != nil,"unknown tracking state in resolved pose") }
                    }
                }
            }
        }
        try require((sounds?.count ?? 0) <= 24, "too many sounds")
        for (_,s) in sounds ?? [:] {
            try require((s.file == nil) != (s.files == nil) && (1...24).contains(s.paths.count), "sound requires one file or a nonempty pool")
            try require(Set(s.paths).count == s.paths.count, "duplicate sound pool file")
            for path in s.paths {
                try require(PetSkinSound.supportedExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased()), "unsupported sound format")
                other.insert(path)
            }
            try range(s.volume, 0...1); try range(s.cooldown, 0...60)
        }
        try require(Set(soundBindings?.keys ?? [:].keys).isSubset(of: ["interaction", "issue", "ended", "petClick"]), "unknown sound binding")
        try require((soundBindings?.values ?? [:].values).allSatisfy { sounds?[$0] != nil }, "unknown bound sound")
        if let script { try require(script.hasSuffix(".js"), "script must be JavaScript"); other.insert(script) }
        var allClips = Set(base.clips.keys)
        for v in self.variants?.values ?? [:].values { allClips.formUnion(v.clips?.keys ?? [:].keys) }
        for t in themes?.values ?? [:].values {
            allClips.formUnion(t.clips?.keys ?? [:].keys)
            for v in t.variants?.values ?? [:].values { allClips.formUnion(v.clips?.keys ?? [:].keys) }
        }
        try require(allClips.allSatisfy { $0.range(of: "^[a-zA-Z][a-zA-Z0-9]{0,39}$",options: .regularExpression) != nil }, "invalid clip name")
        try require(Set(loopingClips ?? []).isSubset(of: allClips), "unknown looping clip")
        try require(Set(bindings?.keys ?? [:].keys).isSubset(of: Self.events), "unknown appearance event")
        for actions in bindings?.values ?? [:].values {
            try require(actions.count <= 16, "too many actions")
            for action in actions { try validate(action: action, manifest: base) }
        }
        try require([nil,"visit","ignore","none"].contains(behavior?.bubbleClick), "invalid bubble click behavior")
        try require(behavior?.bubbleCapacity == nil || (3...20).contains(behavior!.bubbleCapacity!), "invalid bubble capacity")
        try range(behavior?.bubbleArcDegrees, 60...140); try range(behavior?.bubbleStartDegrees, -360...360)
        try require([nil,"default","settings","return","none"].contains(behavior?.click), "invalid click behavior")
        try require([nil,"user","original","latest","disabled"].contains(behavior?.returnPolicy), "invalid return policy")
        try require([nil,"clamp","free"].contains(behavior?.collision), "invalid collision mode")
        try range(behavior?.edgeInset, 0...0.5); try range(behavior?.edgeSnapDistance, 0...100); try range(behavior?.bubbleDistance, 8...72)
        try require((hitRegions?.count ?? 0) <= 16 && hitRegions?.isEmpty != true, "invalid hit region count")
        for r in hitRegions ?? [] { try region(r) }
        return (frames,images,other,references)
    }
    public func validate(action: PetSkinAction, manifest: PetSkinManifest) throws {
        var all = Set(manifest.clips.keys)
        for v in self.variants?.values ?? [:].values { all.formUnion(v.clips?.keys ?? [:].keys) }
        for t in themes?.values ?? [:].values {
            all.formUnion(t.clips?.keys ?? [:].keys)
            for v in t.variants?.values ?? [:].values { all.formUnion(v.clips?.keys ?? [:].keys) }
        }
        let valid: Bool
        switch action.type {
        case "playClip": valid = action.steps == nil && action.value.map { all.contains($0) } ?? false
        case "setTheme": valid = action.steps == nil && action.value.map { $0.isEmpty || themes?[$0] != nil } ?? false
        case "playSound": valid = action.steps == nil && action.value.map { sounds?[$0] != nil } ?? false
        case "setPlacement": valid = action.steps == nil && ["desktop","left","right","top","bottom"].contains(action.value ?? "")
        case "visitAgent","ignoreAgent": valid = action.value?.range(of: "^[a-zA-Z][a-zA-Z0-9._-]{0,79}$",options: .regularExpression) != nil && action.steps == nil
        case "returnHome","showSettings","endHold": valid = action.value == nil && action.steps == nil
        case "cycleBubbles": valid = action.value == nil && [-1,1].contains(action.steps ?? 0)
        default: valid = false
        }
        guard valid else { throw PetSkinError.invalid("invalid Char action: \(action.type)") }
    }
}
