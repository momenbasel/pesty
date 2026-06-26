import SwiftUI

struct BarView: View {
    @Bindable private var store = ClipboardStore.shared
    @Bindable private var settings = Settings.shared

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow)
            Theme.panelTint
        }
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                topBar
                strip
            }
        }
        .clipShape(RoundedCorners(radius: Theme.cornerRadius, corners: [.topLeft, .topRight]))
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            syncButton
            searchIndicator
            PinboardTabs()
                .layoutPriority(1)
            Spacer(minLength: 8)
            moreMenu
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
    }

    private var syncButton: some View {
        Button {
            AppController.shared.toggleICloudSync()
        } label: {
            Image(systemName: settings.iCloudSync ? "checkmark.icloud.fill" : "arrow.triangle.2.circlepath")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(settings.iCloudSync ? Theme.selection : Theme.textSecondary)
        }
        .buttonStyle(.plain)
        .help(settings.iCloudSync ? "iCloud sync on" : "Turn on iCloud sync")
    }

    private var searchIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(store.searchText.isEmpty ? Theme.textSecondary : Theme.textPrimary)
            if !store.searchText.isEmpty {
                Text(store.searchText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Button { store.searchText = ""; store.selectFirst() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, store.searchText.isEmpty ? 0 : 10)
        .frame(height: 30)
        .background(store.searchText.isEmpty ? Color.clear : Theme.fieldBG, in: Capsule())
        .animation(.easeOut(duration: 0.15), value: store.searchText.isEmpty)
    }

    private var moreMenu: some View {
        Menu {
            Button("Settings…") { AppController.shared.showSettings() }
            Button("Clear History") { store.clearHistory() }
            Divider()
            Button("About Pesty") { AppController.shared.showAbout() }
            Button("Quit Pesty") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 30, height: 30)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 34)
        .fixedSize()
    }

    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.cardSpacing) {
                    ForEach(Array(store.visibleItems.enumerated()), id: \.element.id) { index, item in
                        ClipCardView(item: item,
                                     index: index,
                                     selected: item.id == store.selectedID)
                            .id(item.id)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.92).combined(with: .opacity),
                                removal: .opacity))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 18)
                .animation(.spring(response: 0.34, dampingFraction: 0.8), value: store.visibleItems.count)
            }
            .onChange(of: store.selectedID) { _, id in
                guard let id else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .overlay { if store.visibleItems.isEmpty { emptyState } }
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: store.searchText.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text(store.searchText.isEmpty
                 ? "Nothing copied yet"
                 : "No matches for “\(store.searchText)”")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

struct RoundedCorners: Shape {
    var radius: CGFloat
    var corners: RectCorner

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let tl = corners.contains(.topLeft) ? radius : 0
        let tr = corners.contains(.topRight) ? radius : 0
        let bl = corners.contains(.bottomLeft) ? radius : 0
        let br = corners.contains(.bottomRight) ? radius : 0
        p.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr,
                 startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        p.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        p.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

struct RectCorner: OptionSet {
    let rawValue: Int
    static let topLeft = RectCorner(rawValue: 1 << 0)
    static let topRight = RectCorner(rawValue: 1 << 1)
    static let bottomLeft = RectCorner(rawValue: 1 << 2)
    static let bottomRight = RectCorner(rawValue: 1 << 3)
}
