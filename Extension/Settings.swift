import Foundation
func settings() -> AnyObject? {
    let provider = ChoiceProviderID(rawValue: "local.lockalbum.app.wallpaper")
    let thumbnail = frameDirectory.appendingPathComponent("current.png")
    let id = ChoiceID(id: "live", descriptor: ChoiceIDDescriptor(provider: provider, identifier: "live", files: [frameDirectory], configuration: Data("live".utf8)))
    let descriptor = ChoiceDescriptor(id: id, provider: provider, identifier: "live", name: "LockSleeve", localizedDescription: "Apple Music 앨범 배경", thumbnail: .image(url: thumbnail), isDownloaded: true, options: [])
    let item = SettingsItem(id: id, localizedName: "지금 재생 중", thumbnail: .image(url: thumbnail), choice: descriptor, contentBadge: .dynamic, showInTopLevel: true, sortOrder: 0, disposability: .none, contextMenu: nil)
    let group = SettingsGroup(id: GroupID(id: "lockalbum"), items: [item], localizedName: "LockSleeve", disposability: .none, sortOrder: 0, sortID: nil, allChoiceID: nil, shouldHideItemLabels: false, contextMenu: nil, thumbnail: nil)
    let model = SettingsViewModel(groups: [group], refreshPolicy: .default, isModificationDisabled: false)
    let shim = ShimViewModelsXPC(value: SettingsViewModels(desktop: model, screenSaver: model))
    guard let data = try? NSKeyedArchiver.archivedData(withRootObject: shim, requiringSecureCoding: false),
          let realClass = NSClassFromString("WallpaperSettingsViewModelsXPC"),
          let decoder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
    decoder.requiresSecureCoding = false; decoder.decodingFailurePolicy = .setErrorAndReturn
    decoder.setClass(realClass, forClassName: "ShimViewModelsXPC")
    let result = decoder.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
    decoder.finishDecoding()
    return result as AnyObject?
}
