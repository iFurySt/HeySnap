import AppKit
import SwiftUI

enum MainWindowMetrics {
    static let collapsedMinWidth: CGFloat = 520
    static let expandedSidebarMinWidth: CGFloat = 684
    static let minHeight: CGFloat = 460
}

private enum PreferencesPage: String, CaseIterable, Identifiable {
    case general = "General"
    case hotKeys = "HotKeys"
    case about = "About"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .hotKeys: return "keyboard"
        case .about: return "info.circle"
        }
    }
}

struct PreferencesRootView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var hotKeyService: HotKeyService
    @ObservedObject var screenshotService: ScreenshotService
    @State private var selectedPage: PreferencesPage? = .general
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedPage: $selectedPage)
                .frame(
                    minWidth: Metrics.sidebarWidth,
                    idealWidth: Metrics.sidebarWidth,
                    maxWidth: Metrics.sidebarWidth,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                .navigationSplitViewColumnWidth(
                    min: Metrics.sidebarWidth,
                    ideal: Metrics.sidebarWidth,
                    max: Metrics.sidebarWidth
                )
        } detail: {
            NavigationStack {
                detailView
            }
        }
        .tint(Palette.accent)
        .onChange(of: columnVisibility) { _, newVisibility in
            expandMainWindowIfNeededForVisibleSidebar(newVisibility)
        }
        .background {
            MainWindowSizingConfigurator(columnVisibility: $columnVisibility)
                .frame(width: 0, height: 0)
        }
    }

    private func expandMainWindowIfNeededForVisibleSidebar(_ visibility: NavigationSplitViewVisibility) {
        guard Self.sidebarIsVisible(for: visibility) else { return }
        DispatchQueue.main.async {
            let window = NSApplication.shared.keyWindow
                ?? NSApplication.shared.windows.first { $0.isVisible && $0.styleMask.contains(.titled) }
            guard let window else { return }

            let frame = window.frame
            let targetWidth = max(frame.width, MainWindowMetrics.expandedSidebarMinWidth)
            let targetHeight = max(frame.height, MainWindowMetrics.minHeight)
            guard targetWidth != frame.width || targetHeight != frame.height else { return }

            window.setFrame(
                NSRect(
                    x: frame.minX,
                    y: frame.maxY - targetHeight,
                    width: targetWidth,
                    height: targetHeight
                ),
                display: true
            )
        }
    }

    private static func sidebarIsVisible(for columnVisibility: NavigationSplitViewVisibility) -> Bool {
        switch columnVisibility {
        case .detailOnly:
            return false
        case .all, .doubleColumn, .automatic:
            return true
        default:
            return true
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedPage ?? .general {
        case .general:
            GeneralSettingsView(settings: settings, screenshotService: screenshotService)
                .navigationTitle("General")
        case .hotKeys:
            HotKeysSettingsView(settings: settings, hotKeyService: hotKeyService)
                .navigationTitle("HotKeys")
        case .about:
            AboutSettingsView()
                .navigationTitle("About")
        }
    }
}

private struct MainWindowSizingConfigurator: NSViewRepresentable {
    @Binding var columnVisibility: NavigationSplitViewVisibility

    func makeNSView(context: Context) -> NSView {
        MainWindowSizingView(columnVisibility: $columnVisibility)
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let sizingView = view as? MainWindowSizingView else { return }
        sizingView.columnVisibility = $columnVisibility
        sizingView.applyWindowSizing()
    }
}

private final class MainWindowSizingView: NSView {
    var columnVisibility: Binding<NavigationSplitViewVisibility>
    private var resizeObserver: NSObjectProtocol?

    init(columnVisibility: Binding<NavigationSplitViewVisibility>) {
        self.columnVisibility = columnVisibility
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyWindowSizing()
    }

    func applyWindowSizing() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            Self.applyMinimumSize(to: window)
            Self.expandWindowIfNeededForVisibleSidebar(
                in: window,
                columnVisibility: self.columnVisibility.wrappedValue
            )
            self.installResizeObserverIfNeeded(for: window)
        }
    }

    private static func applyMinimumSize(to window: NSWindow) {
        let minimumSize = NSSize(
            width: MainWindowMetrics.collapsedMinWidth,
            height: MainWindowMetrics.minHeight
        )
        window.minSize = minimumSize
        window.contentMinSize = minimumSize

        let frame = window.frame
        let targetWidth = max(frame.width, minimumSize.width)
        let targetHeight = max(frame.height, minimumSize.height)
        guard targetWidth != frame.width || targetHeight != frame.height else { return }

        window.setFrame(
            NSRect(
                x: frame.minX,
                y: frame.maxY - targetHeight,
                width: targetWidth,
                height: targetHeight
            ),
            display: true
        )
    }

    private static func expandWindowIfNeededForVisibleSidebar(
        in window: NSWindow,
        columnVisibility: NavigationSplitViewVisibility
    ) {
        guard sidebarIsVisible(for: columnVisibility) else { return }
        let frame = window.frame
        let targetWidth = max(frame.width, MainWindowMetrics.expandedSidebarMinWidth)
        let targetHeight = max(frame.height, MainWindowMetrics.minHeight)
        guard targetWidth != frame.width || targetHeight != frame.height else { return }

        window.setFrame(
            NSRect(
                x: frame.minX,
                y: frame.maxY - targetHeight,
                width: targetWidth,
                height: targetHeight
            ),
            display: true
        )
    }

    private static func sidebarIsVisible(for columnVisibility: NavigationSplitViewVisibility) -> Bool {
        switch columnVisibility {
        case .detailOnly:
            return false
        case .all, .doubleColumn, .automatic:
            return true
        default:
            return true
        }
    }

    private func installResizeObserverIfNeeded(for window: NSWindow) {
        guard resizeObserver == nil else { return }
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            guard let self, let window else { return }
            Self.applyMinimumSize(to: window)
            self.collapseSidebarIfNeeded(for: window)
        }
    }

    private func collapseSidebarIfNeeded(for window: NSWindow) {
        guard
            window.frame.width < MainWindowMetrics.expandedSidebarMinWidth,
            Self.sidebarIsVisible(for: columnVisibility.wrappedValue)
        else {
            return
        }
        columnVisibility.wrappedValue = .detailOnly
    }
}

private struct SidebarView: View {
    @Binding var selectedPage: PreferencesPage?

    var body: some View {
        List(selection: $selectedPage) {
            Section {
                ForEach(PreferencesPage.allCases) { page in
                    Label(page.rawValue, systemImage: page.symbolName)
                        .tag(page)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            SidebarLogoView()
                .padding(.top, 8)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

private struct SidebarLogoView: View {
    var body: some View {
        Text("Hey Snap")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(.primary)
            .accessibilityLabel("HeySnap")
    }
}

/// App brand mark backed by the bundled `AppIcon` (the generated `.icns`), so
/// in-app chrome stays in sync with the real Dock/Finder icon. Falls back to an
/// accent squircle + viewfinder symbol if the icon image can't be resolved.
private struct BrandIcon: View {
    var size: CGFloat
    var cornerRadius: CGFloat

    var body: some View {
        Group {
            if let image = Self.iconImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Palette.accent)
                    .overlay {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: size * 0.5, weight: .semibold))
                            .foregroundStyle(Color.white)
                    }
            }
        }
        .frame(width: size, height: size)
    }

    private static let iconImage: NSImage? =
        NSImage(named: "AppIcon") ?? NSApplication.shared.applicationIconImage
}

private struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                content
            }
            .padding(Metrics.pagePadding)
            .frame(maxWidth: Metrics.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Palette.pageBackground)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let symbolName: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.leading, 4)

            VStack(spacing: 0) {
                content
            }
            .background(Palette.cardBackground, in: RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
                    .stroke(Palette.cardBorder, lineWidth: Metrics.hairline)
            }
        }
    }
}

private struct SettingsRow<Control: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13.8, weight: .medium))
                    .foregroundStyle(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, subtitle == nil ? 8 : 10)
        .frame(
            maxWidth: .infinity,
            minHeight: subtitle == nil ? Metrics.compactPrimaryRowMinHeight : Metrics.rowMinHeight,
            alignment: .leading
        )
    }
}

private struct CompactSettingsRow<Control: View>: View {
    let title: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(title)
                .font(.system(size: 12.6, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            control
        }
        .padding(.leading, 28)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: Metrics.compactRowMinHeight, alignment: .leading)
    }
}

private struct SettingsSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Palette.separator)
            .frame(height: Metrics.hairline)
            .padding(.leading, 14)
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var screenshotService: ScreenshotService

    var body: some View {
        SettingsPage {
            SettingsSection(title: "Storage", symbolName: "folder") {
                SettingsRow(
                    title: "Save location"
                ) {
                    SaveLocationButton(settings: settings)
                }

                SettingsSeparator()

                SettingsRow(title: "After capture") {
                    PostCaptureActionPicker(settings: settings)
                }

                SettingsSeparator()

                SettingsRow(title: "Save format") {
                    SaveFormatModePicker(settings: settings)
                }

                if settings.saveFormatMode == .automatic {
                    ForEach(ScreenshotOutputFormat.allCases) { format in
                        SettingsSeparator()

                        CompactSettingsRow(title: format.displayName) {
                            Toggle(format.displayName, isOn: automaticFormatBinding(for: format))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .tint(Palette.switchOnTint)
                        }
                    }
                }

                SettingsSeparator()

                SettingsRow(
                    title: "Resize retina screenshots",
                    subtitle: "Downscale Retina captures to 1x when saving."
                ) {
                    Toggle("Resize retina screenshots", isOn: $settings.resizeRetinaScreenshots)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(Palette.switchOnTint)
                }
            }

            SettingsSection(title: "Window Screenshot Background", symbolName: "macwindow") {
                WindowBackgroundPicker(selection: $settings.windowScreenshotBackground)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            SettingsSection(title: "Permissions", symbolName: "lock.shield") {
                SettingsRow(
                    title: "Screen Recording",
                    subtitle: "Required to capture the screen."
                ) {
                    HStack(spacing: 10) {
                        Label(
                            screenshotService.hasScreenRecordingPermission ? "Granted" : "Required",
                            systemImage: screenshotService.hasScreenRecordingPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(screenshotService.hasScreenRecordingPermission ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))

                        if !screenshotService.hasScreenRecordingPermission {
                            Button("Open Settings…") {
                                settings.openScreenRecordingSettings()
                            }
                        }
                    }
                }
            }

        }
        .onAppear {
            screenshotService.refreshPermissionStatus()
        }
    }

    private func automaticFormatBinding(for format: ScreenshotOutputFormat) -> Binding<Bool> {
        Binding {
            settings.automaticSaveFormats.contains(format)
        } set: { isSelected in
            var formats = settings.automaticSaveFormats
            if isSelected {
                formats.insert(format)
            } else if formats.count > 1 {
                formats.remove(format)
            }
            settings.automaticSaveFormats = formats
        }
    }

}

private struct WindowBackgroundPicker: View {
    @Binding var selection: WindowScreenshotBackground

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(WindowScreenshotBackground.allCases) { option in
                WindowBackgroundOptionButton(
                    option: option,
                    isSelected: option == selection
                ) {
                    selection = option
                }
            }
        }
    }
}

private struct WindowBackgroundOptionButton: View {
    let option: WindowScreenshotBackground
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                WindowBackgroundPreview(option: option)
                    .frame(width: Metrics.windowBackgroundPreviewWidth, height: Metrics.windowBackgroundPreviewHeight)
                    .clipShape(previewShape)
                    .overlay {
                        previewShape
                            .strokeBorder(previewBorder, lineWidth: isSelected ? 3 : Metrics.hairline)
                    }

                Text(option.displayName)
                    .font(.system(size: 13.2, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(width: Metrics.windowBackgroundTileWidth)
            }
            .frame(width: Metrics.windowBackgroundTileWidth)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.displayName)
        .onHover { isHovering = $0 }
    }

    private var previewBorder: Color {
        if isSelected {
            return Color(nsColor: .controlAccentColor)
        }
        if isHovering {
            return Palette.previewHoverBorder
        }
        return Palette.previewBorder
    }

    private var previewShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }
}

private struct WindowBackgroundPreview: View {
    let option: WindowScreenshotBackground

    var body: some View {
        Canvas { context, size in
            let previewRect = CGRect(origin: .zero, size: size)
            let windowRect = CGRect(
                x: Metrics.windowBackgroundChromeX,
                y: Metrics.windowBackgroundChromeY,
                width: Metrics.windowBackgroundChromeWidth,
                height: Metrics.windowBackgroundChromeHeight
            )

            drawBackground(in: previewRect, context: &context)
            drawWindowTreatment(around: windowRect, context: &context)
            drawWindow(in: windowRect, context: &context)
        }
    }

    private func drawBackground(in rect: CGRect, context: inout GraphicsContext) {
        switch option {
        case .wallpaper:
            context.fill(
                Path(rect),
                with: .linearGradient(
                    Gradient(colors: [
                        Color(nsColor: Palette.wallpaperBlue),
                        Color(nsColor: Palette.wallpaperIce),
                        Color(nsColor: Palette.wallpaperBlue)
                    ]),
                    startPoint: CGPoint(x: rect.minX, y: rect.minY),
                    endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
                )
            )

            for index in 0..<5 {
                var path = Path()
                let x = CGFloat(index * 20) - 30
                path.move(to: CGPoint(x: x, y: rect.maxY + 8))
                path.addLine(to: CGPoint(x: x + 34, y: rect.minY - 8))
                context.stroke(path, with: .color(Color.white.opacity(0.35)), lineWidth: 8)
            }
        case .transparent:
            drawCheckerboard(in: rect, context: &context, opacity: 1)
        case .shadow:
            drawCheckerboard(in: rect, context: &context, opacity: 0.55)
        case .solidColor:
            context.fill(Path(rect), with: .color(Palette.solidPreviewBackground))
        }
    }

    private func drawWindowTreatment(around windowRect: CGRect, context: inout GraphicsContext) {
        switch option {
        case .shadow:
            drawFloatingShadow(for: windowRect, context: &context)
        case .transparent, .solidColor, .wallpaper:
            break
        }
    }

    private func drawWindow(in rect: CGRect, context: inout GraphicsContext) {
        let windowPath = Path(roundedRect: rect, cornerRadius: 7)
        context.fill(windowPath, with: .color(Palette.previewWindowFill))
        context.stroke(windowPath, with: .color(Palette.previewWindowStroke), lineWidth: 1)

        let trafficLightY = rect.minY + 9
        for (index, color) in [Color(nsColor: .systemRed), Color(nsColor: .systemYellow), Color(nsColor: .systemGreen)].enumerated() {
            let circleRect = CGRect(
                x: rect.minX + 11 + CGFloat(index * 12),
                y: trafficLightY,
                width: 7,
                height: 7
            )
            context.fill(Path(ellipseIn: circleRect), with: .color(color))
        }
    }

    private func drawFloatingShadow(for rect: CGRect, context: inout GraphicsContext) {
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3))
            layer.fill(
                Path(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: 7),
                with: .color(Palette.previewWindowFill.opacity(0.9))
            )
        }
    }

    private func drawCheckerboard(in rect: CGRect, context: inout GraphicsContext, opacity: Double) {
        let cellSize = 8.0
        for row in 0..<Int(ceil(rect.height / cellSize)) {
            for column in 0..<Int(ceil(rect.width / cellSize)) {
                let isDark = (row + column).isMultiple(of: 2)
                let cellRect = CGRect(
                    x: rect.minX + CGFloat(column) * cellSize,
                    y: rect.minY + CGFloat(row) * cellSize,
                    width: cellSize,
                    height: cellSize
                )
                context.fill(
                    Path(cellRect),
                    with: .color((isDark ? Palette.checkerDark : Palette.checkerLight).opacity(opacity))
                )
            }
        }
    }
}

private struct CheckerboardBackground: View {
    private let cellSize: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            for row in 0..<Int(ceil(size.height / cellSize)) {
                for column in 0..<Int(ceil(size.width / cellSize)) {
                    let isDark = (row + column).isMultiple(of: 2)
                    let rect = CGRect(
                        x: CGFloat(column) * cellSize,
                        y: CGFloat(row) * cellSize,
                        width: cellSize,
                        height: cellSize
                    )
                    context.fill(
                        Path(rect),
                        with: .color(isDark ? Palette.checkerDark : Palette.checkerLight)
                    )
                }
            }
        }
    }
}

private struct SaveFormatModePicker: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        NativePopupButton(selection: $settings.saveFormatMode, options: ScreenshotSaveFormatMode.allCases)
            .frame(width: Metrics.popupControlWidth, height: Metrics.controlHeight, alignment: .trailing)
    }
}

private struct PostCaptureActionPicker: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        NativePopupButton(selection: $settings.postCaptureAction, options: PostCaptureAction.allCases)
            .frame(width: Metrics.popupControlWidth, height: Metrics.controlHeight, alignment: .trailing)
    }
}

private protocol PopupDisplayOption: CaseIterable, Equatable {
    var rawValue: String { get }
    var displayName: String { get }
}

extension ScreenshotSaveFormatMode: PopupDisplayOption {}
extension PostCaptureAction: PopupDisplayOption {}

private struct NativePopupButton<Option: PopupDisplayOption>: NSViewRepresentable {
    @Binding var selection: Option
    let options: [Option]

    func makeNSView(context: Context) -> HoverTrackingPopUpButton {
        let popupButton = HoverTrackingPopUpButton(frame: .zero, pullsDown: false)
        popupButton.controlSize = .large
        popupButton.bezelStyle = .rounded
        popupButton.font = Metrics.settingsControlFont
        popupButton.menu?.autoenablesItems = false
        popupButton.target = context.coordinator
        popupButton.action = #selector(Coordinator.selectionDidChange(_:))
        popupButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        popupButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        populate(popupButton)
        if let cell = popupButton.cell {
            cell.font = Metrics.settingsControlFont
            cell.lineBreakMode = .byTruncatingMiddle
        }
        return popupButton
    }

    func updateNSView(_ popupButton: HoverTrackingPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.options = options
        if popupButton.numberOfItems != options.count {
            populate(popupButton)
        }

        if let selectedIndex = options.firstIndex(of: selection),
           popupButton.indexOfSelectedItem != selectedIndex {
            popupButton.selectItem(at: selectedIndex)
        }

        if let cell = popupButton.cell {
            cell.font = Metrics.settingsControlFont
            cell.lineBreakMode = .byTruncatingMiddle
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection, options: options)
    }

    private func populate(_ popupButton: NSPopUpButton) {
        popupButton.removeAllItems()
        for option in options {
            popupButton.addItem(withTitle: option.displayName)
            popupButton.lastItem?.representedObject = option.rawValue
        }
    }

    final class Coordinator: NSObject {
        var selection: Binding<Option>
        var options: [Option]

        init(selection: Binding<Option>, options: [Option]) {
            self.selection = selection
            self.options = options
        }

        @objc func selectionDidChange(_ sender: NSPopUpButton) {
            let selectedIndex = sender.indexOfSelectedItem
            guard options.indices.contains(selectedIndex) else {
                return
            }
            selection.wrappedValue = options[selectedIndex]
        }
    }
}

private final class HoverTrackingPopUpButton: NSPopUpButton {
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let newTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        wantsLayer = true
        layer?.cornerRadius = Metrics.controlCornerRadius
        layer?.backgroundColor = Palette.controlHoverNS.cgColor
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        layer?.backgroundColor = nil
    }
}

private struct SaveLocationButton: View {
    @ObservedObject var settings: AppSettings
    @State private var isHovering = false
    @State private var isPressing = false

    var body: some View {
        Button {
            settings.chooseSaveDirectory()
        } label: {
            Text((settings.saveDirectoryPath as NSString).abbreviatingWithTildeInPath)
                .font(.system(size: 13.2))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 10)
                .frame(
                    minWidth: 120,
                    idealWidth: nil,
                    maxWidth: 220,
                    minHeight: Metrics.compactControlHeight,
                    idealHeight: Metrics.compactControlHeight,
                    maxHeight: Metrics.compactControlHeight,
                    alignment: .center
                )
                .fixedSize(horizontal: true, vertical: false)
                .background(locationBackground, in: RoundedRectangle(cornerRadius: Metrics.controlCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.controlCornerRadius, style: .continuous)
                        .stroke(Palette.controlBorder, lineWidth: Metrics.hairline)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose save location")
        .onHover { isHovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressing = true }
                .onEnded { _ in isPressing = false }
        )
    }

    private var locationBackground: Color {
        if isPressing {
            return Palette.controlPressedBackground
        }
        if isHovering {
            return Palette.controlHoverBackground
        }
        return Palette.controlBackground
    }
}

private struct HotKeysSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var hotKeyService: HotKeyService

    var body: some View {
        SettingsPage {
            SettingsSection(title: "Keyboard shortcuts", symbolName: "keyboard") {
                SettingsRow(
                    title: "Current screen",
                    subtitle: "Capture the screen under the mouse."
                ) {
                    ShortcutRecorderField(shortcut: screenShortcutBinding)
                }

                SettingsSeparator()

                SettingsRow(
                    title: "Area selection",
                    subtitle: "Drag to capture a region of the screen."
                ) {
                    ShortcutRecorderField(shortcut: areaShortcutBinding)
                }

                if let error = hotKeyService.registrationError {
                    SettingsSeparator()

                    SettingsRow(title: "Registration", subtitle: error) {
                        Button("Retry") {
                            retryRegistration()
                        }
                    }
                }
            }
        }
    }

    /// Assigning a combo already used by the other action takes it over, like System Settings.
    private var screenShortcutBinding: Binding<HotKeyShortcut?> {
        Binding {
            settings.screenShortcut
        } set: { newValue in
            if let newValue, newValue == settings.areaShortcut {
                settings.areaShortcut = nil
            }
            settings.screenShortcut = newValue
        }
    }

    private var areaShortcutBinding: Binding<HotKeyShortcut?> {
        Binding {
            settings.areaShortcut
        } set: { newValue in
            if let newValue, newValue == settings.screenShortcut {
                settings.screenShortcut = nil
            }
            settings.areaShortcut = newValue
        }
    }

    private func retryRegistration() {
        var shortcuts: [HotKeyAction: HotKeyShortcut] = [:]
        shortcuts[.screen] = settings.screenShortcut
        shortcuts[.area] = settings.areaShortcut
        try? hotKeyService.register(shortcuts: shortcuts)
    }
}

private struct AboutSettingsView: View {
    var body: some View {
        SettingsPage {
            SettingsSection(title: "About", symbolName: "info.circle") {
                HStack(spacing: 14) {
                    AppIconMark()

                    VStack(alignment: .leading, spacing: 3) {
                        Text("HeySnap")
                            .font(.system(size: 22, weight: .semibold))

                        Text("Fast screenshot capture for macOS.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)

                SettingsSeparator()

                SettingsRow(title: "Version") {
                    Text(Bundle.main.displayVersion)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct AppIconMark: View {
    var body: some View {
        BrandIcon(size: 56, cornerRadius: 14)
            .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
    }
}

private enum Metrics {
    static let sidebarWidth: CGFloat = 160
    static let pagePadding: CGFloat = 20
    static let pageMaxWidth: CGFloat = 720
    static let sectionSpacing: CGFloat = 20
    static let cardCornerRadius: CGFloat = 10
    static let rowMinHeight: CGFloat = 52
    static let compactPrimaryRowMinHeight: CGFloat = 44
    static let compactRowMinHeight: CGFloat = 34
    static let controlHeight: CGFloat = 34
    static let compactControlHeight: CGFloat = 28
    static let controlCornerRadius: CGFloat = 6
    static let popupControlWidth: CGFloat = 120
    static let windowBackgroundTileWidth: CGFloat = 96
    static let windowBackgroundPreviewWidth: CGFloat = 88
    static let windowBackgroundPreviewHeight: CGFloat = 60
    static let windowBackgroundChromeX: CGFloat = 14
    static let windowBackgroundChromeY: CGFloat = 13
    static let windowBackgroundChromeWidth: CGFloat = 60
    static let windowBackgroundChromeHeight: CGFloat = 34
    static let hairline: CGFloat = 0.5
    static var settingsControlFont: NSFont { NSFont.systemFont(ofSize: 13.2) }
}

private enum Palette {
    static let accent = Color(nsColor: dynamic(light: 0x25262B, dark: 0xF0F1F3))
    static let pageBackground = Color(nsColor: dynamic(light: 0xF6F5F4, dark: 0x1B1C1F))
    static let cardBackground = Color(nsColor: dynamic(light: 0xFFFFFF, dark: 0x1F2024))
    static let cardBorder = Color(nsColor: dynamic(light: 0xE3E4E7, dark: 0x34363B))
    static let controlBackground = Color(nsColor: dynamic(light: 0xF0F1F3, dark: 0x303238))
    static let controlHoverBackground = Color(nsColor: controlHoverNS)
    static let controlPressedBackground = Color(nsColor: dynamic(light: 0xE4E5E8, dark: 0x454850))
    static let controlBorder = Color(nsColor: dynamic(light: 0xE6E7EA, dark: 0x3A3C42))
    static let switchOnTint = Color(nsColor: dynamic(light: 0x2F3034, dark: 0x111214))
    static let separator = Color(nsColor: dynamic(light: 0xECEDEF, dark: 0x2D2F34))
    static let controlHoverNS = dynamic(light: 0xE9EAED, dark: 0x3A3C43)
    static let previewBorder = Color(nsColor: dynamic(light: 0xB8BCC4, dark: 0x51545C))
    static let previewHoverBorder = Color(nsColor: dynamic(light: 0x8F949D, dark: 0x6A6E78))
    static let checkerLight = Color(nsColor: dynamic(light: 0xD7D9DE, dark: 0x4A4D55))
    static let checkerDark = Color(nsColor: dynamic(light: 0xAFB3BC, dark: 0x30333A))
    static let solidPreviewBackground = Color(nsColor: dynamic(light: 0xDDE1E6, dark: 0x464A52))
    static let previewWindowFill = Color(nsColor: dynamic(light: 0xF7F8FA, dark: 0x3F4248))
    static let previewWindowStroke = Color(nsColor: dynamic(light: 0xA7ACB6, dark: 0x696E78))
    static let wallpaperBlue = dynamic(light: 0x61B7E3, dark: 0x155FAE)
    static let wallpaperIce = dynamic(light: 0xDFF4FF, dark: 0x6DB7F0)

    private static func dynamic(light: Int, dark: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return color(hex: isDark ? dark : light)
        }
    }

    private static func color(hex: Int) -> NSColor {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
    }
}

private extension Bundle {
    var displayVersion: String {
        let shortVersion = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(shortVersion) (\(build))"
    }
}
