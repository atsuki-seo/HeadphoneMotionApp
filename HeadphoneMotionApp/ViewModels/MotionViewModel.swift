//
//  MotionViewModel.swift
//  HeadphoneMotionApp
//
//  Created by atsuki.seo on 2025/10/23.
//

import Foundation
import SwiftUI
import Combine

/// SwiftUI用のMotionViewModel
/// HeadphoneMotionManagerとAudioRouteMonitorを統合し、UIに適した形でデータを提供
@MainActor
final class MotionViewModel: ObservableObject {

    // MARK: - Published UI State

    @Published var connectionState: HeadphoneConnectionState = .disconnected
    @Published var authorizationState: MotionAuthorizationState = .notDetermined
    @Published var updateState: MotionUpdateState = .stopped
    @Published var currentMotionData: MotionData?
    @Published var isRecording: Bool = false
    @Published var errorMessage: String?

    // MARK: - Audio Route State

    @Published var audioRoute: AudioRoute = .none
    @Published var headphoneType: HeadphoneType = .unknown
    @Published var headphoneDetails: HeadphoneDetails?

    // MARK: - Motion Events

    @Published var recentMotionEvents: [DetectedMotionEvent] = []
    private let maxEventHistory = 50

    // MARK: - Data History for Visualization

    @Published var motionDataHistory: [MotionData] = []
    private let maxHistoryCount = 300  // 約10秒分（30Hz想定）

    // MARK: - UI Formatting

    @Published var attitudeDisplayData: AttitudeDisplayData = AttitudeDisplayData()
    @Published var rotationDisplayData: RotationDisplayData = RotationDisplayData()
    @Published var accelerationDisplayData: AccelerationDisplayData = AccelerationDisplayData()

    // MARK: - Core Managers

    private let motionManager = HeadphoneMotionManager()
    private let audioRouteMonitor = AudioRouteMonitor()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Statistics

    @Published var sessionStats: SessionStatistics = SessionStatistics()

    // MARK: - Initialization

    init() {
        setupBindings()
        startInitialChecks()
    }

    // MARK: - Public Actions

    /// モーション記録開始/停止
    func toggleRecording() {
        print("🟡 toggleRecording() called - isRecording: \(isRecording)")
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    /// 記録開始
    func startRecording() {
        print("🔄 startRecording() called")
        print("  - authorizationState: \(authorizationState)")
        print("  - connectionState: \(connectionState)")
        print("  - isRecording: \(isRecording)")
        print("  - canStartRecording: \(canStartRecording())")

        guard canStartRecording() else {
            print("❌ Cannot start recording - conditions not met")
            return
        }

        print("✅ Starting motion updates...")
        motionManager.startMotionUpdates()
        isRecording = true
        sessionStats.startSession()
        errorMessage = nil
        print("✅ Recording started")
    }

    /// 記録停止
    func stopRecording() {
        motionManager.stopMotionUpdates()
        isRecording = false
        sessionStats.endSession()
    }

    /// ゼロ校正
    func calibrateZeroPosition() {
        motionManager.calibrateZeroPosition()
    }

    /// 接続状態の手動更新
    func refreshConnectionState() {
        audioRouteMonitor.refreshRouteInfo()
        motionManager.refreshConnectionState()
        updateConnectionState()
    }

    /// エラーメッセージクリア
    func clearError() {
        errorMessage = nil
    }

    /// データ履歴クリア
    func clearHistory() {
        motionDataHistory.removeAll()
        recentMotionEvents.removeAll()
        sessionStats.reset()
    }

    /// CSV形式でデータをエクスポート
    func exportDataAsCSV() -> String {
        var csv = "timestamp,roll,pitch,yaw,rotX,rotY,rotZ,accX,accY,accZ,gravX,gravY,gravZ\n"

        for data in motionDataHistory {
            csv += "\(data.timestamp),"
            csv += "\(data.attitude.roll),\(data.attitude.pitch),\(data.attitude.yaw),"
            csv += "\(data.rotationRate.x),\(data.rotationRate.y),\(data.rotationRate.z),"
            csv += "\(data.userAcceleration.x),\(data.userAcceleration.y),\(data.userAcceleration.z),"
            csv += "\(data.gravity.x),\(data.gravity.y),\(data.gravity.z)\n"
        }

        return csv
    }

    // MARK: - Private Implementation

    private func setupBindings() {
        // Motion Manager Bindings
        motionManager.$connectionState
            .assign(to: \.connectionState, on: self)
            .store(in: &cancellables)

        motionManager.$authorizationState
            .assign(to: \.authorizationState, on: self)
            .store(in: &cancellables)

        motionManager.$updateState
            .assign(to: \.updateState, on: self)
            .store(in: &cancellables)

        motionManager.$errorMessage
            .assign(to: \.errorMessage, on: self)
            .store(in: &cancellables)

        // Audio Route Monitor Bindings
        audioRouteMonitor.$currentRoute
            .assign(to: \.audioRoute, on: self)
            .store(in: &cancellables)

        audioRouteMonitor.$connectedHeadphoneType
            .assign(to: \.headphoneType, on: self)
            .store(in: &cancellables)

        // Motion Data Stream
        motionManager.motionDataPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] motionData in
                self?.handleNewMotionData(motionData)
            }
            .store(in: &cancellables)

        // Motion Events Stream
        motionManager.motionEventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleMotionEvent(event)
            }
            .store(in: &cancellables)

        // Audio Route Changes
        audioRouteMonitor.routeChangePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                self?.handleAudioRouteChange(change)
            }
            .store(in: &cancellables)
    }

    private func startInitialChecks() {
        refreshConnectionState()
        updateHeadphoneDetails()
    }

    private func canStartRecording() -> Bool {
        // デバッグ用: シミュレーターでもテストできるように条件を緩和
        #if targetEnvironment(simulator)
        return authorizationState != .denied && !isRecording
        #else
        return authorizationState != .denied &&
               connectionState.isMotionAvailable &&
               !isRecording
        #endif
    }

    private func handleNewMotionData(_ motionData: MotionData) {
        currentMotionData = motionData

        // 履歴管理
        motionDataHistory.append(motionData)
        if motionDataHistory.count > maxHistoryCount {
            motionDataHistory.removeFirst()
        }

        // 表示用データ更新
        updateDisplayData(motionData)

        // 統計更新
        sessionStats.addDataPoint(motionData)
    }

    private func handleMotionEvent(_ event: DetectedMotionEvent) {
        recentMotionEvents.append(event)
        if recentMotionEvents.count > maxEventHistory {
            recentMotionEvents.removeFirst()
        }

        sessionStats.addEvent(event)
    }

    private func handleAudioRouteChange(_ change: AudioRouteChange) {
        updateConnectionState()
        updateHeadphoneDetails()

        // 新しいモーション対応デバイスが接続された場合の自動処理
        if audioRouteMonitor.potentiallySupportsMotion && !isRecording {
            // 少し遅延して接続安定化を待つ
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.refreshConnectionState()
            }
        }
    }

    private func updateConnectionState() {
        // オーディオルート情報とモーション可用性を統合
        if audioRouteMonitor.potentiallySupportsMotion {
            // HeadphoneMotionManagerの状態で最終判定
            connectionState = motionManager.connectionState
        } else if audioRouteMonitor.isHeadphonesConnected {
            connectionState = .connectedUnsupported
        } else {
            connectionState = .disconnected
        }
    }

    private func updateHeadphoneDetails() {
        headphoneDetails = audioRouteMonitor.getHeadphoneDetails()
    }

    private func updateDisplayData(_ motionData: MotionData) {
        attitudeDisplayData = AttitudeDisplayData(
            roll: motionData.attitude.rollDegrees,
            pitch: motionData.attitude.pitchDegrees,
            yaw: motionData.attitude.yawDegrees
        )

        rotationDisplayData = RotationDisplayData(
            x: motionData.rotationRate.x,
            y: motionData.rotationRate.y,
            z: motionData.rotationRate.z,
            magnitude: motionData.rotationRate.magnitudeDegrees
        )

        accelerationDisplayData = AccelerationDisplayData(
            userAcceleration: motionData.userAcceleration,
            gravity: motionData.gravity
        )
    }
}

// MARK: - Display Data Structures

struct AttitudeDisplayData {
    let roll: Double
    let pitch: Double
    let yaw: Double

    init(roll: Double = 0, pitch: Double = 0, yaw: Double = 0) {
        self.roll = roll
        self.pitch = pitch
        self.yaw = yaw
    }

    var formattedRoll: String { String(format: "%.1f°", roll) }
    var formattedPitch: String { String(format: "%.1f°", pitch) }
    var formattedYaw: String { String(format: "%.1f°", yaw) }
}

struct RotationDisplayData {
    let x: Double
    let y: Double
    let z: Double
    let magnitude: Double

    init(x: Double = 0, y: Double = 0, z: Double = 0, magnitude: Double = 0) {
        self.x = x
        self.y = y
        self.z = z
        self.magnitude = magnitude
    }

    var formattedMagnitude: String { String(format: "%.1f°/s", magnitude) }
}

struct AccelerationDisplayData {
    let userAcceleration: AccelerationData
    let gravity: AccelerationData

    init(userAcceleration: AccelerationData = AccelerationData(x: 0, y: 0, z: 0),
         gravity: AccelerationData = AccelerationData(x: 0, y: 0, z: 0)) {
        self.userAcceleration = userAcceleration
        self.gravity = gravity
    }

    var userAccelerationMagnitude: String {
        String(format: "%.2fg", userAcceleration.magnitude)
    }

    var gravityMagnitude: String {
        String(format: "%.2fg", gravity.magnitude)
    }
}

// MARK: - Session Statistics

class SessionStatistics: ObservableObject {
    @Published var startTime: Date?
    @Published var duration: TimeInterval = 0
    @Published var totalDataPoints: Int = 0
    @Published var averageUpdateRate: Double = 0
    @Published var totalEvents: Int = 0
    @Published var eventCounts: [MotionEvent: Int] = [:]

    private var lastUpdateTime: Date?
    private var updateTimes: [TimeInterval] = []

    func startSession() {
        startTime = Date()
        reset()
    }

    func endSession() {
        if let start = startTime {
            duration = Date().timeIntervalSince(start)
        }
    }

    func addDataPoint(_ data: MotionData) {
        totalDataPoints += 1

        let now = Date()
        if let lastTime = lastUpdateTime {
            let interval = now.timeIntervalSince(lastTime)
            updateTimes.append(interval)

            // 直近100回の平均を計算
            if updateTimes.count > 100 {
                updateTimes.removeFirst()
            }

            averageUpdateRate = 1.0 / (updateTimes.reduce(0, +) / Double(updateTimes.count))
        }
        lastUpdateTime = now
    }

    func addEvent(_ event: DetectedMotionEvent) {
        totalEvents += 1
        eventCounts[event.event, default: 0] += 1
    }

    func reset() {
        totalDataPoints = 0
        averageUpdateRate = 0
        totalEvents = 0
        eventCounts.removeAll()
        updateTimes.removeAll()
        lastUpdateTime = nil
    }

    var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "0s"
    }

    var formattedUpdateRate: String {
        String(format: "%.1f Hz", averageUpdateRate)
    }
}