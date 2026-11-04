#if FRALO_DEV
import AppKit
import FraloDesignSystem

struct ExportLabState {
    var ending = 0
    var count = 1
    var background = 0
}

/// FRALO-45: the production `ExportCapsule` on a miniature stage, fed fictional runs.
/// Nothing is written to disk; Finder and Dock calls report or show only.
@MainActor
final class ExportLab: NSView {
    let state: DesignLabState
    private let status = FraloStyle.text("模拟不会写入任何文件", role: .caption, secondary: true)
    private let stage = LabExportStage()
    private var timer: Timer?
    override var isFlipped: Bool { true }

    init(state: DesignLabState) {
        self.state = state
        super.init(frame: NSRect(x: 0, y: 0, width: 1100, height: 650))
        let controls = FraloStyle.stack([
            ChoiceMenu(["全部成功", "部分失败", "中途取消"], label: "模拟结局", selected: state.export.ending) { [weak self] in self?.state.export.ending = $0 },
            ChoiceMenu(["1 张", "8 张", "24 张"], label: "张数", selected: state.export.count) { [weak self] in self?.state.export.count = $0 },
            ChoiceMenu(["暖灰背景", "雾蓝背景", "鼠尾草背景", "透明"], label: "构图背景", selected: state.export.background) { [weak self] in
                self?.state.export.background = $0; self?.refreshStage()
            },
            ActionButton("模拟导出", role: .primary, symbol: "play.fill") { [weak self] in self?.play() },
            NSView(), status
        ], axis: .horizontal, spacing: 12)
        for view in [controls, stage] as [NSView] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            controls.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            controls.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16), controls.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stage.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 12),
            stage.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16), stage.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stage.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
        stage.capsule.preferences = state.preferences; stage.toolbar.preferences = state.preferences
        stage.capsule.onReveal = { [weak self] in self?.status.stringValue = "在 Finder 中显示（模拟）" }
        stage.capsule.onCancel = { [weak self] in self?.stopRequested = true }
        refreshStage()
        playIfRequested()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    private var stopRequested = false
    private let shimmer = PreviewShimmer()
    private var backdrop: NSImage? {
        let images = state.samples.backgrounds
        return state.export.background < images.count ? images[state.export.background] : nil
    }
    private func refreshStage() {
        stage.composition.image = backdrop
        stage.device.image = state.samples.phone(at: 0)
    }

    private func play() {
        timer?.invalidate()
        let total = [1, 8, 24][state.export.count], ending = state.export.ending
        let failures: [Int: Bool] = ending == 1 ? [min(1, total - 1): false, total - 1: true] : [:]
        let stopAt = ending == 2 ? max(1, total / 2) : total
        var completed = 0
        stopRequested = false
        stage.toolbar.alphaValue = 0
        stage.capsule.onReturn = { [weak self] in self?.stage.toolbar.animator().alphaValue = 1 }
        // Like production, the simulated work starts once the capsule has grown.
        stage.capsule.begin(total: total, thumbnail: state.samples.phone(at: 0)) { [weak self] in
            guard let self else { return }
            self.shimmer.start(on: self.stage.canvas, preferences: self.state.preferences)
            self.timer = Timer.scheduledTimer(withTimeInterval: total > 10 ? 0.25 : 0.8, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if completed >= stopAt || self.stopRequested {
                    self.timer?.invalidate(); self.timer = nil; DockProgress.shared.clear(); self.shimmer.stop()
                    let failed = failures.filter { $0.key < completed && $0.value }.count
                    let skipped = failures.filter { $0.key < completed && !$0.value }.count
                    let issues = failures.sorted { $0.key < $1.key }.filter { $0.key < completed }.map {
                        ExportOutcome.Issue(name: String(format: "fralo-%02d-sample-2026-11-04-00-30-00.png", $0.key + 1),
                                            reason: $0.value ? "无法读取图片：文件已损坏或格式不受支持" : "已有同名文件", failed: $0.value)
                    }
                    let outcome = ExportOutcome(total: total, succeeded: completed - failed - skipped, skipped: skipped, failed: failed,
                                                cancelled: ending == 2 || self.stopRequested, issues: issues)
                    self.stage.capsule.finish(outcome, folderName: "Fralo 2026-11-04 00-30-00")
                    return
                }
                completed += 1
                self.stage.capsule.update(completed: completed)
                DockProgress.shared.show(Double(completed) / Double(total))
                self.stage.device.image = self.state.samples.phone(at: completed); self.stage.needsLayout = true; self.stage.layoutSubtreeIfNeeded()
            }
        }
        }
    }

    /// `--export-lab-play=ending` starts a run; `--export-lab-snapshot=/prefix` captures mid-run and the result.
    private func playIfRequested() {
        guard let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--export-lab-play=") }) else { return }
        state.export.ending = Int(argument.dropFirst("--export-lab-play=".count)) ?? 0
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Export lab replay")
        let prefix = CommandLine.arguments.first(where: { $0.hasPrefix("--export-lab-snapshot=") }).map { String($0.dropFirst("--export-lab-snapshot=".count)) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.play()
            guard let prefix else { return }
            for (delay, label) in [(0.12, "grow1"), (0.24, "grow2"), (0.36, "grow3"), (2.0, "mid0"), (2.13, "mid1"), (2.26, "mid2"), (3.0, "mid"), (8.6, "end")] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.capture("\(prefix)-\(label).png") }
            }
            // The completion moment, sampled densely since its highlight lasts well under a second.
            for step in 0..<14 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 6.7 + Double(step) * 0.1) { [weak self] in self?.capture("\(prefix)-done\(step).png") }
            }
            // Then the collapse back into the toolbar, sampled while it runs.
            DispatchQueue.main.asyncAfter(deadline: .now() + 9.2) { [weak self] in
                self?.stage.capsule.hide(animated: true)
                for (index, delay) in [0.05, 0.12, 0.2, 0.28, 0.36, 0.5].enumerated() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.capture("\(prefix)-collapse\(index).png") }
                }
            }
        }
    }
    private var activity: NSObjectProtocol?
    private func capture(_ path: String) {
        guard let number = window?.windowNumber else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", String(number), path]
        // Never wait here: blocking the main thread would freeze the very animation being captured.
        process.terminationHandler = { _ in FileHandle.standardError.write(Data("export-lab snapshot \(path)\n".utf8)) }
        try? process.run()
    }
}

/// A stand-in for the workbench centre: canvas artwork, the viewing toolbar and the capsule above.
@MainActor
private final class LabExportStage: NSView {
    let composition = NSImageView()
    let device = NSImageView()
    let canvas = CanvasSurface(frame: .zero)
    let toolbar = ViewToolbar()
    let capsule = ExportCapsule(frame: .zero)
    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true; layer?.cornerRadius = 12; layer?.masksToBounds = true
        composition.imageScaling = .scaleAxesIndependently
        device.imageScaling = .scaleProportionallyUpOrDown
        for view in [composition, device] { view.unregisterDraggedTypes(); view.wantsLayer = true; addSubview(view) }
        // The canvas only carries the preview shimmer here; the image views draw the artwork.
        canvas.showsTransparencyGrid = false
        for view in [canvas, toolbar, capsule] as [NSView] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            toolbar.centerXAnchor.constraint(equalTo: centerXAnchor), toolbar.centerYAnchor.constraint(equalTo: bottomAnchor, constant: -WorkbenchView.viewingControlsHeight / 2),
            toolbar.heightAnchor.constraint(equalToConstant: ViewToolbar.height),
            capsule.leadingAnchor.constraint(equalTo: leadingAnchor), capsule.trailingAnchor.constraint(equalTo: trailingAnchor),
            capsule.topAnchor.constraint(equalTo: topAnchor), capsule.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        capsule.anchor = { [weak self] in
            guard let self else { return .zero }
            return self.capsule.convert(self.toolbar.bounds, from: self.toolbar)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = NSColor.underPageBackgroundColor.cgColor }
    }
    override func layout() {
        super.layout()
        let height = bounds.height - 120, width = min(bounds.width - 80, height * 0.8)
        let art = NSRect(x: (bounds.width - width) / 2, y: 30, width: width, height: height)
        composition.frame = art
        device.frame = art.insetBy(dx: width * 0.12, dy: height * 0.07)
        canvas.frame = device.frame
        canvas.image = device.image
    }
}
#endif
