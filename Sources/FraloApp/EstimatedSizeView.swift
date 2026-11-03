import AppKit
import FraloDesignSystem
import FraloLocalization

/// The estimate keeps one value slot while encoding replaces its text with activity.
@MainActor
final class EstimatedSizeView: NSView {
    let label = FraloStyle.text("—", role: .body)
    let indicator = ArcActivityIndicator(label: L10n.tr("正在估算…"))
    var preferences = DesignPreferences() { didSet { refresh() } }
    private(set) var isEstimating = false
    private var observer: NSObjectProtocol?

    override var intrinsicContentSize: NSSize {
        NSSize(width: max(128, label.intrinsicContentSize.width), height: max(16, label.intrinsicContentSize.height))
    }
    init() {
        super.init(frame: .zero)
        label.font = .monospacedDigitSystemFont(ofSize: 12.5, weight: .regular)
        label.alignment = .right; label.setAccessibilityLabel(L10n.tr("预计大小"))
        for view in [label, indicator] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor), label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            indicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            indicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            indicator.widthAnchor.constraint(equalToConstant: 14), indicator.heightAnchor.constraint(equalToConstant: 14)
        ])
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit { if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) } }

    func show(_ count: Int?, busy: Bool = false) {
        isEstimating = count == nil && busy
        label.stringValue = count.map { L10n.tr("\(ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)) / 张") }
            ?? (isEstimating ? L10n.tr("正在估算…") : "—")
        invalidateIntrinsicContentSize(); refresh()
    }
    private func refresh() {
        let rotating = isEstimating && !preferences.effectiveReduceMotion
        label.isHidden = rotating; indicator.isHidden = !rotating
        indicator.increaseContrast = preferences.effectiveIncreaseContrast
        indicator.isRunning = rotating
    }
}
