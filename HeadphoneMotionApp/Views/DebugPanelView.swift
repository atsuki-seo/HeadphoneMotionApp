//
//  DebugPanelView.swift
//  HeadphoneMotionApp
//
//  Created by atsuki.seo on 2025/10/23.
//

import SwiftUI

// MARK: - Enhanced Debug View

struct EnhancedDebugView: View {
    @ObservedObject var viewModel: MotionViewModel
    @State private var selectedTab = 0

    var body: some View {
        NavigationView {
            VStack {
                // Tab selector
                Picker("Debug Mode", selection: $selectedTab) {
                    Text("概要").tag(0)
                    Text("グラフ").tag(1)
                    Text("Raw Data").tag(2)
                    Text("イベント").tag(3)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()

                // Content based on selected tab
                TabView(selection: $selectedTab) {
                    OverviewDebugView(viewModel: viewModel)
                        .tag(0)

                    GraphDebugView(viewModel: viewModel)
                        .tag(1)

                    RawDataDebugView(viewModel: viewModel)
                        .tag(2)

                    EventDebugView(viewModel: viewModel)
                        .tag(3)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            }
            .navigationTitle("デバッグ")
        }
    }
}

// MARK: - Overview Debug View

struct OverviewDebugView: View {
    @ObservedObject var viewModel: MotionViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // システム状態
                SystemStatusCard(viewModel: viewModel)

                // セッション統計
                SessionStatsCard(viewModel: viewModel)

                // 処理統計
                ProcessingStatsCard(viewModel: viewModel)

                // 現在の値
                if let currentData = viewModel.currentMotionData {
                    CurrentValuesCard(data: currentData)
                }
            }
            .padding()
        }
    }
}

// MARK: - Graph Debug View

struct GraphDebugView: View {
    @ObservedObject var viewModel: MotionViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 姿勢データ履歴グラフ
                MultiLineChart(data: viewModel.motionDataHistory, title: "姿勢データ履歴")

                // 回転率グラフ
                RotationRateChart(data: viewModel.motionDataHistory)

                // 加速度グラフ
                AccelerationChart(data: viewModel.motionDataHistory)
            }
            .padding()
        }
    }
}

// MARK: - Raw Data Debug View

struct RawDataDebugView: View {
    @ObservedObject var viewModel: MotionViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: HorizontalAlignment.leading, spacing: 16) {
                if let currentData = viewModel.currentMotionData {
                    RawDataDisplay(data: currentData)
                } else {
                    Text("データなし")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Divider()

                Text("最近のデータ (\(min(viewModel.motionDataHistory.count, 10))件)")
                    .font(.headline)

                LazyVStack(spacing: 8) {
                    ForEach(viewModel.motionDataHistory.suffix(10), id: \.id) { data in
                        CompactDataRow(data: data)
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Event Debug View

struct EventDebugView: View {
    @ObservedObject var viewModel: MotionViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: HorizontalAlignment.leading, spacing: 16) {
                // イベント統計
                EventStatisticsCard(viewModel: viewModel)

                // 最近のイベント
                Text("最近のイベント")
                    .font(.headline)

                if viewModel.recentMotionEvents.isEmpty {
                    Text("イベントなし")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.recentMotionEvents, id: \.id) { event in
                            DetailedEventRow(event: event)
                        }
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - System Status Card

struct SystemStatusCard: View {
    @ObservedObject var viewModel: MotionViewModel

    var body: some View {
        VStack(alignment: HorizontalAlignment.leading, spacing: 12) {
            Text("システム状態")
                .font(.headline)

            VStack(alignment: HorizontalAlignment.leading, spacing: 8) {
                StatusRow(
                    label: "接続状態",
                    value: viewModel.connectionState.description,
                    color: connectionColor
                )

                StatusRow(
                    label: "権限状態",
                    value: viewModel.authorizationState.description,
                    color: authorizationColor
                )

                StatusRow(
                    label: "更新状態",
                    value: viewModel.updateState.description,
                    color: updateColor
                )

                StatusRow(
                    label: "記録状態",
                    value: viewModel.isRecording ? "記録中" : "停止中",
                    color: viewModel.isRecording ? .green : .gray
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var connectionColor: Color {
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

    private var updateColor: Color {
        switch viewModel.updateState {
        case .stopped: return .gray
        case .starting: return .orange
        case .active: return .green
        case .error: return .red
        }
    }
}

// MARK: - Status Row

struct StatusRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.primary)
            Spacer()
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(value)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Current Values Card

struct CurrentValuesCard: View {
    let data: MotionData

    var body: some View {
        VStack(alignment: HorizontalAlignment.leading, spacing: 12) {
            Text("現在の値")
                .font(.headline)

            VStack(alignment: HorizontalAlignment.leading, spacing: 8) {
                Text("姿勢 (度)")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                HStack {
                    ValueDisplay(label: "Roll", value: data.attitude.rollDegrees, unit: "°", color: .red)
                    Spacer()
                    ValueDisplay(label: "Pitch", value: data.attitude.pitchDegrees, unit: "°", color: .green)
                    Spacer()
                    ValueDisplay(label: "Yaw", value: data.attitude.yawDegrees, unit: "°", color: .blue)
                }

                Divider()

                Text("回転率 (rad/s)")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                HStack {
                    ValueDisplay(label: "X", value: data.rotationRate.x, unit: "rad/s", color: .red)
                    Spacer()
                    ValueDisplay(label: "Y", value: data.rotationRate.y, unit: "rad/s", color: .green)
                    Spacer()
                    ValueDisplay(label: "Z", value: data.rotationRate.z, unit: "rad/s", color: .blue)
                }

                Divider()

                Text("加速度 (g)")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                VStack(alignment: HorizontalAlignment.leading, spacing: 4) {
                    HStack {
                        Text("ユーザー:")
                        Spacer()
                        Text(String(format: "%.3f g", data.userAcceleration.magnitude))
                            .foregroundColor(.orange)
                    }
                    HStack {
                        Text("重力:")
                        Spacer()
                        Text(String(format: "%.3f g", data.gravity.magnitude))
                            .foregroundColor(.gray)
                    }
                }
                .font(.caption)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Value Display

struct ValueDisplay: View {
    let label: String
    let value: Double
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(String(format: "%.2f", value))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(color)
            Text(unit)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Raw Data Display

struct RawDataDisplay: View {
    let data: MotionData

    var body: some View {
        VStack(alignment: HorizontalAlignment.leading, spacing: 12) {
            Text("Raw Data")
                .font(.headline)

            VStack(alignment: HorizontalAlignment.leading, spacing: 8) {
                Text("Timestamp: \(String(format: "%.3f", data.timestamp))")
                Text("Received: \(formatDate(data.receivedAt))")
                if let deltaTime = data.deltaTime {
                    Text("Delta: \(String(format: "%.3f", deltaTime)) s")
                }
            }
            .font(.caption.monospaced())
            .foregroundColor(Color.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Attitude (rad):")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("  roll: \(String(format: "%.6f", data.attitude.roll))")
                Text("  pitch: \(String(format: "%.6f", data.attitude.pitch))")
                Text("  yaw: \(String(format: "%.6f", data.attitude.yaw))")
            }
            .font(.caption)
            .font(.caption.monospaced())

            VStack(alignment: .leading, spacing: 4) {
                Text("Rotation Rate (rad/s):")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("  x: \(String(format: "%.6f", data.rotationRate.x))")
                Text("  y: \(String(format: "%.6f", data.rotationRate.y))")
                Text("  z: \(String(format: "%.6f", data.rotationRate.z))")
            }
            .font(.caption)
            .font(.caption.monospaced())

            VStack(alignment: .leading, spacing: 4) {
                Text("User Acceleration (g):")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("  x: \(String(format: "%.6f", data.userAcceleration.x))")
                Text("  y: \(String(format: "%.6f", data.userAcceleration.y))")
                Text("  z: \(String(format: "%.6f", data.userAcceleration.z))")
            }
            .font(.caption)
            .font(.caption.monospaced())

            VStack(alignment: .leading, spacing: 4) {
                Text("Gravity (g):")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("  x: \(String(format: "%.6f", data.gravity.x))")
                Text("  y: \(String(format: "%.6f", data.gravity.y))")
                Text("  z: \(String(format: "%.6f", data.gravity.z))")
            }
            .font(.caption)
            .font(.caption.monospaced())
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Compact Data Row

struct CompactDataRow: View {
    let data: MotionData

    var body: some View {
        HStack {
            Text(String(format: "%.1f", data.timestamp))
                .font(.caption.monospaced())
                .frame(width: 60, alignment: Alignment.leading)

            VStack(alignment: HorizontalAlignment.leading, spacing: 2) {
                Text("R:\(String(format: "%.1f°", data.attitude.rollDegrees))")
                Text("P:\(String(format: "%.1f°", data.attitude.pitchDegrees))")
            }
            .font(.caption2)
            .font(.caption.monospaced())

            Spacer()

            Text(String(format: "%.2f", data.rotationRate.magnitude))
                .font(.caption)
                .font(.caption.monospaced())
                .foregroundColor(.blue)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(6)
    }
}

// MARK: - Event Statistics Card

struct EventStatisticsCard: View {
    @ObservedObject var viewModel: MotionViewModel

    var body: some View {
        VStack(alignment: HorizontalAlignment.leading, spacing: 12) {
            Text("イベント統計")
                .font(.headline)

            VStack(alignment: HorizontalAlignment.leading, spacing: 8) {
                HStack {
                    Text("総イベント数")
                    Spacer()
                    Text("\(viewModel.sessionStats.totalEvents)")
                        .foregroundColor(.blue)
                }

                ForEach(MotionEvent.allCases, id: \.self) { event in
                    HStack {
                        Text(event.description)
                        Spacer()
                        Text("\(viewModel.sessionStats.eventCounts[event] ?? 0)")
                            .foregroundColor(.secondary)
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Detailed Event Row

struct DetailedEventRow: View {
    let event: DetectedMotionEvent

    var body: some View {
        VStack(alignment: HorizontalAlignment.leading, spacing: 8) {
            HStack {
                Text(event.event.description)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text(String(format: "%.1f%%", event.confidence * 100))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
            }

            HStack {
                Text("時刻: \(formatTimestamp(event.timestamp))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("姿勢: \(String(format: "%.1f°", event.motionData.attitude.pitchDegrees))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(8)
    }

    private func formatTimestamp(_ timestamp: TimeInterval) -> String {
        let date = Date(timeIntervalSinceReferenceDate: timestamp)
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Additional Chart Views

struct RotationRateChart: View {
    let data: [MotionData]

    var body: some View {
        VStack(alignment: HorizontalAlignment.leading, spacing: 8) {
            Text("回転率履歴")
                .font(.headline)

            VStack(spacing: 8) {
                RealTimeLineChart(
                    data: data,
                    valueKeyPath: \.rotationRate.x,
                    title: "Pitch Rate (X)",
                    color: .red,
                    range: -5...5
                )

                RealTimeLineChart(
                    data: data,
                    valueKeyPath: \.rotationRate.y,
                    title: "Roll Rate (Y)",
                    color: .green,
                    range: -5...5
                )

                RealTimeLineChart(
                    data: data,
                    valueKeyPath: \.rotationRate.z,
                    title: "Yaw Rate (Z)",
                    color: .blue,
                    range: -5...5
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct AccelerationChart: View {
    let data: [MotionData]

    var body: some View {
        VStack(alignment: HorizontalAlignment.leading, spacing: 8) {
            Text("加速度履歴")
                .font(.headline)

            VStack(spacing: 8) {
                RealTimeLineChart(
                    data: data,
                    valueKeyPath: \.userAcceleration.magnitude,
                    title: "User Acceleration Magnitude",
                    color: .orange,
                    range: 0...2
                )

                RealTimeLineChart(
                    data: data,
                    valueKeyPath: \.gravity.magnitude,
                    title: "Gravity Magnitude",
                    color: .gray,
                    range: 0.5...1.5
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}