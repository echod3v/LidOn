import LidOnCore
import SwiftUI

struct MenuView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings

    private var ui: UIState { model.ui }
    /// 메뉴가 열려 있는가 — 닫혀 있으면 모든 애니메이션을 멈춘다 (뚜껑 닫힌 동안 배터리 절약)
    @State private var visible = false
    private var orb: OrbState { OrbState(ui.state) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            SystemSetupCard()
            manualCard
            if let h = hint { h.transition(.move(edge: .top).combined(with: .opacity)) }
            stats
            if !model.holds.isEmpty {
                requestList.transition(.move(edge: .top).combined(with: .opacity))
            }
            if let m = model.lastMessage {
                Label(m, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            if !model.history.isEmpty { historyList }
            if !model.lid.hasLid {
                Label("This Mac has no lid sensor", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(Theme.amber)
            }
            footer
        }
        .padding(16)
        .frame(width: 344)
        .tint(Theme.teal)
        .animation(Theme.spring, value: ui)
        .animation(Theme.spring, value: model.holds)
        .animation(Theme.spring, value: model.lastMessage)
        .onAppear { visible = true }
        .onDisappear { visible = false }
    }

    // MARK: - 머리글

    private var header: some View {
        HStack(spacing: 12) {
            StatusOrb(state: orb, size: 46, animated: visible)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: "LidOn")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Text(stateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let start = ui.sessionStart, visible {
                Pill(color: Theme.indigo) {
                    Text(start, style: .timer)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private var stateText: String {
        switch ui.state {
        case "sealed": return L("Running with the lid closed")
        case "armed": return L("Armed — closing the lid keeps your Mac running")
        default: return L("Idle — your Mac sleeps normally")
        }
    }

    // MARK: - 수동 토글

    private var manualCard: some View {
        Card(highlighted: ui.manualOn) {
            HStack(spacing: 10) {
                IconBadge(symbol: ui.manualOn ? "bolt.fill" : "bolt", color: ui.manualOn ? Theme.teal : .gray, size: 28)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep running with lid closed")
                        .font(.callout.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Group {
                        if let until = ui.manualUntil {
                            Text(L("Until %@", Fmt.time(until)))
                        } else {
                            Text(L("Shortcut: %@", HotKey.display))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                }
                Spacer(minLength: 0)
                Menu {
                    Button("For 30 minutes") { model.setManual(true, minutes: 30) }
                    Button("For 1 hour") { model.setManual(true, minutes: 60) }
                    Button("For 2 hours") { model.setManual(true, minutes: 120) }
                    Button("For 4 hours") { model.setManual(true, minutes: 240) }
                    Button("For 8 hours") { model.setManual(true, minutes: 480) }
                    Divider()
                    Button("Until turned off") { model.setManual(true) }
                } label: {
                    Image(systemName: "timer")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(Text("Turn on for a set time"))
                Toggle("Keep running with lid closed", isOn: Binding(get: { ui.manualOn }, set: { model.setManual($0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }

    private var hint: AnyView? {
        if ui.triggers.contains(.request) && ui.state == "armed" {
            return AnyView(
                Label {
                    Text("An agent asked to keep running — just close the lid")
                } icon: {
                    Image(systemName: "sparkles").symbolEffect(.pulse, options: .repeating, isActive: visible)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.teal)
            )
        }
        if settings.fnGesture && ui.state == "idle" {
            return AnyView(
                Label("Or hold Fn (🌐) while closing the lid", systemImage: "hand.point.up.left.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            )
        }
        return nil
    }

    // MARK: - 상태 타일

    private var stats: some View {
        let p = ui.power
        let temp = p.batteryTempC ?? 0
        let tempColor: Color = temp >= settings.maxBatteryTemp - 2 ? Theme.coral : temp >= settings.maxBatteryTemp - 7 ? Theme.amber : Theme.teal
        let thermalColor: Color = p.thermal >= .serious ? Theme.coral : p.thermal == .fair ? Theme.amber : Theme.teal
        let battery = Double(p.batteryPercent ?? 0) / 100
        let batteryColor: Color = p.onAC ? Theme.teal : battery <= 0.15 ? Theme.coral : battery <= 0.35 ? Theme.amber : Theme.teal
        return HStack(spacing: 8) {
            StatTile(icon: ui.lidClosed ? "lock.laptopcomputer" : "laptopcomputer",
                     value: ui.lidClosed ? L("Closed") : L("Open"), title: L("Lid"),
                     color: ui.lidClosed ? Theme.indigo : .secondary)
            StatTile(icon: p.charging ? "bolt.fill" : p.onAC ? "powerplug.fill" : "battery.75percent",
                     value: p.batteryPercent.map { "\($0)%" } ?? "—", title: L("Battery"),
                     color: batteryColor, fraction: p.batteryPercent == nil ? nil : battery)
            StatTile(icon: "thermometer.medium", value: p.batteryTempC.map { String(format: "%.0f°", $0) } ?? "—",
                     title: L("Battery temp"), color: tempColor)
            StatTile(icon: p.thermal >= .fair ? "flame.fill" : "leaf.fill", value: Fmt.thermal(p.thermal),
                     title: L("Thermal"), color: thermalColor)
        }
    }

    // MARK: - 에이전트 요청

    private var requestList: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(L("Agent requests"), count: model.holds.count)
            ForEach(model.sortedHolds, id: \.id) { h in
                Card(highlighted: true) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 8) {
                            Image(systemName: h.pid != nil && h.until == nil ? "terminal.fill" : "sparkles")
                                .foregroundStyle(Theme.accent)
                            Text(verbatim: h.label).font(.callout.weight(.medium)).lineLimit(1)
                            Spacer(minLength: 0)
                            if let u = h.until, visible {
                                Text(timerInterval: Date()...max(u, Date()), countsDown: true)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Button {
                                model.releaseHold(id: h.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(Text("Cancel this request"))
                        }
                        if let u = h.until, u > h.since, visible {
                            // 남은 시간 막대 — 시스템이 알아서 줄여 준다 (앱이 매초 다시 그리지 않음)
                            ProgressView(timerInterval: h.since...u, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                                .progressViewStyle(.linear)
                                .tint(Theme.mint)
                        }
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .scale(scale: 0.9).combined(with: .opacity)))
            }
        }
    }

    // MARK: - 기록

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(L("Recent sessions"))
            ForEach(model.history.prefix(3)) { r in
                HStack(spacing: 8) {
                    Image(systemName: Self.icon(for: r.reason))
                        .font(.caption)
                        .foregroundStyle(r.reason.isSafeguard ? Theme.amber : Theme.teal)
                        .frame(width: 16)
                    Text(Fmt.dateTime(r.start)).font(.caption)
                    Pill(color: .secondary) { Text(Fmt.duration(r.duration)) }
                    Spacer(minLength: 0)
                    Text(Fmt.reason(r)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    static func icon(for reason: EndReason) -> String {
        switch reason {
        case .lidOpened: return "laptopcomputer"
        case .requestFinished: return "sparkles"
        case .manualOff, .timerEnded: return "power"
        case .systemSlept: return "moon.fill"
        case .thermal, .batteryTemp, .lowBattery, .maxDuration: return "exclamationmark.shield.fill"
        }
    }

    private func sectionTitle(_ title: String, count: Int? = nil) -> some View {
        HStack(spacing: 6) {
            Text(title.uppercased(with: AppLanguage.locale))
                .font(.caption2.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            if let c = count {
                Text(verbatim: "\(c)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Theme.teal))
                    .contentTransition(.numericText())
            }
        }
    }

    // MARK: - 아래

    private var footer: some View {
        HStack {
            SettingsLink {
                Label("Settings…", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
            .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit LidOn", systemImage: "power")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }
}
