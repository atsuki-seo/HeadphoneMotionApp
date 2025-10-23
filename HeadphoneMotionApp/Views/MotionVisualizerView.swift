//
//  MotionVisualizerView.swift
//  HeadphoneMotionApp
//
//  Created by atsuki.seo on 2025/10/23.
//

import SwiftUI

// MARK: - Real Time Line Chart

/// リアルタイム折れ線グラフ
struct RealTimeLineChart: View {
    let data: [MotionData]
    let valueKeyPath: KeyPath<MotionData, Double>
    let title: String
    let color: Color
    let range: ClosedRange<Double>
    let maxDataPoints: Int

    init(data: [MotionData],
         valueKeyPath: KeyPath<MotionData, Double>,
         title: String,
         color: Color,
         range: ClosedRange<Double> = -180...180,
         maxDataPoints: Int = 60) {
        self.data = data
        self.valueKeyPath = valueKeyPath
        self.title = title
        self.color = color
        self.range = range
        self.maxDataPoints = maxDataPoints
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(color)

            ZStack {
                // 背景グリッド
                GridBackground(range: range)

                // データライン
                if !data.isEmpty {
                    DataLine(data: data.suffix(maxDataPoints),
                           valueKeyPath: valueKeyPath,
                           color: color,
                           range: range)
                }

                // 中央線（ゼロライン）
                Rectangle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(height: 1)
            }
            .frame(height: 80)
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(8)
        }
    }
}

// MARK: - Grid Background

struct GridBackground: View {
    let range: ClosedRange<Double>

    var body: some View {
        Canvas { context, size in
            let gridColor = Color.secondary.opacity(0.3)

            // 水平線
            for i in 0...4 {
                let y = size.height * CGFloat(i) / 4
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                    },
                    with: .color(gridColor),
                    lineWidth: 0.5
                )
            }

            // 垂直線
            for i in 0...5 {
                let x = size.width * CGFloat(i) / 5
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                    },
                    with: .color(gridColor),
                    lineWidth: 0.5
                )
            }
        }
    }
}

// MARK: - Data Line

struct DataLine: View {
    let data: Array<MotionData>.SubSequence
    let valueKeyPath: KeyPath<MotionData, Double>
    let color: Color
    let range: ClosedRange<Double>

    var body: some View {
        Canvas { context, size in
            guard data.count > 1 else { return }

            let path = createPath(size: size)

            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func createPath(size: CGSize) -> Path {
        Path { path in
            let dataArray = Array(data)

            for (index, motionData) in dataArray.enumerated() {
                let value = motionData[keyPath: valueKeyPath]
                let normalizedValue = normalizeValue(value)

                let x = size.width * CGFloat(index) / CGFloat(dataArray.count - 1)
                let y = size.height * (1.0 - normalizedValue)

                let point = CGPoint(x: x, y: y)

                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
        }
    }

    private func normalizeValue(_ value: Double) -> CGFloat {
        let normalizedValue = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return CGFloat(max(0, min(1, normalizedValue)))
    }
}

// MARK: - 3D Attitude Visualizer

/// 3D姿勢ビジュアライザー
struct AttitudeVisualizer3D: View {
    let attitudeData: AttitudeDisplayData
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 16) {
            Text("3D姿勢")
                .font(.headline)

            ZStack {
                // 背景円
                Circle()
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                    .frame(width: 150, height: 150)

                // 中心点
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 4, height: 4)

                // ヘッドアイコン（回転）
                HeadIcon()
                    .rotationEffect(.degrees(attitudeData.yaw))
                    .offset(x: CGFloat(attitudeData.roll * 50 / 180),
                            y: CGFloat(-attitudeData.pitch * 50 / 180))
                    .animation(.easeInOut(duration: 0.1), value: attitudeData.roll)
                    .animation(.easeInOut(duration: 0.1), value: attitudeData.pitch)
                    .animation(.easeInOut(duration: 0.1), value: attitudeData.yaw)

                // 角度表示
                VStack {
                    Spacer()
                    HStack {
                        AngleDisplay(label: "R", value: attitudeData.formattedRoll, color: .red)
                        Spacer()
                        AngleDisplay(label: "P", value: attitudeData.formattedPitch, color: .green)
                        Spacer()
                        AngleDisplay(label: "Y", value: attitudeData.formattedYaw, color: .blue)
                    }
                    .padding(.horizontal)
                }
            }
            .frame(height: 200)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Head Icon

struct HeadIcon: View {
    var body: some View {
        ZStack {
            // 頭部（楕円）
            Ellipse()
                .fill(Color.blue.opacity(0.7))
                .frame(width: 30, height: 40)

            // 顔の向き（小さな円）
            Circle()
                .fill(Color.white)
                .frame(width: 8, height: 8)
                .offset(y: -8)
        }
    }
}

// MARK: - Angle Display

struct AngleDisplay: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
    }
}

// MARK: - Multi-Line Chart

/// 複数ライン表示チャート
struct MultiLineChart: View {
    let data: [MotionData]
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            if data.isEmpty {
                EmptyChartView()
            } else {
                VStack(spacing: 8) {
                    // Roll
                    RealTimeLineChart(
                        data: data,
                        valueKeyPath: \.attitude.rollDegrees,
                        title: "Roll",
                        color: .red,
                        range: -90...90
                    )

                    // Pitch
                    RealTimeLineChart(
                        data: data,
                        valueKeyPath: \.attitude.pitchDegrees,
                        title: "Pitch",
                        color: .green,
                        range: -90...90
                    )

                    // Yaw
                    RealTimeLineChart(
                        data: data,
                        valueKeyPath: \.attitude.yawDegrees,
                        title: "Yaw",
                        color: .blue,
                        range: -180...180
                    )
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Empty Chart View

struct EmptyChartView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.title)
                .foregroundColor(.secondary)
            Text("データなし")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(height: 100)
        .frame(maxWidth: .infinity)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(8)
    }
}

// MARK: - Rotation Rate Visualizer

/// 回転率ビジュアライザー
struct RotationRateVisualizer: View {
    let rotationData: RotationDisplayData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("回転率")
                .font(.headline)

            HStack(spacing: 20) {
                // X軸回転
                RotationBar(
                    label: "Pitch",
                    value: rotationData.x,
                    color: .red,
                    maxValue: 5.0
                )

                // Y軸回転
                RotationBar(
                    label: "Roll",
                    value: rotationData.y,
                    color: .green,
                    maxValue: 5.0
                )

                // Z軸回転
                RotationBar(
                    label: "Yaw",
                    value: rotationData.z,
                    color: .blue,
                    maxValue: 5.0
                )
            }

            // 合成値
            HStack {
                Text("合成:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(rotationData.formattedMagnitude)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.purple)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Rotation Bar

struct RotationBar: View {
    let label: String
    let value: Double
    let color: Color
    let maxValue: Double

    var body: some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(color)

            ZStack(alignment: .bottom) {
                // 背景バー
                Rectangle()
                    .fill(Color(.tertiarySystemBackground))
                    .frame(width: 20, height: 60)
                    .cornerRadius(10)

                // 値バー
                Rectangle()
                    .fill(color)
                    .frame(width: 20, height: CGFloat(abs(value) / maxValue * 60))
                    .cornerRadius(10)
                    .scaleEffect(y: value < 0 ? -1 : 1, anchor: .bottom)
            }

            Text(String(format: "%.1f", value))
                .font(.caption2)
                .foregroundColor(color)
        }
    }
}

// MARK: - Acceleration Visualizer

/// 加速度ビジュアライザー
struct AccelerationVisualizer: View {
    let accelerationData: AccelerationDisplayData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("加速度")
                .font(.headline)

            HStack(spacing: 30) {
                // ユーザー加速度
                AccelerationSphere(
                    title: "ユーザー",
                    acceleration: accelerationData.userAcceleration,
                    color: .orange
                )

                // 重力
                AccelerationSphere(
                    title: "重力",
                    acceleration: accelerationData.gravity,
                    color: .gray
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Acceleration Sphere

struct AccelerationSphere: View {
    let title: String
    let acceleration: AccelerationData
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(color)

            ZStack {
                // 背景円
                Circle()
                    .stroke(color.opacity(0.3), lineWidth: 2)
                    .frame(width: 80, height: 80)

                // 加速度ベクトル表示
                VectorIndicator(
                    x: acceleration.x,
                    y: acceleration.y,
                    color: color
                )
            }

            Text(String(format: "%.2fg", acceleration.magnitude))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
    }
}

// MARK: - Vector Indicator

struct VectorIndicator: View {
    let x: Double
    let y: Double
    let color: Color
    let maxValue: Double = 2.0

    var body: some View {
        ZStack {
            // 中心点
            Circle()
                .fill(color)
                .frame(width: 4, height: 4)

            // ベクトル線
            if abs(x) > 0.01 || abs(y) > 0.01 {
                Path { path in
                    path.move(to: CGPoint(x: 40, y: 40))
                    path.addLine(to: CGPoint(
                        x: 40 + CGFloat(x / maxValue * 30),
                        y: 40 - CGFloat(y / maxValue * 30)
                    ))
                }
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))

                // 矢印
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .offset(
                        x: CGFloat(x / maxValue * 30),
                        y: CGFloat(-y / maxValue * 30)
                    )
            }
        }
        .frame(width: 80, height: 80)
    }
}