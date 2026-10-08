import Foundation

/// Report spelling errors instead of silently dropping an author's requested capability.
enum PetSkinJSONContract {
    static func validate(_ data: Data) throws {
        let root = try JSONSerialization.jsonObject(with: data) as? [String:Any] ?? [:]
        guard root["schemaVersion"] as? Int == 2 else {
            throw PetSkinError.invalid("unsupported schema version; appearance packages require schemaVersion 2")
        }
        func keys(_ value: Any?, _ allowed: Set<String>, _ path: String) throws -> [String:Any] {
            guard let value, !(value is NSNull) else { return [:] }
            guard let object = value as? [String:Any] else { throw PetSkinError.invalid("\(path) must be an object") }
            let unknown = Set(object.keys).subtracting(allowed)
            guard unknown.isEmpty else { throw PetSkinError.invalid("unknown \(path) fields: \(unknown.sorted().joined(separator: ", "))") }
            return object
        }
        func region(_ value: Any?) throws { _ = try keys(value,["x","y","width","height","shape"],"region") }
        func trackingLayers(_ t: [String:Any]) throws {
            for eye in t["eyes"] as? [Any] ?? [] { let e = try keys(eye,["image","rect","clipRegion","travelX","travelY"],"eye"); try region(e["rect"]); try region(e["clipRegion"]) }
            let h = try keys(t["head"],["rect","poses"],"head"); try region(h["rect"])
        }
        func tracking(_ value: Any?) throws {
            let t = try keys(value,["eyes","head","states"],"tracking")
            try trackingLayers(t)
            for state in (t["states"] as? [String:Any] ?? [:]).values {
                try trackingLayers(keys(state,["eyes","head"],"tracking state"))
            }
        }
        func clips(_ value: Any?) throws {
            for clip in (value as? [String:Any] ?? [:]).values {
                let c = try keys(clip,["frames","fps","trackingFrames"],"clip")
                for frame in c["trackingFrames"] as? [Any] ?? [] { _ = try keys(frame,["transform","opacity","state"],"tracking frame") }
            }
        }
        func variants(_ value: Any?) throws {
            for variant in (value as? [String:Any] ?? [:]).values {
                let v = try keys(variant,["clips","anchor","rotation","mirrorX","tracking"],"variant")
                _ = try keys(v["anchor"],["x","y"],"anchor"); try clips(v["clips"]); try tracking(v["tracking"])
            }
        }
        func bubbles(_ value: Any?) throws {
            _ = try keys(value,["shell","cliBadge","statusColors","fontName","fontSize","hoverColor","hoverGlow","hoverAmplitude","hoverDuration","shatterDuration","shatterTravel","shatterDivisions","orbitDuration","orbitCurve"],"bubbles")
        }
        _ = try keys(root,["schemaVersion","id","name","canvasSize","anchor","clips","appIcon","features"],"manifest")
        _ = try keys(root["canvasSize"],["width","height"],"canvasSize"); _ = try keys(root["anchor"],["x","y"],"anchor"); try clips(root["clips"])
        let f = try keys(root["features"],["variants","themes","defaultTheme","tracking","bubbles","edgeBoundary","sounds","soundBindings","bindings","behavior","hitRegions","script","loopingClips"],"features")
        _ = try keys(f["edgeBoundary"],["width","thickness","opacity","glowOpacity","glowRadius"],"edgeBoundary")
        try variants(f["variants"]); try tracking(f["tracking"]); try bubbles(f["bubbles"])
        for theme in (f["themes"] as? [String:Any] ?? [:]).values {
            let t = try keys(theme,["name","clips","variants","tracking","bubbles","appIcon"],"theme")
            try clips(t["clips"]); try variants(t["variants"]); try tracking(t["tracking"]); try bubbles(t["bubbles"])
        }
        for sound in (f["sounds"] as? [String:Any] ?? [:]).values { _ = try keys(sound,["file","files","volume","cooldown"],"sound") }
        for actions in (f["bindings"] as? [String:Any] ?? [:]).values {
            for action in actions as? [Any] ?? [] { _ = try keys(action,["type","value","steps"],"action") }
        }
        _ = try keys(f["behavior"],["click","bubbleClick","returnPolicy","followFocus","edgeSnapDistance","edgeInset","collision","bubbleDistance","bubbleCapacity","bubbleArcDegrees","bubbleStartDegrees","bubbleClockwise"],"behavior")
        for r in f["hitRegions"] as? [Any] ?? [] { try region(r) }
    }
}
