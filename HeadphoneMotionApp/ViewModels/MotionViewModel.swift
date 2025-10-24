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

/// 音響波形の種別（仕様書対応）
enum WaveType {
    case sine                // 純粋なサイン波（左折用）
    case sineWithNoise      // 薄いサイン波+ノイズ（右折用）
    case click              // 短クリック（直進用）
    case bandLimitedNoise   // 帯域制限ノイズ（注意用）
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
            // AudioSession設定 (AirPods Pro互換)
            // Note: .allowBluetoothA2DPオプションはAirPods Proで Code -50 エラーを引き起こすため除外
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
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

        // 音の再生（注意音の場合はダッキング併用）
        Task { @MainActor in
            await playAdvancedCue(cue)
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
        // ステレオ対応（左右定位のため2チャンネル必須）
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!

        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)

        print("🔧 Stereo audio graph configured (2ch for spatial audio)")
    }

    private func loadSimpleCueBuffers() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!

        for cue in DirectionCue.allCases {
            let buffer = try generateSimpleCueBuffer(for: cue, format: format)
            cueBuffers[cue] = buffer
        }

        print("🎵 Loaded simple cue buffers")
    }

    private func generateSimpleCueBuffer(for cue: DirectionCue, format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let sampleRate = format.sampleRate
        let channelCount = Int(format.channelCount)

        // 片耳使用に特化した明確区別設定
        let duration: TimeInterval
        let frequency: Float        // 直接周波数指定（明確な差のため）
        let waveType: WaveType

        switch cue {
        case .right:
            duration = 0.12           // 120ms
            frequency = 1400.0        // 高音域（緊急性を感じる）
            waveType = .sineWithNoise // 鋭いクリック系

        case .left:
            duration = 0.12           // 120ms
            frequency = 500.0         // 低音域（落ち着いた音）
            waveType = .sine          // 柔らかいトーン系

        case .straight:
            duration = 0.09           // 90ms
            frequency = 700.0         // 中音域（ニュートラル）
            waveType = .click         // 短クリック

        case .caution:
            duration = 0.25           // 250ms
            frequency = 300.0         // 超低音域（注意喚起）
            waveType = .bandLimitedNoise // 帯域制限ノイズ
        }

        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "AudioTest", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"])
        }

        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData else {
            throw NSError(domain: "AudioTest", code: -2, userInfo: [NSLocalizedDescriptionKey: "No channel data"])
        }

        // 片耳使用に特化：モノラル出力（明確性重視で音量アップ）
        let masterVolume: Float = 0.4  // 基本音量を0.2→0.4に増加（明確性重視）

        // 全チャンネルに同じ音響を出力（モノラル）
        for ch in 0..<channelCount {
            for i in 0..<Int(frameCount) {
                let t = Float(i)
                let normalizedTime = t / Float(frameCount)
                let envelope = calculateAdvancedEnvelope(frame: i, totalFrames: Int(frameCount), waveType: waveType)

                let sample = generateWaveform(
                    waveType: waveType,
                    time: t,
                    frequency: frequency,
                    sampleRate: Float(sampleRate),
                    normalizedTime: normalizedTime
                )

                channelData[ch][i] = sample * envelope * masterVolume
            }
        }

        return buffer
    }

    /// 各波形タイプに応じた波形生成
    private func generateWaveform(waveType: WaveType, time: Float, frequency: Float, sampleRate: Float, normalizedTime: Float) -> Float {
        let phase = 2.0 * Float.pi * frequency * time / sampleRate

        switch waveType {
        case .sine:
            // 純粋なサイン波（左折用）
            return sin(phase)

        case .sineWithNoise:
            // 右折用：鋭いクリック系（明確な識別のため）
            let sineComponent = sin(phase) * 0.6
            let highFreqNoise = sin(phase * 3.0) * 0.2  // 高周波成分追加
            let whiteNoise = Float.random(in: -1...1) * 0.3
            return sineComponent + highFreqNoise + whiteNoise

        case .click:
            // 短クリック（直進用） - 立ち上がりの鋭い短い波形
            if normalizedTime < 0.3 {
                return sin(phase * 4.0) * exp(-normalizedTime * 8.0)
            } else {
                return 0.0
            }

        case .bandLimitedNoise:
            // 帯域制限ノイズ（注意用） - 低域フィルタ適用ノイズ
            let noise = Float.random(in: -1...1)
            // 簡易ローパスフィルタ効果
            let cutoffPhase = 2.0 * Float.pi * frequency * 0.5 * time / sampleRate
            let filterResponse = sin(cutoffPhase) * 0.7 + cos(cutoffPhase) * 0.3
            return noise * filterResponse
        }
    }

    /// 片耳用に特化した音響特性強化エンベロープ
    private func calculateAdvancedEnvelope(frame: Int, totalFrames: Int, waveType: WaveType) -> Float {
        let normalizedPosition = Float(frame) / Float(totalFrames)

        switch waveType {
        case .sineWithNoise:
            // 右折用：鋭い立ち上がり、短い減衰（注意喚起的）
            if normalizedPosition < 0.05 {
                return normalizedPosition / 0.05  // 超高速アタック（5%）
            } else if normalizedPosition < 0.3 {
                return 1.0  // 短いサステイン（30%まで）
            } else {
                // 急速な減衰（70%を使って減衰）
                return exp(-(normalizedPosition - 0.3) * 8.0)
            }

        case .sine:
            // 左折用：緩やかな立ち上がり、長い減衰（安定感）
            if normalizedPosition < 0.15 {
                return normalizedPosition / 0.15  // ゆっくりアタック（15%）
            } else if normalizedPosition < 0.6 {
                return 1.0  // 長いサステイン（60%まで）
            } else {
                // ゆっくりとした減衰
                return (1.0 - normalizedPosition) / 0.4
            }

        case .click:
            // 直進用：急激な立ち上がりと急速な減衰
            return exp(-normalizedPosition * 6.0)

        case .bandLimitedNoise:
            // 注意用：強めの立ち上がりと持続
            if normalizedPosition < 0.1 {
                return normalizedPosition / 0.1  // 標準アタック
            } else if normalizedPosition < 0.85 {
                return 1.0  // 長いサステイン（85%まで）
            } else {
                return (1.0 - normalizedPosition) / 0.15  // 短いリリース
            }
        }
    }

    /// 仕様書準拠の高度な音響再生（ダッキング対応）
    private func playAdvancedCue(_ cue: DirectionCue) async {
        guard let buffer = cueBuffers[cue] else {
            print("❌ No buffer for cue: \(cue.rawValue)")
            return
        }

        // 注意音の場合はダッキング開始
        let shouldDuck = (cue == .caution)
        if shouldDuck {
            await enableDucking()
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
                // 片耳用明確リズムパターン
                let intervalMs: UInt64
                switch cue {
                case .right:
                    intervalMs = 100_000_000 // 100ms（速いテンポ「タタタ」）
                case .left:
                    intervalMs = 200_000_000 // 200ms（ゆったりテンポ「ター、ター」）
                default:
                    intervalMs = 150_000_000 // その他150ms
                }
                try? await Task.sleep(nanoseconds: intervalMs)
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

        // 注意音の場合は再生後にダッキング解除
        if shouldDuck {
            // 音響終了を待つ
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms待機
            await disableDucking()
        }

        // 片耳用詳細ログ
        let cueDetails = getCueDetails(for: cue)
        print("✅ 片耳用再生: \(cue.description)")
        print("   - 周波数: \(cueDetails.frequency)Hz (\(cueDetails.freqDescription))")
        print("   - リズム: \(cueDetails.rhythm)")
        print("   - 音響特性: \(cueDetails.acoustic)")
        if shouldDuck {
            print("   - ダッキング有効")
        }
    }

    /// ダッキング有効化（注意音時に他の音を下げる）
    private func enableDucking() async {
        do {
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
            print("🔇 Ducking enabled")
        } catch {
            print("⚠️ Failed to enable ducking: \(error)")
        }
    }

    /// ダッキング無効化（通常状態に戻す）
    private func disableDucking() async {
        do {
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            print("🔊 Ducking disabled")
        } catch {
            print("⚠️ Failed to disable ducking: \(error)")
        }
    }

    /// 各キューの詳細情報（デバッグ用）
    private func getCueDetails(for cue: DirectionCue) -> (frequency: Float, freqDescription: String, rhythm: String, acoustic: String) {
        switch cue {
        case .right:
            return (
                frequency: 1400.0,
                freqDescription: "高音域・緊急性",
                rhythm: "速いテンポ 3回×100ms「タタタ」",
                acoustic: "鋭いクリック系・超高速アタック"
            )
        case .left:
            return (
                frequency: 500.0,
                freqDescription: "低音域・安定感",
                rhythm: "ゆったりテンポ 2回×200ms「ター、ター」",
                acoustic: "柔らかいトーン・緩やかアタック"
            )
        case .straight:
            return (
                frequency: 700.0,
                freqDescription: "中音域・ニュートラル",
                rhythm: "単発",
                acoustic: "短クリック・急速減衰"
            )
        case .caution:
            return (
                frequency: 300.0,
                freqDescription: "超低音域・注意喚起",
                rhythm: "単発",
                acoustic: "帯域制限ノイズ・長持続"
            )
        }
    }
}
