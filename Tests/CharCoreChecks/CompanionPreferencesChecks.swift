import Foundation
import CoreGraphics
import CharCore

struct CompanionPreferencesChecks {
    func run() throws {
        let legacy = Data(#"{"placement":"left","displays":{"1":{"x":10,"y":200,"placement":"left"},"2":{"x":800,"y":100,"placement":"desktop"}}}"#.utf8)
        var state = try JSONDecoder().decode(CompanionPreferences.self, from: legacy)
        try checkEqual(state.placement, .left)
        try checkEqual(state.petSize, 48)
        try checkEqual(state.bubbleDistance, 20)
        let first = CGRect(x: 0, y: 0, width: 1400, height: 900)
        let second = CGRect(x: 1400, y: -300, width: 1920, height: 1080)
        state.remember(center: CGPoint(x: 350, y: 450), in: first)
        try checkEqual(state.center(in: second), CGPoint(x: 1880, y: 240))
        try checkEqual(state.placement, .left)
        state.setSize(200); try checkEqual(state.petSize, 88)
        state.setSize(0); try checkEqual(state.petSize, 36)
        state.setSize(.nan); try checkEqual(state.petSize, 48)
        state.setBubbleDistance(0); try checkEqual(state.bubbleDistance, 8)
        state.setBubbleDistance(200); try checkEqual(state.bubbleDistance, 72)
        state.setBubbleDistance(.nan); try checkEqual(state.bubbleDistance, 20)
        state.setBubbleDistance(32)
        state.setSize(64)
        let data = try JSONEncoder().encode(state)
        try checkEqual(try JSONDecoder().decode(CompanionPreferences.self, from: data), state)
        try check(!String(decoding: data, as: UTF8.self).contains("displays"))
    }
}
