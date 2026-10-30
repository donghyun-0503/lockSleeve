import Foundation
@main struct WallpaperStoreTests {
    static func main() throws {
        let folder = URL(fileURLWithPath: "/tmp/lockalbum-fixture")
        let store = WallpaperStore(directory: folder)
        let config = try PropertyListSerialization.data(fromPropertyList: ["type": "imageFile", "url": ["relative": folder.appendingPathComponent("album-fixture.png").absoluteString]], format: .binary, options: 0)
        let surface: [String: Any] = ["Content": ["Choices": [["Configuration": config]]]]
        assert(store.owned(surface))
        assert(!store.owned(["Content": ["Choices": []]]))
        let fixture: [String: Any] = ["AllSpacesAndDisplays": ["Type": "individual", "Desktop": ["value": "original"], "Idle": ["value": "screensaver"]], "Displays": ["display": ["Type": "linked", "Linked": ["value": "linked-original"]]], "Unrelated": "preserve"]
        let changed = store.map(fixture, original: nil) { _, _ in surface }
        assert(((changed["AllSpacesAndDisplays"] as! [String: Any])["Idle"] as! [String: String])["value"] == "screensaver")
        assert(store.owned((changed["Displays"] as! [String: Any])["display"].flatMap { ($0 as? [String: Any])?["Linked"] } as! [String: Any]))
        let restored = store.map(changed, original: fixture) { current, backup in store.owned(current) ? backup! : current }
        assert(NSDictionary(dictionary: fixture).isEqual(to: restored))
        let testDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDirectory) }
        let liveURL = testDirectory.appendingPathComponent("Index.plist")
        let isolated = WallpaperStore(directory: testDirectory, storeURL: liveURL)
        func imageSurface(_ name: String) throws -> [String: Any] {
            let config = try PropertyListSerialization.data(fromPropertyList: ["type": "imageFile", "url": ["relative": "file:///tmp/\(name).png"]], format: .binary, options: 0)
            return ["Content": ["Choices": [["Provider": "com.apple.wallpaper.choice.image", "Configuration": config]]]]
        }
        let oldImage = try imageSurface("old")
        let newImage = try imageSurface("new")
        let own: [String: Any] = ["Content": ["Choices": [["Provider": "local.lockalbum.app.wallpaper"]]]]
        let backup: [String: Any] = ["AllSpacesAndDisplays": ["Desktop": oldImage], "SystemDefault": ["Desktop": oldImage]]
        let live: [String: Any] = ["AllSpacesAndDisplays": ["Desktop": newImage], "SystemDefault": ["Desktop": own]]
        func write(_ root: [String: Any], to url: URL) throws {
            try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0).write(to: url)
        }
        try write(backup, to: isolated.backupURL)
        try write(live, to: liveURL)
        let liveImage = try isolated.originalImageURL()
        assert(liveImage.lastPathComponent == "new.png", "Stale backup must not override the live wallpaper")
        assert(!isolated.extensionIsSelected(), "Mixed user/app surfaces require recapturing the desktop")
        let merged = isolated.originalState(current: live, backup: backup)
        assert(NSDictionary(dictionary: (merged["AllSpacesAndDisplays"] as! [String: Any])["Desktop"] as! [String: Any]).isEqual(to: newImage))
        assert(NSDictionary(dictionary: (merged["SystemDefault"] as! [String: Any])["Desktop"] as! [String: Any]).isEqual(to: oldImage))
        try write(["AllSpacesAndDisplays": ["Desktop": own], "SystemDefault": ["Desktop": own]], to: liveURL)
        assert(isolated.extensionIsSelected())
        let savedImage = try isolated.originalImageURL()
        assert(savedImage.lastPathComponent == "old.png", "Active extension still needs original backup")
        print("PASS: new wallpaper takes precedence, backup rebasing preserves user choices, mixed surfaces detected")
        print("PASS: image ownership, nested desktop/linked updates, screen saver preservation, exact restoration")
    }
}
