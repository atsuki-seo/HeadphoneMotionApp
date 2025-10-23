//
//  ContentView.swift
//  HeadphoneMotionApp
//
//  Created by atsuki.seo on 2025/10/23.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = MotionViewModel()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            MainMotionView(viewModel: viewModel)
                .tabItem {
                    Image(systemName: "headphones")
                    Text("モーション")
                }
                .tag(0)

            EnhancedDebugView(viewModel: viewModel)
                .tabItem {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                    Text("デバッグ")
                }
                .tag(1)

            EnhancedSettingsView(viewModel: viewModel)
                .tabItem {
                    Image(systemName: "gear")
                    Text("設定")
                }
                .tag(2)
        }
        .accentColor(.blue)
    }
}

// MARK: - Main Motion View

struct MainMotionView: View {
    @ObservedObject var viewModel: MotionViewModel

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // 接続状態表示
                    ConnectionStatusCard(viewModel: viewModel)

                    // エラー表示
                    if let errorMessage = viewModel.errorMessage {
                        ErrorCard(message: errorMessage) {
                            viewModel.clearError()
                        }
                    }

                    // 権限・接続ガイド
                    if needsUserAction {
                        UserActionCard(viewModel: viewModel)
                    }

                    // メインコントロール
                    ControlButtonsCard(viewModel: viewModel)

                    // リアルタイムデータ表示
                    if viewModel.currentMotionData != nil {
                        RealTimeDataCard(viewModel: viewModel)

                        // 3D姿勢ビジュアライザー
                        AttitudeVisualizer3D(attitudeData: viewModel.attitudeDisplayData)

                        // 回転率・加速度ビジュアライザー
                        RotationRateVisualizer(rotationData: viewModel.rotationDisplayData)
                        AccelerationVisualizer(accelerationData: viewModel.accelerationDisplayData)
                    }

                    // 最近のイベント
                    if !viewModel.recentMotionEvents.isEmpty {
                        RecentEventsCard(viewModel: viewModel)
                    }
                }
                .padding()
            }
            .navigationTitle("ヘッドホンモーション")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                viewModel.refreshConnectionState()
            }
        }
    }

    private var needsUserAction: Bool {
        viewModel.authorizationState == .denied ||
        viewModel.connectionState == .disconnected ||
        viewModel.connectionState == .connectedUnsupported
    }
}

// MARK: - Connection Status Card

struct ConnectionStatusCard: View {
    @ObservedObject var viewModel: MotionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: connectionIcon)
                    .foregroundColor(connectionColor)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text("接続状態")
                        .font(.headline)
                    Text(viewModel.connectionState.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: {
                    viewModel.refreshConnectionState()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.title3)
                }
            }

            if viewModel.audioRoute.isHeadphones {
                HStack {
                    Image(systemName: "headphones")
                        .foregroundColor(.blue)
                    Text("\(viewModel.headphoneType.description)")
                        .font(.subheadline)

                    if viewModel.headphoneType.expectedMotionSupport {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
            }

            // 更新状態表示
            HStack {
                Circle()
                    .fill(updateStateColor)
                    .frame(width: 8, height: 8)
                Text(viewModel.updateState.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var connectionIcon: String {
        switch viewModel.connectionState {
        case .disconnected:
            return "headphones.circle.fill"
        case .connected, .connectedUnsupported:
            return "headphones.circle"
        case .connectedMotionAvailable:
            return "headphones.circle.fill"
        }
    }

    private var connectionColor: Color {
        switch viewModel.connectionState {
        case .disconnected:
            return .red
        case .connected, .connectedUnsupported:
            return .orange
        case .connectedMotionAvailable:
            return .green
        }
    }

    private var updateStateColor: Color {
        switch viewModel.updateState {
        case .stopped:
            return .gray
        case .starting:
            return .orange
        case .active:
            return .green
        case .error:
            return .red
        }
    }
}

// MARK: - Error Card

struct ErrorCard: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.primary)

            Spacer()

            Button("閉じる", action: onDismiss)
                .font(.caption)
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(8)
    }
}

// MARK: - User Action Card

struct UserActionCard: View {
    @ObservedObject var viewModel: MotionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                Text("セットアップが必要です")
                    .font(.headline)
            }

            switch viewModel.authorizationState {
            case .denied:
                Text("モーション権限が拒否されています。設定アプリで権限を有効にしてください。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Button("設定を開く") {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsURL)
                    }
                }
                .buttonStyle(.borderedProminent)

            case .notDetermined:
                Text("モーション権限を許可してください。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

            case .authorized:
                switch viewModel.connectionState {
                case .disconnected:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("対応ヘッドホンを接続してください：")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("• AirPods Pro (第1/第2世代)")
                            Text("• AirPods Max")
                            Text("• Beats Fit Pro, Studio Pro")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)

                        Text("片耳装着でも利用可能です。外音取り込みモードの使用を推奨します。")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .padding(.top, 4)
                    }

                case .connectedUnsupported:
                    Text("接続されたヘッドホンはモーション機能に対応していません。対応機種に変更してください。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                default:
                    EmptyView()
                }
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Control Buttons Card

struct ControlButtonsCard: View {
    @ObservedObject var viewModel: MotionViewModel

    var body: some View {
        VStack(spacing: 16) {
            // メインボタン
            HStack(spacing: 20) {
                Button(action: {
                    viewModel.toggleRecording()
                }) {
                    HStack {
                        Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "play.circle.fill")
                            .font(.title2)
                        Text(viewModel.isRecording ? "停止" : "開始")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(viewModel.isRecording ? Color.red : Color.green)
                    .cornerRadius(25)
                }
                .disabled(!canToggleRecording)

                Button(action: {
                    viewModel.calibrateZeroPosition()
                }) {
                    HStack {
                        Image(systemName: "scope")
                            .font(.title2)
                        Text("校正")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(25)
                }
                .disabled(viewModel.currentMotionData == nil)

                Button(action: {
                    viewModel.toggleAudioSystem()
                }) {
                    HStack {
                        Image(systemName: viewModel.isAudioEnabled ? "speaker.wave.3.fill" : "speaker.slash")
                            .font(.title2)
                        Text(viewModel.isAudioEnabled ? "音響ON" : "音響OFF")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(viewModel.isAudioEnabled ? Color.green : Color.gray)
                    .cornerRadius(25)
                }
            }

            // セカンダリボタン
            HStack(spacing: 12) {
                Button("データクリア") {
                    viewModel.clearHistory()
                }
                .font(.subheadline)
                .foregroundColor(.red)

                Spacer()

                Button("データ出力") {
                    // TODO: CSV出力機能
                }
                .font(.subheadline)
                .foregroundColor(.blue)
                .disabled(viewModel.motionDataHistory.isEmpty)
            }
            .padding(.horizontal)

            // 方向音テスト（音響が有効な場合のみ表示）
            if viewModel.isAudioEnabled {
                HStack(spacing: 8) {
                    ForEach(DirectionCue.allCases, id: \.rawValue) { cue in
                        Button(action: {
                            viewModel.playDirectionCue(cue, urgency: .mid)
                        }) {
                            VStack(spacing: 2) {
                                Image(systemName: iconForCue(cue))
                                    .font(.caption)
                                Text(String(cue.description.prefix(2)))
                                    .font(.caption2)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color(.tertiarySystemBackground))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var canToggleRecording: Bool {
        // 権限が拒否されていない、かつ対応デバイスが接続されていれば押せるように
        viewModel.authorizationState != .denied &&
        viewModel.connectionState.isMotionAvailable
    }

    private func iconForCue(_ cue: DirectionCue) -> String {
        switch cue {
        case .right: return "arrow.turn.up.right"
        case .left: return "arrow.turn.up.left"
        case .straight: return "arrow.up"
        case .caution: return "exclamationmark.triangle"
        }
    }
}

// MARK: - Real Time Data Card

struct RealTimeDataCard: View {
    @ObservedObject var viewModel: MotionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("リアルタイムデータ")
                .font(.headline)

            // 姿勢データ
            AttitudeDisplay(data: viewModel.attitudeDisplayData)

            Divider()

            // 回転データ
            RotationDisplay(data: viewModel.rotationDisplayData)

            Divider()

            // 加速度データ
            AccelerationDisplay(data: viewModel.accelerationDisplayData)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Attitude Display

struct AttitudeDisplay: View {
    let data: AttitudeDisplayData

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("姿勢 (Attitude)")
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack {
                DataValue(label: "Roll", value: data.formattedRoll, color: .red)
                Spacer()
                DataValue(label: "Pitch", value: data.formattedPitch, color: .green)
                Spacer()
                DataValue(label: "Yaw", value: data.formattedYaw, color: .blue)
            }
        }
    }
}

// MARK: - Rotation Display

struct RotationDisplay: View {
    let data: RotationDisplayData

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("回転率 (Rotation Rate)")
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack {
                DataValue(label: "合成", value: data.formattedMagnitude, color: .purple)
                Spacer()
            }
        }
    }
}

// MARK: - Acceleration Display

struct AccelerationDisplay: View {
    let data: AccelerationDisplayData

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("加速度 (Acceleration)")
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack {
                DataValue(label: "ユーザー", value: data.userAccelerationMagnitude, color: .orange)
                Spacer()
                DataValue(label: "重力", value: data.gravityMagnitude, color: .gray)
                Spacer()
            }
        }
    }
}

// MARK: - Data Value

struct DataValue: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
                .foregroundColor(color)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Recent Events Card

struct RecentEventsCard: View {
    @ObservedObject var viewModel: MotionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近のイベント")
                .font(.headline)

            LazyVStack(spacing: 8) {
                ForEach(viewModel.recentMotionEvents.suffix(5), id: \.id) { event in
                    HStack {
                        Image(systemName: iconForEvent(event.event))
                            .foregroundColor(colorForEvent(event.event))

                        Text(event.event.description)
                            .font(.subheadline)

                        Spacer()

                        Text(String(format: "%.1f%%", event.confidence * 100))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func iconForEvent(_ event: MotionEvent) -> String {
        switch event {
        case .lookingDown: return "arrow.down.circle"
        case .lookingUp: return "arrow.up.circle"
        case .headShake: return "arrow.left.and.right.circle"
        case .headNod: return "arrow.up.and.down.circle"
        case .suddenMovement: return "exclamationmark.circle"
        }
    }

    private func colorForEvent(_ event: MotionEvent) -> Color {
        switch event {
        case .lookingDown: return .red
        case .lookingUp: return .green
        case .headShake: return .blue
        case .headNod: return .purple
        case .suddenMovement: return .orange
        }
    }
}

// MARK: - Placeholder Views



// MARK: - Supporting Views

struct SessionStatsCard: View {
    @ObservedObject var viewModel: MotionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("セッション統計")
                .font(.headline)

            if viewModel.sessionStats.startTime != nil {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("継続時間:")
                        Spacer()
                        Text(viewModel.sessionStats.formattedDuration)
                    }

                    HStack {
                        Text("データポイント:")
                        Spacer()
                        Text("\(viewModel.sessionStats.totalDataPoints)")
                    }

                    HStack {
                        Text("更新レート:")
                        Spacer()
                        Text(viewModel.sessionStats.formattedUpdateRate)
                    }

                    HStack {
                        Text("イベント:")
                        Spacer()
                        Text("\(viewModel.sessionStats.totalEvents)")
                    }
                }
                .font(.subheadline)
            } else {
                Text("セッション未開始")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct ProcessingStatsCard: View {
    @ObservedObject var viewModel: MotionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("処理統計")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("フィルタリング:")
                    Spacer()
                    Text("有効") // TODO: Get from viewModel
                        .foregroundColor(.green)
                }

                HStack {
                    Text("検出イベント:")
                    Spacer()
                    Text("\(viewModel.recentMotionEvents.count)")
                        .foregroundColor(.blue)
                }

                HStack {
                    Text("データバッファ:")
                    Spacer()
                    Text("\(viewModel.motionDataHistory.count)/300")
                        .foregroundColor(.orange)
                }
            }
            .font(.subheadline)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

#Preview {
    ContentView()
}
