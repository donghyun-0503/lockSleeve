import AppKit
import CoreImage
import ApplicationServices
import CryptoKit
import UniformTypeIdentifiers

struct SavedBackground: Codable {
    let url: URL
    let scaling: Int?
    let clipping: Bool?
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let workspace = NSWorkspace.shared
    let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LockAlbum", isDirectory: true)
    lazy var wallpaperStore = WallpaperStore(directory: folder)
    var backupURL: URL { folder.appendingPathComponent("originals.json") }
    var originals: [String: SavedBackground] = [:]
    var item: NSStatusItem!
    var window: NSWindow!
    var statusLabel: NSTextField!
    var syncButton: NSButton!
    var lyricsToggleButton: NSButton?
    var lyricsToggleMenuItem: NSMenuItem!
    var lyricsVisible = !UserDefaults.standard.bool(forKey: "lyricsHidden")
    var lastPresentation: (image: NSImage, title: String, artist: String, lyrics: SongLyrics?, index: Int)?
    func updateLyricsToggle() {
        lyricsToggleButton?.state = lyricsVisible ? .on : .off
        lyricsToggleButton?.toolTip = lyricsVisible ? "가사 숨기기" : "가사 표시하기"
        lyricsToggleButton?.setAccessibilityLabel(lyricsVisible ? "가사 숨기기" : "가사 표시하기")
        lyricsToggleMenuItem?.title = lyricsVisible ? "가사 숨기기" : "가사 표시하기"
        lyricsToggleMenuItem?.state = lyricsVisible ? .on : .off
    }
    @objc func toggleLyricsVisibility() {
        lyricsVisible.toggle()
        UserDefaults.standard.set(!lyricsVisible, forKey: "lyricsHidden")
        updateLyricsToggle()
        lastKey = ""
        if enabled, let presentation = lastPresentation {
            do {
                try apply(image: presentation.image, title: presentation.title, artist: presentation.artist, lyrics: presentation.lyrics, lyricIndex: presentation.index)
            } catch { status.title = "가사 표시 변경 실패: \(error.localizedDescription)" }
        }
        refresh()
    }
    var backgroundButton: NSButton!
    var backgroundMenuItem: NSMenuItem!
    var backgroundMode = UserDefaults.standard.bool(forKey: "backgroundMode")
    var status: NSMenuItem!
    var toggle: NSMenuItem!
    var timer: Timer?
    var enabled = false
    var busy = false
    var lastKey = ""
    var lastArtwork: Data?
    var currentTrackKey = ""
    var cachedBackgroundKey = ""
    var cachedBackground: Data?
    var currentLyrics: SongLyrics?
    let lyricsService = LyricsService()
    var remoteLyrics = ""
    var remoteLookupStarted = false
    var remoteLyricsStatus = ""
    var nextLyricsRetry = Date.distantPast
    var importedLyrics = ""
    var lastLyricsSource = ""
    var syncGeneration = UUID()
    var lyricsDirectory: URL { folder.appendingPathComponent("Lyrics", isDirectory: true) }
    func lyricsURL(for key: String) -> URL {
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return lyricsDirectory.appendingPathComponent(name + ".lrc")
    }
    @objc func importLyrics() {
        guard enabled, !currentTrackKey.isEmpty else { alert("먼저 동기화를 시작하고 곡을 재생하세요."); return }
        let key = currentTrackKey
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "lrc") ?? .plainText, .plainText]
        panel.allowsMultipleSelection = false
        panel.message = "현재 곡의 LRC 또는 텍스트 가사를 선택하세요. 시간 정보가 있으면 재생에 맞춰 강조합니다."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard enabled, currentTrackKey == key else { alert("곡이 바뀌었습니다. 현재 곡의 가사를 다시 선택하세요."); return }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 1_000_000, let text = String(data: data, encoding: .utf8), SongLyrics(text).available else {
                throw NSError(domain: "Lyrics", code: 1, userInfo: [NSLocalizedDescriptionKey: "UTF-8 형식의 가사 파일을 선택하세요 (최대 1MB)."])
            }
            try FileManager.default.createDirectory(at: lyricsDirectory, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: lyricsURL(for: key), options: .atomic)
            lyricsService.cancel()
            importedLyrics = text
            lastLyricsSource = ""
            lastKey = ""
            refresh()
        } catch { alert("가사 불러오기 실패: \(error.localizedDescription)") }
    }

    var framesDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers/local.lockalbum.app.wallpaper/Data/Library/Application Support/LockAlbum/Frames", isDirectory: true)
    }
    var locked = false
    func publishMode() {
        guard FileManager.default.fileExists(atPath: framesDirectory.path) else { return }
        if let data = try? JSONSerialization.data(withJSONObject: ["locked": locked]) {
            try? data.write(to: framesDirectory.appendingPathComponent("mode.json"), options: .atomic)
        }
    }
    @objc func didLock() { locked = true; publishMode() }
    @objc func didUnlock() { locked = false; publishMode() }
    func reconcileLock() {
        if let state = CGSessionCopyCurrentDictionary() as? [String: Any] {
            let actual = state["CGSSessionScreenIsLocked"] as? Bool ?? false
            if actual != locked { locked = actual; publishMode() }
        }
    }


    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: backupURL.path) {
                originals = try JSONDecoder().decode([String: SavedBackground].self, from: Data(contentsOf: backupURL))
            }
        } catch { alert("복원 정보 읽기 실패: \(error.localizedDescription)"); NSApp.terminate(nil); return }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "LockSleeve")
        let menu = NSMenu()
        status = NSMenuItem(title: "동기화 꺼짐", action: nil, keyEquivalent: "")
        add("LockSleeve 열기", #selector(showWindow), to: menu)
        backgroundMenuItem = NSMenuItem(title: backgroundMode ? "Dock에 표시" : "백그라운드 실행", action: #selector(toggleBackground), keyEquivalent: "")
        backgroundMenuItem.target = self
        menu.addItem(backgroundMenuItem)
        menu.addItem(status)
        toggle = NSMenuItem(title: "앨범 배경 동기화 시작", action: #selector(toggleSync), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        lyricsToggleMenuItem = NSMenuItem(title: "가사 숨기기", action: #selector(toggleLyricsVisibility), keyEquivalent: "")
        lyricsToggleMenuItem.target = self
        lyricsToggleMenuItem.image = NSImage(systemSymbolName: "quote.bubble.fill", accessibilityDescription: "가사")
        menu.addItem(lyricsToggleMenuItem)
        updateLyricsToggle()
        add("현재 곡 가사 파일 선택…", #selector(importLyrics), to: menu)
        add("미리보기", #selector(preview), to: menu)
        add("원래 배경 복원", #selector(restoreManually), to: menu)
        menu.addItem(.separator())
        add("사용 안내", #selector(help), to: menu)
        add("종료 및 배경 복원", #selector(quit), to: menu)
        item.menu = menu
        workspace.notificationCenter.addObserver(self, selector: #selector(refresh), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(displayChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        restore()
        reconcileLock()
        let center = DistributedNotificationCenter.default()
        center.addObserver(self, selector: #selector(didLock), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil, suspensionBehavior: .deliverImmediately)
        center.addObserver(self, selector: #selector(didUnlock), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, suspensionBehavior: .deliverImmediately)
        if !backgroundMode { showWindow() }
        if CommandLine.arguments.contains("--resume-sync") { toggleSync() }
    }
    @objc func showWindow() {
        if window == nil {
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 480), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "LockSleeve · Apple Music 앨범 배경"
            window.isReleasedWhenClosed = false
            window.center()
            let heading = NSTextField(labelWithString: "지금 듣는 음악을 배경으로")
            heading.font = .systemFont(ofSize: 24, weight: .bold)
            let description = NSTextField(wrappingLabelWithString: "Apple Music에서 노래를 재생한 뒤 동기화를 시작하세요.\n평소에는 원래 배경, 잠금화면에는 앨범 표지를 표시합니다.")
            statusLabel = NSTextField(labelWithString: "동기화 꺼짐")
            statusLabel.textColor = .secondaryLabelColor
            syncButton = NSButton(title: "앨범 배경 동기화 시작", target: self, action: #selector(toggleSync))
            syncButton.bezelStyle = .rounded
            let visibilityButton = NSButton(image: NSImage(systemSymbolName: "quote.bubble.fill", accessibilityDescription: "가사 표시 전환")!, target: self, action: #selector(toggleLyricsVisibility))
            visibilityButton.setButtonType(.pushOnPushOff)
            visibilityButton.bezelStyle = .circular
            visibilityButton.imageScaling = .scaleProportionallyDown
            visibilityButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 23, weight: .semibold)
            visibilityButton.translatesAutoresizingMaskIntoConstraints = false
            visibilityButton.widthAnchor.constraint(equalToConstant: 52).isActive = true
            visibilityButton.heightAnchor.constraint(equalToConstant: 52).isActive = true
            lyricsToggleButton = visibilityButton
            updateLyricsToggle()
            let visibilityHint = NSTextField(labelWithString: "가사 표시 · 버튼을 눌러 켜거나 끄세요")
            visibilityHint.textColor = .secondaryLabelColor
            let lyricsControls = NSStackView(views: [visibilityButton, visibilityHint])
            lyricsControls.spacing = 12
            let restoreButton = NSButton(title: "원래 배경 복원", target: self, action: #selector(restoreManually))
            let lyricsButton = NSButton(title: "현재 곡 가사 파일 선택…", target: self, action: #selector(importLyrics))
            let helpButton = NSButton(title: "사용 안내 및 제한", target: self, action: #selector(help))
            backgroundButton = NSButton(title: backgroundMode ? "Dock에 표시" : "백그라운드 실행", target: self, action: #selector(toggleBackground))
            backgroundButton.bezelStyle = .rounded
            let backgroundHint = NSTextField(labelWithString: "Dock에서 숨겨도 동기화는 계속됩니다. 메뉴바 음표로 다시 열 수 있어요.")
            backgroundHint.font = .systemFont(ofSize: 11)
            backgroundHint.textColor = .secondaryLabelColor
            let stack = NSStackView(views: [heading, description, statusLabel, syncButton, lyricsControls, restoreButton, backgroundButton, backgroundHint, lyricsButton, helpButton])
            stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
            stack.translatesAutoresizingMaskIntoConstraints = false
            window.contentView!.addSubview(stack)
            NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 28), stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -28), stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 28)])
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.statusLabel.stringValue = self.status.title
                self.syncButton.title = self.toggle.title
            }
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func toggleBackground() {
        let next = !backgroundMode
        guard NSApp.setActivationPolicy(next ? .accessory : .regular) else { return }
        backgroundMode = next
        UserDefaults.standard.set(next, forKey: "backgroundMode")
        let title = next ? "Dock에 표시" : "백그라운드 실행"
        backgroundButton?.title = title
        backgroundMenuItem.title = title
        if next { window?.orderOut(nil) } else { showWindow() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(); return true
    }
    func add(_ title: String, _ action: Selector, to menu: NSMenu) {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self; menu.addItem(entry)
    }
    func alert(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = "LockSleeve"; a.informativeText = message; a.runModal()
    }
    @objc func help() {
        alert("동기화 시작 시 원래 배경 이미지를 저장합니다. 평소에는 이 배경을 표시하고 잠기면 앨범 표지로 전환합니다. 잠금 해제하면 원래 배경 이미지로 돌아갑니다.\n\n전환은 확장 내부에서 이루어져 WallpaperAgent를 재시작하지 않습니다. 최초 활성화와 동기화 종료 때만 시스템 배경 제공자를 전환합니다. 현재는 정적인 배경 이미지에 대응하며 동영상·자동 순환 배경은 지원하지 않습니다.")
    }
    @objc func toggleSync() {
        enabled.toggle()
        lyricsService.cancel()
        syncGeneration = UUID()
        toggle.title = enabled ? "동기화 중지 및 배경 복원" : "앨범 배경 동기화 시작"
        if enabled {
            do { try prepareDesktop() } catch {
                enabled = false; toggle.title = "앨범 배경 동기화 시작"
                status.title = "원래 배경 준비 실패: \(error.localizedDescription)"; return
            }
            lastKey = ""
            timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
            refresh()
        } else { timer?.invalidate(); timer = nil; restore(); status.title = "동기화 꺼짐" }
    }
    @objc func displayChanged() { lastKey = ""; refresh() }
    @objc func preview() {
        let url = folder.appendingPathComponent("preview.png")
        if FileManager.default.fileExists(atPath: url.path) { workspace.open(url) }
        else { alert("동기화를 시작하고 Apple Music에서 노래를 재생하면 미리보기가 생성됩니다.") }
    }
    @objc func restoreManually() {
        if enabled { toggleSync() } else { restore() }
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        enabled = false; timer?.invalidate(); restore()
        return originals.isEmpty && !FileManager.default.fileExists(atPath: wallpaperStore.backupURL.path) ? .terminateNow : .terminateCancel
    }
    func screenID(_ screen: NSScreen) -> String {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        if let number, let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return screen.localizedName
    }
    func persist() throws { try JSONEncoder().encode(originals).write(to: backupURL, options: .atomic) }
    func restore() {
        do { try wallpaperStore.restore() } catch {
            status?.title = "잠금화면 복원 실패: \(error.localizedDescription)"
            return
        }
        for screen in NSScreen.screens {
            let id = screenID(screen)
            guard let original = originals[id] else { continue }
            do {
                // Do not overwrite a wallpaper the user selected while we were running.
                if let current = workspace.desktopImageURL(for: screen), current.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL {
                    var options: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
                    if let scaling = original.scaling { options[.imageScaling] = scaling }
                    if let clipping = original.clipping { options[.allowClipping] = clipping }
                    try workspace.setDesktopImageURL(original.url, for: screen, options: options)
                }
                originals.removeValue(forKey: id)
            } catch { status?.title = "배경 복원 실패: \(error.localizedDescription)" }
        }
        do { try persist() } catch { alert("복원 정보 저장 실패: \(error.localizedDescription)") }
        lastKey = ""
        lyricsService.cancel()
        remoteLyrics = ""
        remoteLookupStarted = false
        remoteLyricsStatus = ""
        nextLyricsRetry = .distantPast
        currentTrackKey = ""
        currentLyrics = nil
        lastPresentation = nil
        lastLyricsSource = ""
    }
    @objc func refresh() {
        guard enabled else { return }
        reconcileLock()
        guard !busy else { return }
        guard workspace.runningApplications.contains(where: { $0.bundleIdentifier == "com.apple.Music" }) else {
            restore(); status.title = "Apple Music 실행 대기 중"; return
        }
        busy = true
        let generation = syncGeneration
        // Apple events run off the main thread so the menu remains responsive.
        DispatchQueue.global(qos: .utility).async {
            let source = """
            with timeout of 5 seconds
                tell application "Music"
                    if player state is not playing then return {"idle"}
                    set t to current track
                    set coverData to ""
                    try
                        set coverData to raw data of artwork 1 of t
                    end try
                    set lyricText to ""
                    try
                        set lyricText to lyrics of t
                    end try
                    return {"playing", name of t, artist of t, album of t, coverData, player position, lyricText, duration of t}
                end tell
            end timeout
            """
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            let errorMessage = error?[NSAppleScript.errorMessage] as? String
            let state = result?.atIndex(1)?.stringValue
            let title = result?.atIndex(2)?.stringValue ?? "제목 없음"
            let artist = result?.atIndex(3)?.stringValue ?? ""
            let album = result?.atIndex(4)?.stringValue ?? ""
            let data = result?.atIndex(5)?.data
            let position = result?.atIndex(6)?.doubleValue ?? 0
            let lyricText = result?.atIndex(7)?.stringValue ?? ""
            let duration = result?.atIndex(8)?.doubleValue ?? 0
            DispatchQueue.main.async {
                self.busy = false
                guard self.enabled, self.syncGeneration == generation else { return }
                if let errorMessage {
                    self.status.title = "Music 연결 실패 · 자동화 권한 확인"
                    self.item.button?.toolTip = errorMessage
                    return
                }
                guard state == "playing" else { self.restore(); self.status.title = "재생 대기 중"; return }
                self.status.title = "\(title) — \(artist)"
                guard let data, let image = NSImage(data: data) else {
                    self.restore(); self.status.title = "앨범 표지가 없는 곡"; return
                }
                let key = title + "\u{0}" + artist + "\u{0}" + album
                if self.currentTrackKey != key {
                    self.lyricsService.cancel()
                    self.remoteLyrics = ""
                    self.remoteLookupStarted = false
                    self.remoteLyricsStatus = ""
                    self.nextLyricsRetry = .distantPast
                    self.currentTrackKey = key
                    self.importedLyrics = (try? String(contentsOf: self.lyricsURL(for: key), encoding: .utf8)) ?? ""
                    self.lastLyricsSource = ""
                    self.currentLyrics = nil
                }
                if self.remoteLookupStarted, self.remoteLyrics.isEmpty, Date() >= self.nextLyricsRetry {
                    self.remoteLookupStarted = false
                }
                if self.importedLyrics.isEmpty, !self.remoteLookupStarted, SongLyrics(lyricText).lines.isEmpty {
                    self.remoteLookupStarted = true
                    self.remoteLyricsStatus = "가사 찾는 중…"
                    self.nextLyricsRetry = .distantFuture
                    self.lyricsService.fetch(key: key, title: title, artist: artist, album: album, duration: duration) { [weak self = self] source in
                        guard let self, self.enabled, self.syncGeneration == generation, self.currentTrackKey == key else { return }
                        self.remoteLyrics = source ?? ""
                        self.remoteLyricsStatus = self.lyricsService.status
                        self.nextLyricsRetry = Date().addingTimeInterval(65)
                        self.refresh()
                    }
                }
                let remote = SongLyrics(self.remoteLyrics)
                let music = SongLyrics(lyricText)
                let source: String
                if !self.importedLyrics.isEmpty { source = self.importedLyrics }
                else if !music.lines.isEmpty { source = lyricText }
                else if !remote.lines.isEmpty { source = self.remoteLyrics }
                else if music.available { source = lyricText }
                else { source = self.remoteLyrics }
                if source != self.lastLyricsSource {
                    self.currentLyrics = SongLyrics(source)
                    self.lastLyricsSource = source
                    self.lastKey = ""
                }
                let lyricsMessage = self.currentLyrics?.available == true
                    ? (self.currentLyrics!.lines.isEmpty ? "일반 가사 · 시간 정보 없음" : "동기화 가사")
                    : self.remoteLyricsStatus
                self.status.title = "\(title) — \(artist)" + (lyricsMessage.isEmpty ? "" : " · " + lyricsMessage)
                let lyricIndex = self.currentLyrics?.activeIndex(at: position) ?? -1
                let renderKey = key + "\u{0}" + String(lyricIndex)
                guard renderKey != self.lastKey || data != self.lastArtwork || !self.wallpaperStore.extensionIsSelected() else { return }
                if data != self.lastArtwork { self.cachedBackgroundKey = "" }
                do {
                    try self.apply(image: image, title: title, artist: artist, lyrics: self.currentLyrics, lyricIndex: lyricIndex)
                    self.lastKey = renderKey; self.lastArtwork = data
                } catch { self.status.title = "배경 변경 실패: \(error.localizedDescription)"; self.item.button?.toolTip = error.localizedDescription }
            }
        }
    }
    func prepareDesktop() throws {
        let original = try wallpaperStore.originalImageURL()
        guard let image = NSImage(contentsOf: original), let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "LockAlbum", code: 30, userInfo: [NSLocalizedDescriptionKey: "원래 배경을 이미지로 읽을 수 없습니다."])
        }
        try FileManager.default.createDirectory(at: framesDirectory, withIntermediateDirectories: true)
        try png.write(to: framesDirectory.appendingPathComponent("desktop.png"), options: .atomic)
        reconcileLock(); publishMode()
    }
    func apply(image: NSImage, title: String, artist: String, lyrics: SongLyrics?, lyricIndex: Int) throws {
        lastPresentation = (image, title, artist, lyrics, lyricIndex)
        let shownLyrics = lyricsVisible ? lyrics : nil
        guard let screen = NSScreen.main else { return }
        let width = min(screen.frame.width * screen.backingScaleFactor, 3840)
        let size = NSSize(width: width, height: width * screen.frame.height / screen.frame.width)
        let backgroundKey = currentTrackKey + "|\(size.width)x\(size.height)|\(shownLyrics?.available == true)"
        let frames = framesDirectory
        try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        if cachedBackgroundKey != backgroundKey || cachedBackground == nil {
            let background = try render(image: image, title: title, artist: artist, size: size, lyrics: shownLyrics, lyricIndex: lyricIndex, drawLyricText: false)
            try background.write(to: frames.appendingPathComponent("current.png"), options: .atomic)
            cachedBackground = background
            cachedBackgroundKey = backgroundKey
        }
        let state = LyricsFrame(trackID: currentTrackKey, texts: shownLyrics.map { $0.lines.isEmpty ? $0.plain : $0.lines.map(\.text) } ?? [], activeIndex: lyricIndex, synced: shownLyrics?.lines.isEmpty == false)
        try JSONEncoder().encode(state).write(to: frames.appendingPathComponent("lyrics.json"), options: .atomic)
        let preview = try render(image: image, title: title, artist: artist, size: size, lyrics: shownLyrics, lyricIndex: lyricIndex)
        try preview.write(to: folder.appendingPathComponent("preview.png"), options: .atomic)
        // A user may have changed wallpaper since sync started, even on the same song.
        if !wallpaperStore.extensionIsSelected() { try prepareDesktop() }
        try wallpaperStore.applyExtension(framesDirectory: frames)

    }
}

func render(image: NSImage, title: String, artist: String, size: NSSize, lyrics: SongLyrics? = nil, lyricIndex: Int = -1, drawLyricText: Bool = true) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { throw NSError(domain: "Render", code: 1) }
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
    defer { NSGraphicsContext.restoreGraphicsState() }
    let bounds = NSRect(origin: .zero, size: size)
    NSColor.black.setFill(); bounds.fill()
    if let tiff = image.tiffRepresentation, let ci = CIImage(data: tiff) {
        let scale = max(size.width / ci.extent.width, size.height / ci.extent.height)
        let scaled = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let positioned = scaled.transformed(by: CGAffineTransform(translationX: (size.width - scaled.extent.width) / 2, y: (size.height - scaled.extent.height) / 2))
        let blurred = positioned.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: size.width * 0.085]).cropped(to: bounds)
        // Broad album-color washes, closer to Music's lyrics background.
        let luminous = blurred.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 2.3, kCIInputBrightnessKey: 0.055, kCIInputContrastKey: 0.92])
        if let cg = CIContext().createCGImage(luminous, from: bounds) { NSImage(cgImage: cg, size: size).draw(in: bounds) }
    }
    NSColor.black.withAlphaComponent(0.20).setFill(); bounds.fill()
    let hasLyrics = lyrics?.available == true
    let edge = min(size.width * (hasLyrics ? 0.28 : 0.35), size.height * 0.44)
    let cover = NSRect(x: hasLyrics ? size.width * 0.12 : (size.width-edge)/2, y: size.height * 0.30, width: edge, height: edge)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.28); shadow.shadowBlurRadius = edge * 0.1; shadow.shadowOffset = NSSize(width: 0, height: -12); shadow.set()
    NSColor.black.setFill(); NSBezierPath(roundedRect: cover, xRadius: edge * 0.035, yRadius: edge * 0.035).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: cover, xRadius: edge * 0.035, yRadius: edge * 0.035).addClip()
    let ratio = max(edge / image.size.width, edge / image.size.height)
    image.draw(in: NSRect(x: cover.midX-image.size.width*ratio/2, y: cover.midY-image.size.height*ratio/2, width: image.size.width*ratio, height: image.size.height*ratio))
    NSGraphicsContext.restoreGraphicsState()
    let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
    let textShadow = NSShadow(); textShadow.shadowColor = NSColor.black.withAlphaComponent(0.35); textShadow.shadowBlurRadius = 8; textShadow.shadowOffset = NSSize(width: 0, height: -1)
    let font = size.height * 0.028
    (title as NSString).draw(in: NSRect(x: hasLyrics ? cover.minX : size.width*0.12, y: cover.minY-font*2.0, width: hasLyrics ? edge : size.width*0.76, height: font*1.5), withAttributes: [.font: NSFont.systemFont(ofSize: font, weight: .semibold), .foregroundColor: NSColor.white, .paragraphStyle: paragraph, .shadow: textShadow])
    (artist as NSString).draw(in: NSRect(x: hasLyrics ? cover.minX : size.width*0.12, y: cover.minY-font*3.5, width: hasLyrics ? edge : size.width*0.76, height: font*1.4), withAttributes: [.font: NSFont.systemFont(ofSize: font*0.75), .foregroundColor: NSColor.white.withAlphaComponent(0.75), .paragraphStyle: paragraph, .shadow: textShadow])
    if let lyrics, hasLyrics, drawLyricText { drawLyrics(lyrics, activeIndex: lyricIndex, size: size) }
    guard let data = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "Render", code: 2) }
    return data
}

func drawLyrics(_ lyrics: SongLyrics, activeIndex: Int, size: NSSize) {
    let state = LyricsFrame(trackID: "preview", texts: lyrics.lines.isEmpty ? lyrics.plain : lyrics.lines.map(\.text), activeIndex: activeIndex, synced: !lyrics.lines.isEmpty)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: LyricsLayout.area(size)).addClip()
    defer { NSGraphicsContext.restoreGraphicsState() }
    for placement in LyricsLayout.placements(state, size: size) {
        var attributes = LyricsLayout.attributes(size)
        attributes[.foregroundColor] = NSColor.white.withAlphaComponent(CGFloat(placement.opacity))
        (LyricsLayout.text(state, at: placement.index) as NSString).draw(in: placement.rect, withAttributes: attributes)
    }
}

if CommandLine.arguments.contains("--render-test") {
    let image = NSImage(size: NSSize(width: 500, height: 500))
    image.lockFocus(); NSColor.systemIndigo.setFill(); NSRect(x: 0, y: 0, width: 500, height: 500).fill(); NSColor.systemPink.setFill(); NSBezierPath(ovalIn: NSRect(x: 100, y: 100, width: 300, height: 300)).fill(); image.unlockFocus()
    let output = CommandLine.arguments.last!
    let sample = CommandLine.arguments.contains("--lyrics") ? SongLyrics("[00:00.00]오늘의 음악이 흐르면\n[00:05.00]이 순간을 기억해\n[00:10.00]하얀 빛으로 번지는 밤\n[00:15.00]조용히 눈을 감아") : nil
    try render(image: image, title: "Midnight Memories", artist: "LockSleeve · 렌더링 테스트", size: NSSize(width: 1920, height: 1080), lyrics: sample, lyricIndex: 1).write(to: URL(fileURLWithPath: output))
} else {
    let app = NSApplication.shared
    let menu = NSMenu()
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "LockSleeve 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    let rootItem = NSMenuItem(); rootItem.submenu = appMenu; menu.addItem(rootItem)
    app.mainMenu = menu
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(UserDefaults.standard.bool(forKey: "backgroundMode") ? .accessory : .regular)
    withExtendedLifetime(delegate) { app.run() }
}
