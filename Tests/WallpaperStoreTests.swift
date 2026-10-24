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
        print("PASS: image ownership, nested desktop/linked updates, screen saver preservation, exact restoration")
    }
}
