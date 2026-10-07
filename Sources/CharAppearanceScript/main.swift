import Foundation
import JavaScriptCore

// No native object, file, process, console or networking bridge is installed.
let context = JSContext()!
var scriptError: String?
context.exceptionHandler = { _, value in scriptError = value?.toString() ?? "JavaScript exception" }
while let line = readLine() {
    var reply: [String:Any] = [:]
    do {
        guard line.utf8.count <= 1_048_576, let request = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String:Any], let id = request["id"] as? Int else { throw NSError(domain: "CharScript",code: 1) }
        reply["id"] = id; scriptError = nil
        if request["method"] as? String == "init" {
            guard let source = request["source"] as? String, source.utf8.count <= 131_072 else { throw NSError(domain: "CharScript",code: 2) }
            context.evaluateScript(source)
            guard context.objectForKeyedSubscript("onEvent")?.isObject == true else { throw NSError(domain: "CharScript",code: 3,userInfo: [NSLocalizedDescriptionKey:"define onEvent(event)"]) }
            reply["actions"] = [] as [String]
        } else {
            let event = request["event"] as? [String:Any] ?? [:]
            // Return JSON rather than bridging arbitrary JS objects to the host.
            let json = String(decoding: try JSONSerialization.data(withJSONObject: event),as: UTF8.self)
            let encoded = context.evaluateScript("JSON.stringify(onEvent(\(json)) || [])")?.toString() ?? "[]"
            guard encoded.utf8.count <= 32_768 else { throw NSError(domain: "CharScript",code: 4) }
            reply["actions"] = try JSONSerialization.jsonObject(with: Data(encoded.utf8))
        }
        if let scriptError { throw NSError(domain: "CharScript",code: 5,userInfo: [NSLocalizedDescriptionKey:scriptError]) }
    } catch { reply["error"] = String(error.localizedDescription.prefix(500)); reply["actions"] = [] as [String] }
    let data = (try? JSONSerialization.data(withJSONObject: reply)) ?? Data("{}".utf8)
    FileHandle.standardOutput.write(data + Data([10]))
}
