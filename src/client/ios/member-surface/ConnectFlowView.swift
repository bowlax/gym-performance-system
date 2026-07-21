import SwiftUI

/// Full connect flow: explainer → auth → branch → sync or discard-cloud-wins (#31 / #33).
struct ConnectFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppDependencies.self) private var dependencies

    @State private var step: Step = .explainer
    @State private var session: BrokerSession?
    @State private var claims: JWTClaimsDecoder.Claims?
    @State private var syncResult: SyncCycleResult?
    @State private var discardResult: DiscardCloudWinsResult?
    @State private var isWorking = false

    private enum Step: Equatable {
        case explainer
        case discardWarning
        case syncing
        case discarding
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .explainer:
                    ConnectExplainerView(
                        onConnect: { Task { await startAuth() } },
                        onNotNow: { dismiss() }
                    )
                case .discardWarning:
                    DiscardCloudWinsView(
                        onProceed: { Task { await runDiscard() } },
                        onCancel: {
                            session = nil
                            claims = nil
                            dismiss()
                        }
                    )
                case .syncing:
                    ConnectUploadProgressView(
                        result: syncResult,
                        isSyncing: isWorking && syncResult == nil,
                        onDone: {
                            dependencies.refresh()
                            dismiss()
                        },
                        onRetry: { Task { await runSync() } }
                    )
                case .discarding:
                    DiscardCloudWinsProgressView(
                        result: discardResult,
                        isWorking: isWorking && discardResult == nil,
                        onDone: {
                            dependencies.refresh()
                            dismiss()
                        },
                        onRetryPull: { Task { await retryDiscardPull() } }
                    )
                case .failed(let message):
                    VStack(alignment: .leading, spacing: .sectionSpacing) {
                        Text("Couldn’t connect")
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                        Text(message)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(.secondary)
                        Button("Close") { dismiss() }
                            .primaryButtonStyle(isEnabled: true)
                        Spacer()
                    }
                    .padding()
                }
            }
            .overlay {
                if isWorking && step == .explainer {
                    ProgressView()
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if step == .explainer {
                        Button("Close") { dismiss() }
                            .foregroundStyle(Color.wolfBlue)
                    }
                }
            }
        }
        .tint(Color.wolfBlue)
    }

    @MainActor
    private func startAuth() async {
        guard ConnectFeatureAvailability.isAvailable else {
            step = .failed("Connect isn’t available in this build.")
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let flow = try ConnectFlowService.makeFromCloudConfig(
                modelContext: dependencies.modelContext,
                performanceDataAccess: dependencies.performanceDataAccess
            )
            let (brokerSession, brokerClaims) = try await flow.authenticate()
            session = brokerSession
            claims = brokerClaims

            flow.persistConnected(session: brokerSession, claims: brokerClaims)

            let branch = try await flow.assessBranch(session: brokerSession, claims: brokerClaims)
            switch branch {
            case .discardCloudWinsChoice:
                step = .discardWarning
            case .proceedToUpload:
                await runSync(flow: flow, session: brokerSession, claims: brokerClaims)
            }
        } catch {
            step = .failed(error.localizedDescription)
        }
    }

    @MainActor
    private func runSync(
        flow: ConnectFlowService? = nil,
        session overrideSession: BrokerSession? = nil,
        claims overrideClaims: JWTClaimsDecoder.Claims? = nil
    ) async {
        guard let brokerSession = overrideSession ?? session,
              let brokerClaims = overrideClaims ?? claims else {
            step = .failed("Missing session — try connecting again.")
            return
        }

        step = .syncing
        syncResult = nil
        isWorking = true
        defer { isWorking = false }

        do {
            let service = try flow ?? ConnectFlowService.makeFromCloudConfig(
                modelContext: dependencies.modelContext,
                performanceDataAccess: dependencies.performanceDataAccess
            )
            let result = await service.syncAfterConnect(session: brokerSession)
            if result.completed {
                SyncStatusStore.recordSuccess(memberId: brokerClaims.memberId)
            } else {
                SyncStatusStore.recordFailure(
                    memberId: brokerClaims.memberId,
                    message: result.errorMessage ?? "Sync failed"
                )
            }
            syncResult = result
        } catch {
            SyncStatusStore.recordFailure(
                memberId: brokerClaims.memberId,
                message: error.localizedDescription
            )
            syncResult = SyncCycleResult(
                pull: .interrupted(
                    mergeCounts: SyncMergeCounts(),
                    highWaterSyncedAt: nil,
                    error: error
                ),
                push: .interrupted(counts: FirstConnectUploadCounts(), error: error)
            )
        }
    }

    @MainActor
    private func runDiscard() async {
        guard ConnectFeatureAvailability.isAvailable else {
            step = .failed("Connect isn’t available in this build.")
            return
        }
        guard let brokerSession = session, let brokerClaims = claims else {
            step = .failed("Missing session — try connecting again.")
            return
        }

        step = .discarding
        discardResult = nil
        isWorking = true
        defer { isWorking = false }

        do {
            let service = try ConnectFlowService.makeFromCloudConfig(
                modelContext: dependencies.modelContext,
                performanceDataAccess: dependencies.performanceDataAccess
            )
            // Capture anonymous id before adopt (service holds the pre-auth device id).
            discardResult = await service.discardLocalAndPullFromCloud(
                session: brokerSession,
                claims: brokerClaims
            )
        } catch {
            discardResult = .failedBeforeClear(error: error)
        }
    }

    @MainActor
    private func retryDiscardPull() async {
        guard let brokerSession = session, let brokerClaims = claims else {
            step = .failed("Missing session — try connecting again.")
            return
        }

        discardResult = nil
        isWorking = true
        defer { isWorking = false }

        do {
            let service = try ConnectFlowService.makeFromCloudConfig(
                modelContext: dependencies.modelContext,
                performanceDataAccess: dependencies.performanceDataAccess
            )
            discardResult = await service.retryPullAfterDiscard(
                session: brokerSession,
                claims: brokerClaims
            )
        } catch {
            discardResult = DiscardCloudWinsResult(
                cleared: true,
                pull: .interrupted(
                    mergeCounts: SyncMergeCounts(),
                    highWaterSyncedAt: nil,
                    error: error
                ),
                completed: false,
                errorMessage: error.localizedDescription
            )
        }
    }
}
