//
//  Filters.swift
//  HeadphoneMotionApp
//
//  Created by atsuki.seo on 2025/10/23.
//

import Foundation
import Combine

// MARK: - Low Pass Filter

/// 低域通過フィルター（姿勢データの安定化用）
/// カットオフ周波数を指定してノイズを除去
class LowPassFilter {
    private let alpha: Double
    private var lastOutput: Double?

    /// イニシャライザ
    /// - Parameters:
    ///   - cutoffFrequency: カットオフ周波数 (Hz)
    ///   - sampleRate: サンプリングレート (Hz)
    init(cutoffFrequency: Double, sampleRate: Double = 30.0) {
        let rc = 1.0 / (2.0 * .pi * cutoffFrequency)
        let dt = 1.0 / sampleRate
        self.alpha = dt / (rc + dt)
    }

    /// フィルター適用
    func apply(_ input: Double) -> Double {
        if let last = lastOutput {
            let output = alpha * input + (1.0 - alpha) * last
            lastOutput = output
            return output
        } else {
            lastOutput = input
            return input
        }
    }

    /// フィルター状態リセット
    func reset() {
        lastOutput = nil
    }
}

// MARK: - Median Filter

/// メディアンフィルター（スパイク除去用）
class MedianFilter {
    private var buffer: [Double]
    private let windowSize: Int

    init(windowSize: Int = 5) {
        self.windowSize = windowSize
        self.buffer = []
    }

    func apply(_ input: Double) -> Double {
        buffer.append(input)

        if buffer.count > windowSize {
            buffer.removeFirst()
        }

        return buffer.sorted()[buffer.count / 2]
    }

    func reset() {
        buffer.removeAll()
    }
}

// MARK: - Motion Data Processor

/// モーションデータの総合処理クラス
/// フィルタリング、イベント検出、キャリブレーションを統合
class MotionDataProcessor: ObservableObject {

    // MARK: - Filter Settings

    @Published var attitudeLPFCutoff: Double = 8.0  // 姿勢用LPF (Hz)
    @Published var rotationMedianWindow: Int = 5    // 回転用メディアンフィルター
    @Published var accelerationMedianWindow: Int = 3 // 加速度用メディアンフィルター
    @Published var isFilteringEnabled: Bool = true

    // MARK: - Event Detection Settings

    @Published var lookingDownThreshold: Double = -45.0  // 下向き検出閾値 (度)
    @Published var lookingUpThreshold: Double = 30.0     // 上向き検出閾値 (度)
    @Published var rapidMotionThreshold: Double = 180.0  // 急激動作閾値 (度/秒)
    @Published var headShakeThreshold: Double = 120.0    // 首振り検出閾値 (度/秒)

    // MARK: - Filters

    private var rollLPF: LowPassFilter
    private var pitchLPF: LowPassFilter
    private var yawLPF: LowPassFilter

    private var rotationXMedian: MedianFilter
    private var rotationYMedian: MedianFilter
    private var rotationZMedian: MedianFilter

    private var accelXMedian: MedianFilter
    private var accelYMedian: MedianFilter
    private var accelZMedian: MedianFilter

    // MARK: - Event Detection State

    private var eventDetectionHistory: [MotionData] = []
    private let historySize = 30  // 約1秒分の履歴
    private var lastEventTime: [MotionEvent: TimeInterval] = [:]
    private let eventCooldownTime: TimeInterval = 1.0  // イベント間最小間隔

    // MARK: - Statistics

    @Published var processingStats: ProcessingStatistics = ProcessingStatistics()

    // MARK: - Initialization

    init() {
        // Low Pass Filters for Attitude
        self.rollLPF = LowPassFilter(cutoffFrequency: 8.0)
        self.pitchLPF = LowPassFilter(cutoffFrequency: 8.0)
        self.yawLPF = LowPassFilter(cutoffFrequency: 8.0)

        // Median Filters for Rotation
        self.rotationXMedian = MedianFilter(windowSize: 5)
        self.rotationYMedian = MedianFilter(windowSize: 5)
        self.rotationZMedian = MedianFilter(windowSize: 5)

        // Median Filters for Acceleration
        self.accelXMedian = MedianFilter(windowSize: 3)
        self.accelYMedian = MedianFilter(windowSize: 3)
        self.accelZMedian = MedianFilter(windowSize: 3)
    }

    // MARK: - Main Processing Function

    /// メインの処理関数：フィルタリングとイベント検出を実行
    func processMotionData(_ data: MotionData) -> (filteredData: MotionData, events: [DetectedMotionEvent]) {
        let startTime = CFAbsoluteTimeGetCurrent()

        // フィルタリング実行
        let filteredData = isFilteringEnabled ? applyFilters(to: data) : data

        // 履歴更新
        updateHistory(filteredData)

        // イベント検出
        let events = detectEvents(from: filteredData)

        // 統計更新
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        processingStats.addProcessingTime(processingTime)

        return (filteredData, events)
    }

    // MARK: - Filtering

    private func applyFilters(to data: MotionData) -> MotionData {
        // 姿勢データのLPF適用
        let filteredRoll = rollLPF.apply(data.attitude.roll)
        let filteredPitch = pitchLPF.apply(data.attitude.pitch)
        let filteredYaw = yawLPF.apply(data.attitude.yaw)

        let filteredAttitude = AttitudeData(
            roll: filteredRoll,
            pitch: filteredPitch,
            yaw: filteredYaw
        )

        // 回転データのメディアンフィルター適用
        let filteredRotX = rotationXMedian.apply(data.rotationRate.x)
        let filteredRotY = rotationYMedian.apply(data.rotationRate.y)
        let filteredRotZ = rotationZMedian.apply(data.rotationRate.z)

        let filteredRotation = RotationData(
            x: filteredRotX,
            y: filteredRotY,
            z: filteredRotZ
        )

        // 加速度データのメディアンフィルター適用
        let filteredAccelX = accelXMedian.apply(data.userAcceleration.x)
        let filteredAccelY = accelYMedian.apply(data.userAcceleration.y)
        let filteredAccelZ = accelZMedian.apply(data.userAcceleration.z)

        let filteredAcceleration = AccelerationData(
            x: filteredAccelX,
            y: filteredAccelY,
            z: filteredAccelZ
        )

        // フィルター適用済みデータを作成
        return MotionData(
            timestamp: data.timestamp,
            attitude: filteredAttitude,
            rotationRate: filteredRotation,
            userAcceleration: filteredAcceleration,
            gravity: data.gravity,  // 重力はフィルターしない
            receivedAt: data.receivedAt,
            deltaTime: data.deltaTime
        )
    }

    // MARK: - Event Detection

    private func updateHistory(_ data: MotionData) {
        eventDetectionHistory.append(data)
        if eventDetectionHistory.count > historySize {
            eventDetectionHistory.removeFirst()
        }
    }

    private func detectEvents(from data: MotionData) -> [DetectedMotionEvent] {
        var detectedEvents: [DetectedMotionEvent] = []

        // 下向き検出
        if let lookingDownEvent = detectLookingDown(data) {
            detectedEvents.append(lookingDownEvent)
        }

        // 上向き検出
        if let lookingUpEvent = detectLookingUp(data) {
            detectedEvents.append(lookingUpEvent)
        }

        // 急激な動き検出
        if let rapidMotionEvent = detectRapidMotion(data) {
            detectedEvents.append(rapidMotionEvent)
        }

        // 首振り検出
        if let headShakeEvent = detectHeadShake() {
            detectedEvents.append(headShakeEvent)
        }

        // うなずき検出
        if let headNodEvent = detectHeadNod() {
            detectedEvents.append(headNodEvent)
        }

        return detectedEvents.filter { canEmitEvent($0.event, at: data.timestamp) }
    }

    private func detectLookingDown(_ data: MotionData) -> DetectedMotionEvent? {
        let pitchDegrees = data.attitude.pitchDegrees

        if pitchDegrees < lookingDownThreshold {
            let confidence = min(abs(pitchDegrees - lookingDownThreshold) / abs(lookingDownThreshold), 1.0)

            return DetectedMotionEvent(
                event: .lookingDown,
                timestamp: data.timestamp,
                confidence: confidence,
                motionData: data
            )
        }

        return nil
    }

    private func detectLookingUp(_ data: MotionData) -> DetectedMotionEvent? {
        let pitchDegrees = data.attitude.pitchDegrees

        if pitchDegrees > lookingUpThreshold {
            let confidence = min(pitchDegrees / lookingUpThreshold, 1.0)

            return DetectedMotionEvent(
                event: .lookingUp,
                timestamp: data.timestamp,
                confidence: confidence,
                motionData: data
            )
        }

        return nil
    }

    private func detectRapidMotion(_ data: MotionData) -> DetectedMotionEvent? {
        let rotationMagnitude = data.rotationRate.magnitudeDegrees

        if rotationMagnitude > rapidMotionThreshold {
            let confidence = min(rotationMagnitude / (rapidMotionThreshold * 2.0), 1.0)

            return DetectedMotionEvent(
                event: .suddenMovement,
                timestamp: data.timestamp,
                confidence: confidence,
                motionData: data
            )
        }

        return nil
    }

    private func detectHeadShake() -> DetectedMotionEvent? {
        guard eventDetectionHistory.count >= 10 else { return nil }

        let recent = eventDetectionHistory.suffix(10)
        var maxYawRate: Double = 0
        var alternatingCount = 0
        var lastSign: Int = 0

        for data in recent {
            let yawRate = data.rotationRate.z
            maxYawRate = max(maxYawRate, abs(yawRate))

            let currentSign = yawRate > 0 ? 1 : -1
            if lastSign != 0 && currentSign != lastSign {
                alternatingCount += 1
            }
            lastSign = currentSign
        }

        // 一定以上の回転率かつ交互の動きを検出
        if maxYawRate * 180.0 / .pi > headShakeThreshold && alternatingCount >= 3 {
            let confidence = min(maxYawRate * 180.0 / .pi / (headShakeThreshold * 2.0), 1.0)

            return DetectedMotionEvent(
                event: .headShake,
                timestamp: recent.last!.timestamp,
                confidence: confidence,
                motionData: recent.last!
            )
        }

        return nil
    }

    private func detectHeadNod() -> DetectedMotionEvent? {
        guard eventDetectionHistory.count >= 10 else { return nil }

        let recent = eventDetectionHistory.suffix(10)
        var maxPitchRate: Double = 0
        var alternatingCount = 0
        var lastSign: Int = 0

        for data in recent {
            let pitchRate = data.rotationRate.x
            maxPitchRate = max(maxPitchRate, abs(pitchRate))

            let currentSign = pitchRate > 0 ? 1 : -1
            if lastSign != 0 && currentSign != lastSign {
                alternatingCount += 1
            }
            lastSign = currentSign
        }

        // うなずき動作の検出
        if maxPitchRate * 180.0 / .pi > 90.0 && alternatingCount >= 2 {
            let confidence = min(maxPitchRate * 180.0 / .pi / 180.0, 1.0)

            return DetectedMotionEvent(
                event: .headNod,
                timestamp: recent.last!.timestamp,
                confidence: confidence,
                motionData: recent.last!
            )
        }

        return nil
    }

    private func canEmitEvent(_ event: MotionEvent, at timestamp: TimeInterval) -> Bool {
        if let lastTime = lastEventTime[event] {
            let timeSinceLastEvent = timestamp - lastTime
            if timeSinceLastEvent < eventCooldownTime {
                return false
            }
        }

        lastEventTime[event] = timestamp
        return true
    }

    // MARK: - Filter Configuration

    /// フィルター設定を更新
    func updateFilterSettings() {
        // LPFの再初期化
        rollLPF = LowPassFilter(cutoffFrequency: self.attitudeLPFCutoff)
        pitchLPF = LowPassFilter(cutoffFrequency: self.attitudeLPFCutoff)
        yawLPF = LowPassFilter(cutoffFrequency: self.attitudeLPFCutoff)

        // メディアンフィルターの再初期化
        rotationXMedian = MedianFilter(windowSize: self.rotationMedianWindow)
        rotationYMedian = MedianFilter(windowSize: self.rotationMedianWindow)
        rotationZMedian = MedianFilter(windowSize: self.rotationMedianWindow)

        accelXMedian = MedianFilter(windowSize: self.accelerationMedianWindow)
        accelYMedian = MedianFilter(windowSize: self.accelerationMedianWindow)
        accelZMedian = MedianFilter(windowSize: self.accelerationMedianWindow)
    }

    /// フィルター状態をリセット
    func resetFilters() {
        rollLPF.reset()
        pitchLPF.reset()
        yawLPF.reset()

        rotationXMedian.reset()
        rotationYMedian.reset()
        rotationZMedian.reset()

        accelXMedian.reset()
        accelYMedian.reset()
        accelZMedian.reset()

        eventDetectionHistory.removeAll()
        lastEventTime.removeAll()
        processingStats.reset()
    }
}

// MARK: - Processing Statistics

class ProcessingStatistics: ObservableObject {
    @Published var averageProcessingTime: Double = 0.0
    @Published var maxProcessingTime: Double = 0.0
    @Published var totalProcessedSamples: Int = 0

    private var processingTimes: [Double] = []
    private let maxSamples = 100

    func addProcessingTime(_ time: Double) {
        processingTimes.append(time)
        totalProcessedSamples += 1

        if processingTimes.count > maxSamples {
            processingTimes.removeFirst()
        }

        averageProcessingTime = processingTimes.reduce(0, +) / Double(processingTimes.count)
        maxProcessingTime = max(maxProcessingTime, time)
    }

    func reset() {
        processingTimes.removeAll()
        averageProcessingTime = 0.0
        maxProcessingTime = 0.0
        totalProcessedSamples = 0
    }

    var formattedAverageTime: String {
        String(format: "%.2f ms", averageProcessingTime * 1000)
    }

    var formattedMaxTime: String {
        String(format: "%.2f ms", maxProcessingTime * 1000)
    }
}