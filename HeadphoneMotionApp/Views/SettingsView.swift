//
//  SettingsView.swift
//  HeadphoneMotionApp
//
//  Created by atsuki.seo on 2025/10/23.
//

import SwiftUI

// MARK: - Enhanced Settings View

struct EnhancedSettingsView: View {
    @ObservedObject var viewModel: MotionViewModel
    @State private var showingExportSheet = false
    @State private var exportData = ""

    var body: some View {
        NavigationView {
            Form {
                // 基本設定セクション
                BasicSettingsSection(viewModel: viewModel)

                // フィルター設定
                FilterSettingsSection(viewModel: viewModel)

                // イベント検出設定
                EventDetectionSection(viewModel: viewModel)

                // データ管理
                DataManagementSection(
                    viewModel: viewModel,
                    showingExportSheet: $showingExportSheet,
                    exportData: $exportData
                )

                // デバイス情報
                DeviceInfoSection(viewModel: viewModel)

                // 開発・研究用設定
                DevelopmentSection(viewModel: viewModel)
            }
            .navigationTitle("設定")
            .sheet(isPresented: $showingExportSheet) {
                DataExportSheet(data: exportData)
            }
        }
    }
}

// MARK: - Basic Settings Section

struct BasicSettingsSection: View {
    @ObservedObject var viewModel: MotionViewModel

    var body: some View {
        Section("使用方法") {
            VStack(alignment: .leading, spacing: 8) {
                Label("外音取り込みモード推奨", systemImage: "ear")
                    .foregroundColor(.blue)
                Text("安全のため、外音取り込みモードでの使用を推奨します")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("片耳装着対応", systemImage: "headphones")
                    .foregroundColor(.green)
                Text("片耳装着でもモーション検出が可能です")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("安全注意", systemImage: "exclamationmark.triangle")
                    .foregroundColor(.orange)
                Text("走行中の音量は控えめに設定し、周囲の音に注意してください")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Filter Settings Section

struct FilterSettingsSection: View {
    @ObservedObject var viewModel: MotionViewModel

    var body: some View {
        Section("フィルター設定") {
            HStack {
                Text("フィルタリング有効")
                Spacer()
                Toggle("", isOn: .constant(true)) // TODO: Bind to actual setting
                    .disabled(true) // TODO: Enable when setting is exposed
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("姿勢データLPF")
                    .font(.subheadline)
                HStack {
                    Text("5 Hz")
                        .font(.caption)
                    Slider(value: .constant(8.0), in: 1...20)
                        .disabled(true) // TODO: Bind to actual setting
                    Text("20 Hz")
                        .font(.caption)
                }
                Text("現在: 8.0 Hz")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("メディアンフィルターサイズ")
                    .font(.subheadline)
                HStack {
                    Text("3")
                        .font(.caption)
                    Slider(value: .constant(5.0), in: 3...10, step: 1)
                        .disabled(true) // TODO: Bind to actual setting
                    Text("10")
                        .font(.caption)
                }
                Text("現在: 5")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Event Detection Section

struct EventDetectionSection: View {
    @ObservedObject var viewModel: MotionViewModel

    var body: some View {
        Section("イベント検出") {
            VStack(alignment: .leading, spacing: 8) {
                Text("下向き検出閾値")
                    .font(.subheadline)
                HStack {
                    Text("-60°")
                        .font(.caption)
                    Slider(value: .constant(-45.0), in: -60...0)
                        .disabled(true) // TODO: Bind to actual setting
                    Text("0°")
                        .font(.caption)
                }
                Text("現在: -45.0°")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("急激動作閾値")
                    .font(.subheadline)
                HStack {
                    Text("90°/s")
                        .font(.caption)
                    Slider(value: .constant(180.0), in: 90...360)
                        .disabled(true) // TODO: Bind to actual setting
                    Text("360°/s")
                        .font(.caption)
                }
                Text("現在: 180.0°/s")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("首振り検出閾値")
                    .font(.subheadline)
                HStack {
                    Text("60°/s")
                        .font(.caption)
                    Slider(value: .constant(120.0), in: 60...240)
                        .disabled(true) // TODO: Bind to actual setting
                    Text("240°/s")
                        .font(.caption)
                }
                Text("現在: 120.0°/s")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Data Management Section

struct DataManagementSection: View {
    @ObservedObject var viewModel: MotionViewModel
    @Binding var showingExportSheet: Bool
    @Binding var exportData: String

    var body: some View {
        Section("データ管理") {
            HStack {
                VStack(alignment: .leading) {
                    Text("データポイント")
                        .font(.subheadline)
                    Text("\(viewModel.motionDataHistory.count) / 300")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("クリア") {
                    viewModel.clearHistory()
                }
                .foregroundColor(.red)
            }

            HStack {
                VStack(alignment: .leading) {
                    Text("セッション時間")
                        .font(.subheadline)
                    Text(viewModel.sessionStats.formattedDuration)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("CSV出力") {
                    exportData = viewModel.exportDataAsCSV()
                    showingExportSheet = true
                }
                .disabled(viewModel.motionDataHistory.isEmpty)
            }

            Button(action: {
                viewModel.calibrateZeroPosition()
            }) {
                HStack {
                    Image(systemName: "scope")
                    Text("ゼロ校正実行")
                }
            }
            .disabled(viewModel.currentMotionData == nil)
        }
    }
}

// MARK: - Device Info Section

struct DeviceInfoSection: View {
    @ObservedObject var viewModel: MotionViewModel

    var body: some View {
        Section("デバイス情報") {
            if let details = viewModel.headphoneDetails {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("デバイス名")
                        Spacer()
                        Text(details.portName)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("種類")
                        Spacer()
                        Text(details.headphoneType.description)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("モーション対応")
                        Spacer()
                        HStack {
                            Text(details.estimatedMotionSupport ? "対応" : "非対応")
                                .foregroundColor(details.estimatedMotionSupport ? .green : .red)
                            Image(systemName: details.estimatedMotionSupport ? "checkmark.circle" : "xmark.circle")
                                .foregroundColor(details.estimatedMotionSupport ? .green : .red)
                        }
                    }

                    HStack {
                        Text("チャンネル数")
                        Spacer()
                        Text("\(details.channels)")
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                HStack {
                    Image(systemName: "headphones.circle")
                        .foregroundColor(.red)
                    Text("ヘッドホン未接続")
                        .foregroundColor(.secondary)
                }
            }

            // 接続状態
            HStack {
                Text("接続状態")
                Spacer()
                HStack {
                    Circle()
                        .fill(connectionStateColor)
                        .frame(width: 8, height: 8)
                    Text(viewModel.connectionState.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // 権限状態
            HStack {
                Text("モーション権限")
                Spacer()
                Text(viewModel.authorizationState.description)
                    .font(.caption)
                    .foregroundColor(authorizationColor)
            }
        }
    }

    private var connectionStateColor: Color {
        switch viewModel.connectionState {
        case .disconnected: return .red
        case .connected, .connectedUnsupported: return .orange
        case .connectedMotionAvailable: return .green
        }
    }

    private var authorizationColor: Color {
        switch viewModel.authorizationState {
        case .notDetermined: return .orange
        case .authorized: return .green
        case .denied: return .red
        }
    }
}

// MARK: - Development Section

struct DevelopmentSection: View {
    @ObservedObject var viewModel: MotionViewModel

    var body: some View {
        Section("開発・研究用") {
            HStack {
                Text("更新レート")
                Spacer()
                Text(viewModel.sessionStats.formattedUpdateRate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("総データポイント")
                Spacer()
                Text("\(viewModel.sessionStats.totalDataPoints)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("検出イベント数")
                Spacer()
                Text("\(viewModel.sessionStats.totalEvents)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            NavigationLink("詳細ログ") {
                DetailedLogView(viewModel: viewModel)
            }
        }
    }
}

// MARK: - Data Export Sheet

struct DataExportSheet: View {
    let data: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("CSV データ")
                        .font(.headline)

                    Text(data)
                        .font(.caption.monospaced())
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                }
                .padding()
            }
            .navigationTitle("データ出力")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("閉じる") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("共有") {
                        // TODO: Implement sharing
                    }
                }
            }
        }
    }
}

// MARK: - Detailed Log View

struct DetailedLogView: View {
    @ObservedObject var viewModel: MotionViewModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(viewModel.recentMotionEvents, id: \.id) { event in
                    EventLogRow(event: event)
                }
            }
            .padding()
        }
        .navigationTitle("イベントログ")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Event Log Row

struct EventLogRow: View {
    let event: DetectedMotionEvent

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(event.event.description)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(formatTimestamp(event.timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "%.1f%%", event.confidence * 100))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)

                Text("信頼度")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(6)
    }

    private func formatTimestamp(_ timestamp: TimeInterval) -> String {
        let date = Date(timeIntervalSinceReferenceDate: timestamp)
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}