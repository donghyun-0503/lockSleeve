import Foundation

/// Undocumented macOS wallpaper store. Keep unrelated settings and restore only
/// surfaces that still point to an image owned by this application.
final class WallpaperStore {
    let directory: URL
    let storeURL: URL
    var backupURL: URL { directory.appendingPathComponent("wallpaper-store-backup.plist") }
    init(directory: URL, storeURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")) {
        self.directory = directory; self.storeURL = storeURL
    }
    /// Live, user-selected surfaces win. Only our own surfaces need the backup.
    func originalState(current: [String: Any], backup: [String: Any]?) -> [String: Any] {
        map(current, original: backup) { surface, saved in
            self.owned(surface) ? (saved ?? surface) : surface
        }
    }

    func dictionary(_ data: Data) throws -> [String: Any] {
        guard let result = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw NSError(domain: "LockAlbum", code: 10, userInfo: [NSLocalizedDescriptionKey: "배경 설정 형식을 읽을 수 없습니다."])
        }
        return result
    }
    func owned(_ surface: [String: Any]) -> Bool {
        guard let content = surface["Content"] as? [String: Any], let choices = content["Choices"] as? [[String: Any]] else { return false }
        return choices.contains { choice in
            if choice["Provider"] as? String == "local.lockalbum.app.wallpaper" { return true }
            guard let data = choice["Configuration"] as? Data,
                  let configuration = try? dictionary(data), let location = configuration["url"] as? [String: Any],
                  let relative = location["relative"] as? String, let url = URL(string: relative) else { return false }
            return url.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path && url.lastPathComponent.hasPrefix("album-")
        }
    }
    func map(_ node: [String: Any], original: [String: Any]?, transform: ([String: Any], [String: Any]?) throws -> [String: Any]) rethrows -> [String: Any] {
        var result = node
        // Desktop also drives the lock-screen wallpaper. Idle is the screen saver.
        for key in ["Desktop", "Linked"] {
            if let surface = node[key] as? [String: Any] {
                result[key] = try transform(surface, original?[key] as? [String: Any])
            }
        }
        for (key, value) in node where key != "Desktop" && key != "Linked" && key != "Idle" {
            if let child = value as? [String: Any] {
                result[key] = try map(child, original: original?[key] as? [String: Any], transform: transform)
            }
        }
        return result
    }
    func originalImageURL() throws -> URL {
        let current = try dictionary(Data(contentsOf: storeURL))
        let backup = try existingBackup()
        let root = originalState(current: current, backup: backup)
        var result: URL?
        // The active shared wallpaper takes precedence over the system default.
        let ordered = ["AllSpacesAndDisplays", "Spaces", "Displays", "SystemDefault"]
        for key in ordered {
            guard let node = root[key] as? [String: Any] else { continue }
            _ = map(node, original: nil) { surface, _ in
            if result == nil, let content = surface["Content"] as? [String: Any], let choices = content["Choices"] as? [[String: Any]] {
                for choice in choices {
                    if let data = choice["Configuration"] as? Data, let config = try? self.dictionary(data),
                       config["type"] as? String == "imageFile", let url = config["url"] as? [String: Any],
                       let relative = url["relative"] as? String, let candidate = URL(string: relative), candidate.isFileURL { result = candidate; break }
                }
            }
            return surface
        }
            if result != nil { break }
        }
        guard let result else { throw NSError(domain: "LockAlbum", code: 31, userInfo: [NSLocalizedDescriptionKey: "이 모드는 정적인 이미지 배경이 필요합니다."]) }
        return result
    }
    func existingBackup() throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: backupURL.path) else { return nil }
        return try dictionary(Data(contentsOf: backupURL))
    }
    func extensionIsSelected() -> Bool {
        guard let data = try? Data(contentsOf: storeURL), let root = try? dictionary(data) else { return false }
        var found = false
        var allSelected = true
        _ = map(root, original: nil) { surface, _ in
            found = true
            let content = surface["Content"] as? [String: Any]
            let choices = content?["Choices"] as? [[String: Any]] ?? []
            if !choices.contains(where: { $0["Provider"] as? String == "local.lockalbum.app.wallpaper" }) { allSelected = false }
            return surface
        }
        return found && allSelected
    }
    func applyExtension(framesDirectory: URL) throws {
        if extensionIsSelected() { return }
        try apply(choice: ["Provider": "local.lockalbum.app.wallpaper", "Configuration": Data("live".utf8), "Files": []])
    }
    func apply(imageURL: URL) throws {
        let config = try PropertyListSerialization.data(fromPropertyList: ["type": "imageFile", "url": ["relative": imageURL.absoluteString]], format: .binary, options: 0)
        try apply(choice: ["Provider": "com.apple.wallpaper.choice.image", "Configuration": config, "Files": []])
    }
    private func apply(choice: [String: Any]) throws {
        let data = try Data(contentsOf: storeURL)
        let root = try dictionary(data)
        var count = 0
        let updated = map(root, original: nil) { surface, _ in
            var surface = surface
            var content = surface["Content"] as? [String: Any] ?? [:]
            content["Choices"] = [choice]
            content["Shuffle"] = "$null"
            surface["Content"] = content
            surface["LastSet"] = Date(); surface["LastUse"] = Date()
            count += 1
            return surface
        }
        guard count > 0 else { throw NSError(domain: "LockAlbum", code: 11, userInfo: [NSLocalizedDescriptionKey: "지원하지 않는 배경 설정 형식입니다."]) }
        let original = originalState(current: root, backup: try existingBackup())
        let saved = try PropertyListSerialization.data(fromPropertyList: original, format: .binary, options: 0)
        try saved.write(to: backupURL, options: .atomic)
        try write(updated)
    }
    func restore() throws {
        guard FileManager.default.fileExists(atPath: backupURL.path) else { return }
        let original = try dictionary(Data(contentsOf: backupURL))
        let current = try dictionary(Data(contentsOf: storeURL))
        var changes = 0
        let restored = map(current, original: original) { surface, backup in
            guard self.owned(surface), let backup else { return surface }
            changes += 1
            return backup
        }
        if changes > 0 { try write(restored) }
        try FileManager.default.removeItem(at: backupURL)
    }
    func runAgent(_ arguments: [String]) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = arguments + ["WallpaperAgent"]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        // Exit 1 means the agent was not running; launchd starts it when needed.
        guard process.terminationStatus <= 1 else { throw NSError(domain: "LockAlbum", code: 12, userInfo: [NSLocalizedDescriptionKey: "WallpaperAgent 갱신 실패"] ) }
    }
    func write(_ root: [String: Any]) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        // Prevent the agent from flushing stale state over the atomic write.
        try runAgent(["-STOP"])
        do { try data.write(to: storeURL, options: .atomic) }
        catch { try? runAgent(["-CONT"]); throw error }
        try runAgent(["-TERM"])
        try runAgent(["-CONT"])
    }
}
