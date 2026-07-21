import SwiftUI

/// Settings: personal-best staleness (#28) + Connect / sync status (#31 / #32).
struct AppInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppDependencies.self) private var dependencies

    @State private var enabled = false
    @State private var periods = 2
    @State private var unit: StalenessPeriodUnit = .quarter
    @State private var saveError: String?
    @State private var isLoaded = false
    @State private var showConnectFlow = false
    /// Bumps relative "Last synced" copy while the sheet is open.
    @State private var relativeClock = Date()

    private var isConnected: Bool { MemberConnectionStore.isConnected }
    private var sync: SyncCoordinator { dependencies.syncCoordinator }

    private var relativeSyncFormatter: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Let personal bests lapse", isOn: $enabled)

                    if enabled {
                        Stepper(value: $periods, in: 1...12) {
                            Text("After \(periods) complete \(unitLabel)")
                        }

                        Picker("Period", selection: $unit) {
                            Text("Quarters").tag(StalenessPeriodUnit.quarter)
                            Text("Months").tag(StalenessPeriodUnit.month)
                        }
                        .pickerStyle(.segmented)
                    }
                } header: {
                    Text("Personal bests")
                } footer: {
                    Text(stalenessFooter)
                }

                Section {
                    if isConnected {
                        connectedRows
                    } else if ConnectFeatureAvailability.isAvailable {
                        Button {
                            showConnectFlow = true
                        } label: {
                            Label("Connect with TeamUp", systemImage: "link")
                        }
                    } else {
                        Text("Connect isn’t available in this build.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Account")
                } footer: {
                    Text(accountFooter)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.wolfBlue)
                }
            }
            .onAppear(perform: load)
            .onChange(of: enabled) { _, _ in persistIfLoaded() }
            .onChange(of: periods) { _, _ in persistIfLoaded() }
            .onChange(of: unit) { _, _ in persistIfLoaded() }
            .alert("Couldn't save", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
            .alert("Sync couldn’t finish", isPresented: Binding(
                get: { sync.lastManualError != nil },
                set: { if !$0 { sync.clearManualError() } }
            )) {
                Button("OK", role: .cancel) { sync.clearManualError() }
            } message: {
                Text(sync.lastManualError ?? "")
            }
            .sheet(isPresented: $showConnectFlow) {
                ConnectFlowView()
            }
            .task(id: isConnected) {
                while !Task.isCancelled {
                    relativeClock = Date()
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                }
            }
        }
        .tint(Color.wolfBlue)
    }

    @ViewBuilder
    private var connectedRows: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text("Connected")
                if let memberId = MemberConnectionStore.connectedMemberId {
                    Text(memberId.uuidString)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if MemberConnectionStore.sessionNeedsReauth {
                    Text("Sign-in expired — open Connect to refresh.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.orange)
                }
            }
        } icon: {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(Color.wolfBlue)
        }

        if MemberConnectionStore.sessionNeedsReauth {
            Button {
                showConnectFlow = true
            } label: {
                Label("Sign in again", systemImage: "arrow.triangle.2.circlepath")
            }
        } else if ConnectFeatureAvailability.isAvailable {
            syncStatusRows
        }
    }

    @ViewBuilder
    private var syncStatusRows: some View {
        HStack {
            if sync.isSyncing {
                ProgressView()
                Text("Syncing…")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                Text(lastSyncedCaption)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
                    // Touch relativeClock so the caption refreshes.
                    .id(relativeClock)
            }
            Spacer()
        }

        if let failure = sync.unrecoveredFailureMessage, !sync.isSyncing {
            Text(failure)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.orange)
        }

        Button {
            Task { await sync.syncNow() }
        } label: {
            Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(sync.isSyncing)
    }

    private var lastSyncedCaption: String {
        _ = relativeClock
        guard let at = sync.lastSuccessfulCycleAt else {
            return "Not synced yet"
        }
        let relative = relativeSyncFormatter.localizedString(for: at, relativeTo: Date())
        return "Last synced \(relative)"
    }

    private var unitLabel: String {
        switch unit {
        case .quarter: return periods == 1 ? "quarter" : "quarters"
        case .month: return periods == 1 ? "month" : "months"
        }
    }

    private var stalenessFooter: String {
        """
        When this is on, a personal best stops counting as your current best if you don’t maintain it within the window you choose. Your lifetime best is always kept.

        Default is off. A common window is two complete calendar quarters.
        """
    }

    private var accountFooter: String {
        if isConnected {
            return "Disconnect isn’t available yet — it needs a clearer privacy policy first. Sync runs after you save a session, when you open the app (at most every six hours), or when you tap Sync now."
        }
        if ConnectFeatureAvailability.isAvailable {
            return "Connecting backs up your history and lets your coach see your progress. You can stay on this device only."
        }
        return "TeamUp connect requires cloud configuration in this build."
    }

    private func load() {
        isLoaded = false
        guard let setting = try? MemberState.stalenessSetting(
            in: dependencies.modelContext,
            memberId: dependencies.memberId
        ) else {
            DispatchQueue.main.async { isLoaded = true }
            return
        }
        enabled = setting.enabled
        periods = setting.periods
        unit = setting.unit
        DispatchQueue.main.async { isLoaded = true }
    }

    private func persistIfLoaded() {
        guard isLoaded else { return }
        do {
            try MemberState.updateStalenessSetting(
                MemberStalenessSetting(enabled: enabled, periods: periods, unit: unit),
                in: dependencies.modelContext,
                memberId: dependencies.memberId
            )
            dependencies.refresh()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

#Preview {
    AppInfoSheet()
}
