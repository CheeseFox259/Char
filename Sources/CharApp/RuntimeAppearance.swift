import AppKit
import CharCore
import CharPlatform

extension CompanionRuntime {
    var appearanceFeatures: PetSkinFeatures? { skinStore?.selectedSkin.features }
    var appearancePose: PetSkinPose? { appearancePose(for: petPlacement) }
    func appearancePose(for placement: PetPlacement) -> PetSkinPose? {
        let key = selectedSkinID+"/"+(skinStore?.selectedTheme ?? "")+"/"+placement.rawValue
        if let cached = appearancePoseCache[key] { return cached }
        guard let pose = skinStore?.selectedSkin.pose(placement: placement.rawValue,theme: skinStore?.selectedTheme) else { return nil }
        appearancePoseCache[key] = pose; return pose
    }
    var appearanceBehavior: PetSkinBehavior? { useAppearanceBehavior ? appearanceFeatures?.behavior : nil }
    func setAppearanceBehavior(_ enabled: Bool) {
        do { try skinStore?.setBehaviorEnabled(enabled); useAppearanceBehavior = enabled; router.updateSettings(effectiveSettings); panel?.surface.refresh() }
        catch { setupMessage = error.localizedDescription }
    }
    var bubbleStyle: PetBubbleStyle? { appearancePose?.bubbles }
    var effectiveBubbleDistance: Double { appearanceBehavior?.bubbleDistance ?? bubbleDistance }
    var effectiveOriginPolicy: CharSettings.OriginPolicy {
        guard let value = appearanceBehavior?.returnPolicy, value != "user", let policy = CharSettings.OriginPolicy(rawValue: value) else { return settings.originPolicy }
        return policy
    }
    var effectiveSettings: CharSettings { var value = settings; value.originPolicy = effectiveOriginPolicy; return value }
    func appearanceCapacity(for placement: PetPlacement) -> Int {
        CompanionGeometry.capacity(placement: placement,petSize: petSize,bubbleDistance: effectiveBubbleDistance,limit: appearanceBehavior?.bubbleCapacity,arcDegrees: appearanceBehavior?.bubbleArcDegrees ?? 140)
    }
    func appearanceBubbleClick(_ end: WorkEnd) {
        appearanceEvent("click",workEnd: end.rawValue,state: "bubble")
        switch appearanceBehavior?.bubbleClick {
        case "ignore": ignore(end)
        case "none": break
        default: visit(end)
        }
    }
    func appearanceOrbitProgress(_ fraction: Double) -> Double {
        let t = min(1,max(0,fraction))
        if bubbleStyle?.orbitCurve == "spring" { return 1-pow(1-t,3)*(cos(t*2*Double.pi)*0.15+0.85) }
        return CompanionGeometry.orbitProgress(t)
    }
    func appearanceAsset(_ path: String?) -> NSImage? { path.flatMap { skinStore?.asset($0,maxPixels:Int(ceil(petSize*2.2))) } }
    func appearanceColor(_ hex: String?, fallback: NSColor) -> NSColor {
        guard let hex, let bits = UInt64(hex.dropFirst(),radix: 16) else { return fallback }
        let rgba = hex.count == 9 ? bits : (bits << 8)|255
        return NSColor(calibratedRed: Double((rgba>>24)&255)/255,green: Double((rgba>>16)&255)/255,blue: Double((rgba>>8)&255)/255,alpha: Double(rgba&255)/255)
    }
    func setAppearanceTheme(_ id: String) {
        guard id != selectedThemeID else { return }
        do { try skinStore?.selectTheme(id); refreshSkins(); appearanceEvent("theme") }
        catch { setupMessage = error.localizedDescription }
    }
    func prepareAppearance() {
        appearanceScript?.stop(); appearanceScript = nil; appearanceGeneration += 1
        appearancePoseCache.removeAll()
        appearanceSoundCache.values.forEach { $0.stop() }
        appearanceSoundCache.removeAll(); appearanceSoundTimes.removeAll()
        useAppearanceBehavior = skinStore?.behaviorEnabled ?? true
        selectedThemeID = skinStore?.selectedTheme ?? ""
        router.updateSettings(effectiveSettings)
        if let path = appearanceFeatures?.script, let url = skinStore?.resourceURL(path) {
            do {
                let executable = Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("char-appearance-script")
                appearanceScript = try AppearanceScriptHost(executable: executable,source: String(contentsOf: url,encoding: .utf8))
            } catch { setupMessage = localized("形象脚本无法启动：\(error)","Could not start appearance script: \(error)") }
        }
        scheduleInstalledIcon()
        appearanceEvent("select")
    }
    func appearanceEvent(_ name: String, workEnd: String? = nil, state: String? = nil) {
        guard !appearanceApplyingActions, let features = appearanceFeatures else { return }
        appearanceApplyingActions = true
        if features.sounds?[name] != nil { playAppearanceSound(name) }
        for action in features.bindings?[name] ?? [] { applyAppearanceAction(action) }
        appearanceApplyingActions = false
        guard let script = appearanceScript else { return }
        let generation = appearanceGeneration
        var event = ["name":name,"placement":petPlacement.rawValue,"theme":skinStore?.selectedTheme ?? "","hold":snapshot.hold == nil ? "false":"true"]
        if let workEnd { event["workEnd"] = workEnd }; if let state { event["state"] = state }
        Task {
            do {
                let actions = try await script.event(event)
                guard generation == appearanceGeneration, appearanceScript === script else { return }
                for action in actions { try features.validate(action: action,manifest: skinStore!.selectedSkin) }
                appearanceApplyingActions = true
                defer { appearanceApplyingActions = false }
                for action in actions { applyAppearanceAction(action) }
            } catch {
                guard generation == appearanceGeneration else { return }
                script.stop()
                setupMessage = localized("形象脚本已停止：\(error)","Appearance script stopped: \(error)"); appearanceScript = nil
            }
        }
    }
    func applyAppearanceAction(_ action: PetSkinAction) {
        switch action.type {
        case "playClip": if let clip = action.value, appearancePose?.clips[clip] != nil { panel?.surface.appearanceFeedback(clip) }
        case "setTheme": if let theme = action.value { setAppearanceTheme(theme) }
        case "playSound": if let sound = action.value { playAppearanceSound(sound) }
        case "setPlacement": if let value = action.value, let placement = PetPlacement(rawValue: value), placement != petPlacement { setPlacement(placement) }
        case "visitAgent": if let value = action.value, let end = WorkEnd(rawValue: value) { visit(end) }
        case "ignoreAgent": if let value = action.value, let end = WorkEnd(rawValue: value) { ignore(end) }
        case "endHold": endHold()
        case "returnHome": returnHome()
        case "showSettings": showSettings()
        case "cycleBubbles": _ = panel?.surface.cycleBubbles(by: action.steps ?? 0)
        default: break
        }
    }
    @discardableResult func appearanceClick() -> Bool {
        appearanceEvent("click",state: "pet")
        switch appearanceBehavior?.click {
        case "settings": showSettings(); return true
        case "return": returnHome(); return true
        case "none": return true
        default: return false
        }
    }
    @discardableResult func playAppearanceSound(_ id: String) -> Bool {
        guard !demo, settings.soundEnabled, let descriptor = appearanceFeatures?.sounds?[id] else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        // A configured sound in cooldown is handled; do not replace it with Ping.
        guard now-(appearanceSoundTimes[id] ?? -.infinity) >= (descriptor.cooldown ?? 0.3) else { return true }
        if appearanceSoundCache[id] == nil, let url = skinStore?.resourceURL(descriptor.file) { appearanceSoundCache[id] = NSSound(contentsOf: url,byReference: true) }
        guard let sound = appearanceSoundCache[id] else { return false }
        sound.volume = Float(descriptor.volume ?? 1); sound.stop()
        guard sound.play() else { return false }
        appearanceSoundTimes[id] = now
        return true
    }
    func scheduleInstalledIcon() {
        appearanceIconTask?.cancel()
        guard !demo, Bundle.main.bundleURL.pathExtension == "app" else { return }
        let isDefault = selectedSkinID == PetSkinStore.defaultID
        // Preserve the authored PNG for installation; small UI images never expand
        // into a 1024-point AppKit drawing cache just to re-encode the same file.
        let data: Data?
        if isDefault { data = nil }
        else if let url = skinStore?.applicationIconURL(for:selectedSkinID) { data = try? Data(contentsOf:url) }
        else {
            data = autoreleasepool {
                skinStore?.icon(for:selectedSkinID,maxPixels:1024)?.cgImage(forProposedRect:nil,context:nil,hints:nil)
                    .flatMap { NSBitmapImageRep(cgImage:$0).representation(using:.png,properties:[:]) }
            }
        }
        guard isDefault || data != nil else { return }
        let app = Bundle.main.bundleURL, archive = store.fileURL.deletingLastPathComponent().appendingPathComponent("ReleaseBackups/AppearanceIcons")
        appearanceIconTask = Task {
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
                try await AppearanceIconWorker.shared.synchronize(app: app,png: isDefault ? nil:data,archive: archive)
                if !Task.isCancelled { installedIconStatus = localized("安装图标已同步", "Installed icon synchronized") }
            } catch is CancellationError { }
            catch { if !Task.isCancelled { installedIconStatus = localized("图标同步失败：\(error.localizedDescription)","Icon sync failed: \(error.localizedDescription)") } }
        }
    }
    /// Map view-space gaze into the authored canvas after edge orientation/mirroring.
    func authoredGaze(_ gaze: NSPoint, placement: PetPlacement? = nil) -> NSPoint {
        let placement = placement ?? petPlacement
        let pose = appearancePose(for: placement)
        let angle = (pose?.rotation ?? CompanionPlayback.edgeRotation(placement: placement)) * .pi/180
        let x = gaze.x*cos(angle)+gaze.y*sin(angle), y = -gaze.x*sin(angle)+gaze.y*cos(angle)
        return NSPoint(x: pose?.mirrorX == true ? -x:x,y: y)
    }
    func trackingFrameIndex(clip: String, elapsed: Double, placement: PetPlacement) -> Int {
        appearancePose(for: placement)?.clips[clip]?.frameIndex(elapsed: elapsed,
            looping: clip == "idle" || appearanceFeatures?.loopingClips?.contains(clip) == true) ?? 0
    }
    func drawAppearanceTracking(in rect: NSRect, gaze: NSPoint, placement: PetPlacement, clip: String, elapsed: Double) {
        guard let tracking = appearancePose(for: placement)?.tracking else { return }
        let index = trackingFrameIndex(clip: clip,elapsed: elapsed,placement: placement)
        let frameData = appearancePose(for: placement)?.clips[clip]?.trackingFrames?[index]
        let opacity = frameData?.opacity ?? 1
        guard opacity > 0 else { return }
        let state = frameData?.state.flatMap { tracking.states?[$0] }
        let head = frameData?.state == nil ? tracking.head : state?.head
        let eyes = frameData?.state == nil ? tracking.eyes : state?.eyes
        var g = authoredGaze(gaze,placement: placement)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if let context = NSGraphicsContext.current?.cgContext {
            context.setAlpha(opacity)
            if let t = frameData?.transform {
                let affine = CGAffineTransform(a: t[0],b: t[1],c: t[2],d: t[3],tx: t[4],ty: t[5])
                guard abs(affine.a*affine.d-affine.b*affine.c) > 0.000001 else { return }
                // Convert the author's normalized top-left map into the view's y-up coordinates.
                context.translateBy(x: rect.minX,y: rect.maxY); context.scaleBy(x: rect.width,y: -rect.height)
                context.concatenate(affine)
                context.scaleBy(x: 1/rect.width,y: -1/rect.height); context.translateBy(x: -rect.minX,y: -rect.maxY)
                let inv = affine.inverted()
                g = NSPoint(x: inv.a*g.x-inv.c*g.y,y: -inv.b*g.x+inv.d*g.y)
                g.x = min(1,max(-1,g.x)); g.y = min(1,max(-1,g.y))
            }
        }
        func frame(_ r: PetSkinRegion) -> NSRect { NSRect(x: rect.minX+r.x*rect.width,y: rect.minY+(1-r.y-r.height)*rect.height,width: r.width*rect.width,height: r.height*rect.height) }
        if let head {
            let horizontal = g.x > 0.25 ? "e":g.x < -0.25 ? "w":"", vertical = g.y > 0.25 ? "n":g.y < -0.25 ? "s":""
            let direction = vertical+horizontal
            appearanceAsset(head.poses[direction.isEmpty ? "center":direction] ?? head.poses["center"])?.draw(in: frame(head.rect))
        }
        for eye in eyes ?? [] {
            var target = frame(eye.rect)
            target.origin.x += g.x*(eye.travelX ?? 0.025)*rect.width
            target.origin.y += g.y*(eye.travelY ?? 0.025)*rect.height
            appearanceAsset(eye.image)?.draw(in: target)
        }
    }
}
