//
//  MotionViewModel.swift
//  HeadphoneMotionApp
//
//  Created by atsuki.seo on 2025/10/23.
//

import Foundation
import SwiftUI
import Combine
import AVFoundation
import Accelerate

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

    // MARK: - Audio System

    @Published var isAudioEnabled: Bool = false
    @Published var audioVolume: Float = -10.0  // -10dB初期値
    @Published var lastPlayedCue: String = ""

    private var audioService: DirectionAudioServiceTest?

    // MARK: - Statistics

    @Published var sessionStats: SessionStatistics = SessionStatistics()

    // MARK: - Initialization

    init() {
        // 音響サービス初期化
        setupAudioService()

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

    // MARK: - Audio Controls

    /// 音響システムの開始
    func startAudioSystem() {
        guard let audioService = audioService else { return }

        do {
            try audioService.startEngine()
            isAudioEnabled = true
            print("🎵 Audio system started")
        } catch {
            print("❌ Audio system start failed: \(error)")
            isAudioEnabled = false
        }
    }

    /// 音響システムの停止
    func stopAudioSystem() {
        audioService?.stopEngine()
        isAudioEnabled = false
        print("🔇 Audio system stopped")
    }

    /// 音響システムの開始/停止切り替え
    func toggleAudioSystem() {
        if isAudioEnabled {
            stopAudioSystem()
        } else {
            startAudioSystem()
        }
    }

    /// 方向音再生
    func playDirectionCue(_ cue: DirectionCue, distance: Double? = nil, urgency: Urgency = .mid) {
        guard isAudioEnabled else { return }

        audioService?.playCue(cue, distanceMeters: distance, urgency: urgency)
        lastPlayedCue = "\(cue.description) (\(urgency.description))"
    }

    /// 音量設定
    func setAudioVolume(_ db: Float) {
        audioVolume = db
        audioService?.setMasterVolume(db)
    }

    /// テスト用：全ての方向音を順次再生
    func playAllDirectionCues() {
        guard isAudioEnabled else {
            print("⚠️ Audio not enabled")
            return
        }

        Task { @MainActor in
            for (index, cue) in DirectionCue.allCases.enumerated() {
                if index > 0 {
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2秒間隔
                }
                playDirectionCue(cue, urgency: .mid)
            }
        }
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

    /// 音響サービスの初期化
    private func setupAudioService() {
        audioService = DirectionAudioServiceTest()
        print("🎧 Audio service initialized")
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

// MARK: - Direction Audio System (Integrated)

/// 方向音キューの種別
enum DirectionCue: String, CaseIterable {
    case right = "right"        // 右折
    case left = "left"          // 左折
    case straight = "straight"  // 直進
    case caution = "caution"    // 注意・減速

    var description: String {
        switch self {
        case .right: return "右折"
        case .left: return "左折"
        case .straight: return "直進"
        case .caution: return "注意・減速"
        }
    }
}

/// 緊急度レベル
enum Urgency: String, CaseIterable {
    case low = "low"
    case mid = "mid"
    case high = "high"

    var description: String {
        switch self {
        case .low: return "低"
        case .mid: return "中"
        case .high: return "高"
        }
    }
}

/// テスト用の簡易音響サービス
class DirectionAudioServiceTest: ObservableObject {

    // MARK: - Properties

    @Published var isEngineRunning: Bool = false
    @Published var isCueEnabled: Bool = true
    @Published var currentVolume: Float = -10.0

    private let audioEngine = AVAudioEngine()
    private let audioSession = AVAudioSession.sharedInstance()
    private let playerNode = AVAudioPlayerNode()

    // MARK: - 簡易音響バッファ

    private var cueBuffers: [DirectionCue: AVAudioPCMBuffer] = [:]

    // MARK: - クールダウン管理

    private var lastPlayTime: Date = Date.distantPast
    private let cooldownDuration: TimeInterval = 1.0

    // MARK: - Initialization

    init() {
        setupAudioGraph()
    }

    deinit {
        stopEngine()
    }

    // MARK: - Public Interface

    func startEngine() throws {
        guard !isEngineRunning else { return }

        do {
            // AudioSession設定
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers, .allowBluetoothA2DP])
            try audioSession.setActive(true)

            // 音素材準備
            try loadSimpleCueBuffers()

            // エンジン開始
            try audioEngine.start()
            isEngineRunning = true

            print("🎵 Audio engine started")

        } catch {
            print("❌ Audio engine start failed: \(error)")
            throw error
        }
    }

    func stopEngine() {
        guard isEngineRunning else { return }

        if playerNode.isPlaying {
            playerNode.stop()
        }

        audioEngine.stop()
        isEngineRunning = false

        try? audioSession.setActive(false)

        print("🔇 Audio engine stopped")
    }

    func playCue(_ cue: DirectionCue, distanceMeters: Double? = nil, urgency: Urgency = .mid) {
        guard isEngineRunning && isCueEnabled else {
            print("⚠️ Cannot play cue: engine=\(isEngineRunning), enabled=\(isCueEnabled)")
            return
        }

        // 簡易クールダウンチェック
        let now = Date()
        let elapsed = now.timeIntervalSince(lastPlayTime)
        if elapsed < cooldownDuration {
            print("⏳ Cue in cooldown, skipping")
            return
        }

        lastPlayTime = now

        // 音の再生
        Task { @MainActor in
            await playSimpleCue(cue)
        }
    }

    func setMasterVolume(_ db: Float) {
        let clampedVolume = max(-24.0, min(0.0, db))
        currentVolume = clampedVolume

        // 簡易音量制御
        audioEngine.mainMixerNode.outputVolume = pow(10.0, clampedVolume / 20.0)

        print("🔊 Volume set to \(clampedVolume) dB")
    }

    // MARK: - Private Implementation

    private func setupAudioGraph() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!

        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)

        print("🔧 Simple audio graph configured")
    }

    private func loadSimpleCueBuffers() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!

        for cue in DirectionCue.allCases {
            let buffer = try generateSimpleCueBuffer(for: cue, format: format)
            cueBuffers[cue] = buffer
        }

        print("🎵 Loaded simple cue buffers")
    }

    private func generateSimpleCueBuffer(for cue: DirectionCue, format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let sampleRate = format.sampleRate
        let duration: TimeInterval
        let frequency: Float

        switch cue {
        case .right:
            duration = 0.12  // 120ms
            frequency = 1200.0
        case .left:
            duration = 0.12
            frequency = 900.0
        case .straight:
            duration = 0.09  // 90ms
            frequency = 600.0
        case .caution:
            duration = 0.25  // 250ms
            frequency = 400.0
        }

        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "AudioTest", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"])
        }

        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData?[0] else {
            throw NSError(domain: "AudioTest", code: -2, userInfo: [NSLocalizedDescriptionKey: "No channel data"])
        }

        // 簡易サイン波生成
        let phaseIncrement = Float(2.0 * Double.pi * Double(frequency) / sampleRate)

        for i in 0..<Int(frameCount) {
            let t = Float(i)
            let phase = phaseIncrement * t

            // エンベロープ付きサイン波
            let envelope = calculateSimpleEnvelope(frame: i, totalFrames: Int(frameCount))
            channelData[i] = 0.3 * sin(phase) * envelope
        }

        return buffer
    }

    private func calculateSimpleEnvelope(frame: Int, totalFrames: Int) -> Float {
        let normalizedPosition = Float(frame) / Float(totalFrames)

        if normalizedPosition < 0.1 {
            // アタック
            return normalizedPosition / 0.1
        } else if normalizedPosition < 0.9 {
            // サステイン
            return 1.0
        } else {
            // リリース
            return (1.0 - normalizedPosition) / 0.1
        }
    }

    private func playSimpleCue(_ cue: DirectionCue) async {
        guard let buffer = cueBuffers[cue] else {
            print("❌ No buffer for cue: \(cue.rawValue)")
            return
        }

        let repeatCount: Int
        switch cue {
        case .right: repeatCount = 3
        case .left: repeatCount = 2
        case .straight, .caution: repeatCount = 1
        }

        await MainActor.run {
            playerNode.stop()
        }

        for i in 0..<repeatCount {
            if i > 0 {
                // 間隔を空ける
                try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
            }

            if isEngineRunning && isCueEnabled {
                await MainActor.run {
                    playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)

                    if !playerNode.isPlaying {
                        playerNode.play()
                    }
                }
            }
        }

        print("✅ Played cue: \(cue.description)")
    }
}