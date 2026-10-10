import Foundation
public enum SetupError:LocalizedError {case invalidSettings, changed, missingClaude, missingHelper
 public var errorDescription:String? {switch self {case .invalidSettings:return "Claude settings are not valid. Nothing was overwritten.";case .changed:return "Claude settings changed during setup. Please retry.";case .missingClaude:return "Install and sign in to Claude Code first, then retry.";case .missingHelper:return "The bundled tracking helper is missing. Rebuild or reinstall the app."}}
}
public enum HookInstaller {
 public static let events=["SessionStart","UserPromptSubmit","PreToolUse","PostToolUse","PostToolUseFailure","PermissionRequest","Notification","Stop","SessionEnd"]
 static func command(_ u:URL)->String {"'"+u.path.replacingOccurrences(of:"'",with:"'\\''")+"' --claude-companion"}
 public static func install(settingsURL:URL,executableURL:URL) throws {try edit(settingsURL,executableURL,true)}
 public static func uninstall(settingsURL:URL,executableURL:URL) throws {try edit(settingsURL,executableURL,false)}
 public static func installed(settingsURL:URL,executableURL:URL)->Bool {
 guard let d=try? Data(contentsOf:settingsURL),let p=try? JSONSerialization.jsonObject(with:d) as? [String:Any],let h=p["hooks"] as? [String:[[String:Any]]] else{return false}
 return events.allSatisfy {name in (h[name] ?? []).contains {entry in (entry["hooks"] as? [[String:Any]] ?? []).contains {$0["command"] as? String == command(executableURL)}}}
 }
 static func edit(_ url:URL,_ helper:URL,_ install:Bool) throws {
 let fm=FileManager.default;try AppPaths.privateDirectory(url.deletingLastPathComponent())
 let original=fm.fileExists(atPath:url.path) ? try Data(contentsOf:url) : nil
 var root:[String:Any]=[:]
 if let original {guard let parsed=try JSONSerialization.jsonObject(with:original) as? [String:Any] else {throw SetupError.invalidSettings};root=parsed}
 if root["hooks"] != nil && !(root["hooks"] is [String:Any]) {throw SetupError.invalidSettings}
 var hooks=root["hooks"] as? [String:Any] ?? [:]
 for name in events {
 if hooks[name] != nil && !(hooks[name] is [[String:Any]]) {throw SetupError.invalidSettings}
 var entries=hooks[name] as? [[String:Any]] ?? []
 entries=entries.compactMap { entry in
 guard let commands=entry["hooks"] as? [[String:Any]] else{return entry}
 let others=commands.filter{$0["command"] as? String != command(helper)}
 if others.count == commands.count {return entry};if others.isEmpty{return nil};var updated=entry;updated["hooks"]=others;return updated
 }
 if install {entries.append(["matcher":"","hooks":[["type":"command","command":command(helper),"timeout":2]]])}
 if entries.isEmpty {hooks.removeValue(forKey:name)} else {hooks[name]=entries}
 }
 if hooks.isEmpty {root.removeValue(forKey:"hooks")} else {root["hooks"]=hooks}
 let updated=try JSONSerialization.data(withJSONObject:root,options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes])
 if original == updated {return}
 if let original {let backup=url.deletingLastPathComponent().appendingPathComponent("settings.companion-backup-\(UUID().uuidString).json");try original.write(to:backup,options:.atomic);try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:backup.path)}
 let current=fm.fileExists(atPath:url.path) ? try Data(contentsOf:url) : nil;guard current == original else {throw SetupError.changed}
 try updated.write(to:url,options:.atomic);try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
 }
}
