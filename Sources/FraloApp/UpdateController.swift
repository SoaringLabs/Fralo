import FraloLocalization
import AppKit
import Sparkle

/// Keeps Sparkle's relaunch callback alive without cancelling an active export.
@MainActor
final class UpdateInstallationGate {
    private var install: (() -> Void)?
    var isWaiting: Bool { install != nil }

    func postpone(whileBusy: Bool, install: @escaping () -> Void) -> Bool {
        guard whileBusy else { return false }
        self.install = install
        return true
    }

    @discardableResult
    func resumeIfIdle(whileBusy: Bool) -> Bool {
        guard !whileBusy, let pending = install else { return false }
        install = nil
        pending()
        return true
    }

    func cancel() { install = nil }
}

@MainActor
final class UpdateController: NSObject, SPUUpdaterDelegate, NSMenuItemValidation, UpdatePreferences {
    private var controller: SPUStandardUpdaterController!
    private weak var mainController: MainWindowController?
    private let installation = UpdateInstallationGate()
    private enum Unavailable { case notBundled, failed(String) }
    private var unavailable: Unavailable?
    /// Formatted on each read so it follows a language change made in Settings.
    var unavailableReason: String? {
        switch unavailable {
        case .notBundled?: return L10n.tr("请打开完整的 Fralo.app 后检查更新。直接运行构建目录中的可执行文件不支持安装更新。")
        case .failed(let detail)?: return L10n.tr("更新服务未能启动：\(detail)")
        case nil: return nil
        }
    }
    private var sheetObserver: NSObjectProtocol?
    private var isBusy: Bool {
        mainController?.isExporting == true || mainController?.window?.attachedSheet != nil
    }

    init(mainController: MainWindowController) {
        self.mainController = mainController
        super.init()
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            unavailable = .notBundled
            return
        }
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        do { try controller.updater.start() }
        catch { unavailable = .failed(error.localizedDescription) }
        bind(to: mainController)
    }

    /// Also called when a language change replaces the workbench window.
    func bind(to mainController: MainWindowController) {
        self.mainController = mainController
        guard controller != nil else { return }
        mainController.onExportFinished = { [weak self] in
            guard let self else { return false }
            let pending = self.installation.isWaiting
            self.installation.resumeIfIdle(whileBusy: self.isBusy)
            return pending
        }
        if let sheetObserver { NotificationCenter.default.removeObserver(sheetObserver) }
        // AppKit can reject termination before asking the app delegate when a sheet is open.
        sheetObserver = NotificationCenter.default.addObserver(forName: NSWindow.didEndSheetNotification,
                                                               object: mainController.window, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.installation.resumeIfIdle(whileBusy: self.isBusy)
            }
        }
    }

    deinit { if let sheetObserver { NotificationCenter.default.removeObserver(sheetObserver) } }

    @objc func checkForUpdates(_ sender: Any?) {
        if let reason = unavailableReason {
            let alert = NSAlert()
            alert.messageText = L10n.tr("暂时无法检查更新")
            alert.informativeText = reason
            alert.addButton(withTitle: L10n.tr("好"))
            alert.runModal()
            return
        }
        guard controller.updater.canCheckForUpdates else { return }
        controller.checkForUpdates(sender)
    }

    /// Sparkle persists this preference itself; Settings is its only editing surface.
    var automaticallyChecksForUpdates: Bool {
        get { unavailableReason == nil && controller.updater.automaticallyChecksForUpdates }
        set { if unavailableReason == nil { controller.updater.automaticallyChecksForUpdates = newValue } }
    }
    var lastUpdateCheckDate: Date? { unavailableReason == nil ? controller.updater.lastUpdateCheckDate : nil }
    var canCheckForUpdates: Bool { unavailableReason == nil && controller.updater.canCheckForUpdates }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdates(_:)) {
            return unavailableReason != nil || controller.updater.canCheckForUpdates
        }
        return true
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        let postponed = installation.postpone(whileBusy: isBusy, install: installHandler)
        if postponed { mainController?.showPendingUpdate() }
        return postponed
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        installation.cancel()
        mainController?.clearPendingUpdate()
    }
}
