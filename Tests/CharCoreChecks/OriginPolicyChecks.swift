import Foundation
import CharCore

func originPolicyChecks() throws {
    let now = Date()
    let end = WorkEnd(rawValue: "independent.policy.client")!
    let a = ReturnAnchor(id:"first",bundleIdentifier:"com.example.first",token:"a",accuracy:.exact)
    let b = ReturnAnchor(id:"second",bundleIdentifier:"com.example.second",token:"b",accuracy:.application)
    for policy in CharSettings.OriginPolicy.allCases {
        let settings = CharSettings(filterSeconds:0,originPolicy:policy)
        let router = AttentionRouter(startedAt:now,settings:settings)
        let keys = ["one","two","three"].map { SessionKey(workEnd:end,nativeID:$0) }
        router.ingest(keys.map { ObservationEvent(key:$0,target:SessionTarget(bundleIdentifier:"com.example.client"),timestamp:now,state:.stopped(.question)) })
        router.advance(to:now)
        router.completeVisit(key:keys[0],outcome:.exact,sourceAnchor:a,at:now)
        router.completeVisit(key:keys[1],outcome:.fallback,sourceAnchor:b,at:now)
        try checkEqual(router.snapshot.hold?.anchor.id, policy == .disabled ? nil : policy == .original ? a.id : b.id)
        router.completeVisit(key:keys[2],outcome:.unavailable,sourceAnchor:a,at:now)
        try checkEqual(router.snapshot.hold?.anchor.id, policy == .disabled ? nil : policy == .original ? a.id : b.id)
        var disabled = settings; disabled.originPolicy = .disabled; router.updateSettings(disabled)
        try check(router.snapshot.hold == nil)
    }
    let router = AttentionRouter(startedAt:now,settings:CharSettings(filterSeconds:0,applicationOrigins:false))
    let key = SessionKey(workEnd:end,nativeID:"generic")
    router.ingest([ObservationEvent(key:key,target:SessionTarget(bundleIdentifier:"com.example.client"),timestamp:now,state:.stopped(.question))]);router.advance(to:now)
    router.completeVisit(key:key,outcome:.fallback,sourceAnchor:b,at:now)
    try check(router.snapshot.hold == nil,"application origins bypassed preference")
    let legacy = Data(#"{"filterSeconds":0,"graceSeconds":10,"soundEnabled":false,"launchAtLogin":false}"#.utf8)
    let migrated = try JSONDecoder().decode(CharSettings.self,from:legacy)
    try check(migrated.originPolicy == .original && migrated.applicationOrigins,"legacy origin defaults")
}
