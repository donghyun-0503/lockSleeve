import AppKit
import ExtensionFoundation
import QuartzCore
import IOSurface
import os

let logger = Logger(subsystem: "local.lockalbum.app.wallpaper", category: "renderer")
func extensionLog(_ message: String) { logger.notice("\(message, privacy: .public)") }
let frameDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LockAlbum/Frames", isDirectory: true)

func property(_ name: String, in value: Any, depth: Int = 0) -> Any? {
    guard depth < 7 else { return nil }
    for child in Mirror(reflecting: value).children {
        if child.label == name { return child.value }
        if let result = property(name, in: child.value, depth: depth + 1) { return result }
    }
    return nil
}

final class Surface {
    let context: CAContext
    let root = CALayer()
    init?(size: CGSize, scale: CGFloat, display: UInt32?) {
        let raw: Any? = display.map { CAContext.remoteContext(withOptions: ["displayId": $0]) } ?? CAContext.remoteContext()
        guard let context = raw as? CAContext, context.contextId != 0 else { return nil }
        self.context = context
        root.frame = CGRect(origin: .zero, size: size)
        root.contentsScale = scale
        root.contentsGravity = .resizeAspectFill
        context.layer = root
    }
}
final class Frames {
    static let shared = Frames()
    var surfaces: [String: Surface] = [:]
    var image: CGImage?
    var revision = ""
    var timer: Timer?
    var mode = "desktop"
    func start() {
        guard timer == nil else { return }
        load()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in self.load() }
    }
    func load() {
        let state = (try? Data(contentsOf: frameDirectory.appendingPathComponent("mode.json"))).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        mode = (state?["locked"] as? Bool == true) ? "album" : "desktop"
        let url = frameDirectory.appendingPathComponent(mode == "album" ? "current.png" : "desktop.png")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return }
        let next = "\(mode)-\((attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)-\(attrs[.size] ?? "")"
        guard next != revision,
              let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        revision = next; self.image = image
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for surface in surfaces.values { surface.root.contents = image }
        CATransaction.commit(); CATransaction.flush()
        extensionLog("frame updated surfaces=\(surfaces.count)")
        heartbeat()
    }
    func heartbeat() {
        let info: [String: Any] = ["mode": mode, "pid": ProcessInfo.processInfo.processIdentifier, "surfaces": surfaces.count, "revision": revision, "time": Date().timeIntervalSince1970]
        if let data = try? JSONSerialization.data(withJSONObject: info) {
            try? data.write(to: frameDirectory.appendingPathComponent("renderer-status.json"), options: .atomic)
        }
    }
}

@main final class LockAlbumExtension: NSObject, AppExtension {
    override required init() {
        super.init()
        _ = dlopen("/System/Library/PrivateFrameworks/WallpaperExtensionKit.framework/WallpaperExtensionKit", RTLD_NOW)
        extensionLog("extension launched")
        DispatchQueue.main.async { Frames.shared.start() }
    }
    var configuration: some AppExtensionConfiguration { WallpaperConfiguration() }
}
struct WallpaperConfiguration: AppExtensionConfiguration {
    func accept(connection: NSXPCConnection) -> Bool {
        // Accept only Apple's signed wallpaper/Settings hosts.
        guard let app = NSRunningApplication(processIdentifier: connection.processIdentifier), let url = app.bundleURL,
              url.path.hasPrefix("/System/") else { return false }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              let requirement = try? makeAppleRequirement(), SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess else { return false }
        let exported = NSXPCInterface(with: WallpaperExtensionXPCProtocol.self)
        let names = ["WallpaperIDXPC", "WallpaperCreationRequestXPC", "WallpaperUpdateRequestXPC", "WallpaperRemoteContextXPC", "WallpaperSnapshotXPC", "WallpaperContentTypeSetXPC", "WallpaperChoiceIDXPC", "WallpaperChoiceIDsXPC", "WallpaperExtensionChoiceRequestXPC", "WallpaperChoiceRequestAdditionResultXPC", "WallpaperDebugRequestXPC", "WallpaperDebugResponseXPC", "WallpaperMigrationVersionXPC", "WallpaperSettingsViewModelsXPC", "AuditTokenXPC"]
        let set = NSMutableSet(array: [NSString.self, NSNumber.self, NSData.self, NSArray.self, NSDictionary.self, NSURL.self, NSError.self])
        for name in names { if let cls = NSClassFromString(name) { set.add(cls) } }
        let classes = set as! Set<AnyHashable>
        let selectors: [(String, [Int], Bool)] = [
            ("acquireWithId:request:reply:", [0,1], false), ("acquireWithId:request:reply:", [0], true),
            ("updateWithId:request:reply:", [0,1], false), ("invalidateWithId:reply:", [0], false),
            ("snapshotWithId:reply:", [0], false), ("snapshotWithId:reply:", [0], true),
            ("provideSettingsViewModelsWithContentTypes:reply:", [0], false), ("provideSettingsViewModelsWithContentTypes:reply:", [0], true),
            ("addChoiceRequestWithChoiceRequest:onBehalfOfProcess:reply:", [0,1], false), ("addChoiceRequestWithChoiceRequest:onBehalfOfProcess:reply:", [0], true),
            ("removeChoiceRequestWithChoiceRequest:reply:", [0], false), ("selectedChoicesDidChangeFor:reply:", [0], false),
            ("invokeContextMenuActionWithMenuItemID:groupItemID:reply:", [0,1], false), ("isChoiceDownloadedWith:reply:", [0], false),
            ("downloadWithChoiceID:reply:", [0], false), ("pauseDownloadFor:reply:", [0], false), ("cancelDownloadFor:reply:", [0], false),
            ("resumeDownloadFor:reply:", [0], false), ("removeDownloadFor:reply:", [0], false), ("migrateSelectedChoiceFor:reply:", [0], false),
            ("migrateSelectedChoiceFor:reply:", [0], true), ("migrateFrom:to:reply:", [0,1], false),
            ("skipShuffledContentWithId:reply:", [0], false), ("canSkipShuffledContentWithId:reply:", [0], false),
            ("handleDebugRequestFor:reply:", [0], false), ("handleDebugRequestFor:reply:", [0], true), ("handleNotificationWithNamed:reply:", [0], false)
        ]
        for (selector, indices, reply) in selectors { for index in indices { exported.setClasses(classes, for: NSSelectorFromString(selector), argumentIndex: index, ofReply: reply) } }
        connection.exportedInterface = exported
        connection.remoteObjectInterface = NSXPCInterface(with: WallpaperExtensionProxyXPCProtocol.self)
        connection.exportedObject = Handler()
        connection.resume()
        extensionLog("accepted host \(connection.processIdentifier)")
        return true
    }
    func makeAppleRequirement() throws -> SecRequirement {
        var requirement: SecRequirement?
        let status = SecRequirementCreateWithString("anchor apple" as CFString, [], &requirement)
        guard status == errSecSuccess, let requirement else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        return requirement
    }
}
final class Handler: NSObject, WallpaperExtensionXPCProtocol {
    func acquire(withId id: Any?, request: Any?, reply: @escaping (Any?, Error?) -> Void) {
        let size = request.flatMap { property("destination", in: $0) }.flatMap { property("size", in: $0) } as? CGSize ?? CGSize(width: 1512, height: 982)
        let scale = request.flatMap { property("scaleFactor", in: $0) } as? CGFloat ?? 2
        let display = request.flatMap { property("directDisplayID", in: $0) } as? UInt32
        let key = id.flatMap { property("rawValue", in: $0) }.map { String(describing: $0) } ?? "display-\(display ?? 0)"
        DispatchQueue.main.async {
            let frames = Frames.shared; frames.start(); frames.load()
            let surface = frames.surfaces[key] ?? Surface(size: size, scale: scale, display: display)
            guard let surface, let image = frames.image else { reply(nil, NSError(domain: "LockAlbum", code: 20)); return }
            frames.surfaces[key] = surface
            CATransaction.begin(); CATransaction.setDisableActions(true)
            surface.root.frame = CGRect(origin: .zero, size: size); surface.root.contentsScale = scale
            surface.root.contents = image
            CATransaction.commit(); CATransaction.flush()
            frames.heartbeat()
            extensionLog("acquire context=\(surface.context.contextId) key=\(key)")
            reply(createRemoteContextXPC(contextId: surface.context.contextId), nil)
        }
    }
    func update(withId id: Any?, request: Any?, reply: @escaping (Error?) -> Void) { DispatchQueue.main.async { Frames.shared.load(); reply(nil) } }
    func invalidate(withId id: Any?, reply: @escaping (Error?) -> Void) { reply(nil) } // Reuse contexts across lock/unlock.
    func snapshot(withId id: Any?, reply: @escaping (Any?, Error?) -> Void) {
        DispatchQueue.main.async {
            guard let image = Frames.shared.image,
                  let surface = IOSurface(properties: [.width: image.width, .height: image.height, .bytesPerElement: 4, .pixelFormat: 0x42475241]) else { reply(nil, nil); return }
            let address = surface.baseAddress
            surface.lock(options: [], seed: nil)
            if let context = CGContext(data: address, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: surface.bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) { context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height)) }
            surface.unlock(options: [], seed: nil)
            reply(createSnapshotXPC(surface: surface), nil)
        }
    }
    func provideSettingsViewModels(withContentTypes types: Any?, reply: @escaping (Any?, Error?) -> Void) { reply(settings(), nil) }
    func addChoiceRequest(withChoiceRequest request: Any?, onBehalfOfProcess process: Any?, reply: @escaping (Any?, Error?) -> Void) { reply(nil, nil) }
    func removeChoiceRequest(withChoiceRequest request: Any?, reply: @escaping (Error?) -> Void) { reply(nil) }
    func selectedChoicesDidChange(for id: Any?, reply: @escaping (Error?) -> Void) { reply(nil) }
    func invokeContextMenuAction(withMenuItemID id: Any?, groupItemID group: Any?, reply: @escaping (Error?) -> Void) { reply(nil) }
    func isChoiceDownloaded(with id: Any?, reply: @escaping (NSNumber?, Error?) -> Void) { reply(true, nil) }
    func download(withChoiceID id: Any?, reply: (Error?) -> Void) -> Any? { reply(nil); return nil }
    func pauseDownload(for id: Any?, reply: @escaping (Error?) -> Void) { reply(nil) }
    func cancelDownload(for id: Any?, reply: @escaping (Error?) -> Void) { reply(nil) }
    func resumeDownload(for id: Any?, reply: @escaping (Error?) -> Void) { reply(nil) }
    func removeDownload(for id: Any?, reply: @escaping (Error?) -> Void) { reply(nil) }
    func migrateSelectedChoice(for id: Any?, reply: @escaping (Any?, Error?) -> Void) { reply(nil, nil) }
    func migrate(from: Any?, to: Any?, reply: @escaping (Error?) -> Void) { reply(nil) }
    func skipShuffledContent(withId id: Any?, reply: @escaping (Error?) -> Void) { reply(nil) }
    func canSkipShuffledContent(withId id: Any?, reply: @escaping (Bool, Error?) -> Void) { reply(false, nil) }
    func handleDebugRequest(for request: Any?, reply: @escaping (Any?, Error?) -> Void) { reply(nil, nil) }
    func handleNotification(withNamed name: Any?, reply: @escaping (Error?) -> Void) { reply(nil) }
}
