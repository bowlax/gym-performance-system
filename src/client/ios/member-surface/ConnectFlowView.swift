import SwiftUI

/// Full connect flow: explainer → auth → branch → sync or discard-cloud-wins (#31 / #33).
///
/// When hosted from onboarding, pass `onDecline` / `onConnected` so the host
/// can fork to manual PB population (or skip it) using `ConnectBranchAssessment`.
struct ConnectFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppDependencies.self) private var dependencies

    /// Onboarding / host: member tapped Not now / Close on the explainer.
    var onDecline: (() -> Void)? = nil
    /// Onboarding / host: connect + sync/discard finished successfully.
    var onConnected: ((ConnectBranchAssessment) -> Void)? = nil

    @State private var step: Step = .explainer
    @State private var session: BrokerSession?
    @State private var claims: JWTClaimsDecoder.Claims?
    @State private var branchAssessment: ConnectBranchAssessment?
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
                        onNotNow: { decline() }
                    )
                case .discardWarning:
                    DiscardCloudWinsView(
                        onProceed: { Task { await runDiscard() } },
                        onCancel: {
                            session = nil
                            claims = nil
                            branchAssessment = nil
                            decline()
                        }
                    )
                case .syncing:
                    ConnectUploadProgressView(
                        result: syncResult,
                        isSyncing: isWorking && syncResult == nil,
                        onDone: { finishAfterSync() },
                        onRetry: { Task { await runSync() } }
                    )
                case .discarding:
                    DiscardCloudWinsProgressView(
                        result: discardResult,
                        isWorking: isWorking && discardResult == nil,
                        onDone: { finishAfterDiscard() },
                        onRetryPull: { Task { await retryDiscardPull() } }
                    )
                case .failed(let message):
                    VStack(alignment: .leading, spacing: .sectionSpacing) {
                        Text("Couldn’t connect")
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                        Text(message)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(.secondary)
                        Button("Close") { decline() }
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
                        Button("Close") { decline() }
                            .foregroundStyle(Color.wolfBlue)
                    }
                }
            }
        }
        .tint(Color.wolfBlue)
    }

    private func decline() {
        if let onDecline {
            onDecline()
        } else {
            dismiss()
        }
    }

    /// Successful upload/sync path — only advance onboarding when sync completed.
    private func finishAfterSync() {
        dependencies.refresh()
        let succeeded = syncResult?.completed == true
        finishHostedOrDismiss(connectedSuccessfully: succeeded)
    }

    /// Discard path — local cleared (or full complete) means cloud history owns the board;
    /// skip-populate still applies even if pull needs a later retry.
    private func finishAfterDiscard() {
        dependencies.refresh()
        let succeeded = discardResult?.completed == true || discardResult?.cleared == true
        finishHostedOrDismiss(connectedSuccessfully: succeeded)
    }

    private func finishHostedOrDismiss(connectedSuccessfully: Bool) {
        if connectedSuccessfully, let onConnected {
            onConnected(
                branchAssessment
                    ?? ConnectBranchAssessment(
                        adopted: false,
                        hasLocal: false,
                        hasCloud: false,
                        postAuthBranch: .proceedToUpload
                    )
            )
            return
        }
        if !connectedSuccessfully, let onDecline {
            onDecline()
            return
        }
        dismiss()
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

            // Assess before persist so a blocked different-account connect never
            // writes tokens / isConnected / lastConnectedMemberId.
            let assessment = try await flow.assessBranch(
                session: brokerSession,
                claims: brokerClaims
            )
            branchAssessment = assessment

            switch assessment.postAuthBranch {
            case .blockedDifferentAccount:
                step = .failed(ConnectBranchLogic.blockedDifferentAccountMessage)
            case .discardCloudWinsChoice:
                flow.persistConnected(session: brokerSession, claims: brokerClaims)
                step = .discardWarning
            case .proceedToUpload:
                flow.persistConnected(session: brokerSession, claims: brokerClaims)
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
