//
//  HeadphoneMotionManager.swift
//  HeadphoneMotionApp
//
//  Created by atsuki.seo on 2025/10/23.
//

import Foundation
import CoreMotion
import Combine

/// CMHeadphoneMotionManagerのラッパークラス
/// 権限管理、接続状態監視、データ取得、エラーハンドリングを統合管理
@MainActor
class HeadphoneMotionManager: ObservableObject {

    // MARK: - Published Properties

    @Published var connectionState: HeadphoneConnectionState = .disconnected
    @Published var authorizationState: MotionAuthorizationState = .notDetermined
    @Published var updateState: MotionUpdateState = .stopped
    @Published var latestMotionData: MotionData?
    @Published var errorMessage: String?
    @Published var isCalibrating: Bool = false

    // MARK: - Core Motion

    private let motionManager: CMHeadphoneMotionManager
    private let operationQueue: OperationQueue
    private let audioRouteMonitor: AudioRouteMonitor

    // MARK: - State Management

    private var lastMotionData: MotionData?
    private var calibrationOffset: AttitudeData?
    private var retryCount: Int = 0
    private var maxRetryCount: Int = 5
    private var retryTask: Task<Void, Never>?

    // MARK: - Data Processing

    private var motionDataBuffer: [MotionData] = []
    private let bufferSize: Int = 100
    private let dataProcessor = MotionDataProcessor()

    // MARK: - Publishers

    private let motionDataSubject = PassthroughSubject<MotionData, Never>()
    private let motionEventSubject = PassthroughSubject<DetectedMotionEvent, Never>()

    var motionDataPublisher: AnyPublisher<MotionData, Never> {
        motionDataSubject.eraseToAnyPublisher()
    }

    var motionEventPublisher: AnyPublisher<DetectedMotionEvent, Never> {
        motionEventSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    init() {
        self.motionManager = CMHeadphoneMotionManager()
        self.audioRouteMonitor = AudioRouteMonitor()

        // 専用キューの設定（メインキュー回避で低遅延化）
        self.operationQueue = OperationQueue()
        self.operationQueue.name = "HeadphoneMotionQueue"
        self.operationQueue.maxConcurrentOperationCount = 1
        self.operationQueue.qualityOfService = .userInteractive

        updateAuthorizationState()
        updateConnectionState()
    }

    deinit {
        retryTask?.cancel()

        // deinit内ではTaskを使わずに直接停止処理を行う
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
    }

    // MARK: - Public Interface

    /// モーション更新を開始
    func startMotionUpdates() {
        Task { @MainActor in
            // 権限が未決定の場合は、最初に権限要求を行う
            if authorizationState == .notDetermined {
                print("🔐 Requesting headphone motion permission...")
                await requestMotionPermission()
            }

            guard canStartMotionUpdates() else {
                handleStartError(HeadphoneMotionError.notAvailable)
                return
            }

            updateState = .starting
            errorMessage = nil
            retryCount = 0

            await performStartMotionUpdates()
        }
    }

    /// モーション権限を要求
    private func requestMotionPermission() async {
        // CMHeadphoneMotionManagerを一時的に作成して権限要求
        let tempManager = CMHeadphoneMotionManager()
        tempManager.startDeviceMotionUpdates(to: OperationQueue()) { _, _ in }

        // 少し待ってから停止して権限状態を更新
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
        tempManager.stopDeviceMotionUpdates()

        // 権限状態を再確認
        updateAuthorizationState()
    }

    /// モーション更新を停止
    func stopMotionUpdates() {
        retryTask?.cancel()
        retryTask = nil

        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }

        updateState = .stopped
        latestMotionData = nil
        motionDataBuffer.removeAll()
    }

    /// ゼロ校正実行
    func calibrateZeroPosition() {
        guard latestMotionData != nil else { return }

        isCalibrating = true

        // 数百ms待って安定化
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self,
                  let stableData = self.latestMotionData else { return }

            self.calibrationOffset = stableData.attitude
            self.isCalibrating = false
        }
    }

    /// 手動で接続状態を再チェック
    func refreshConnectionState() {
        updateConnectionState()
        updateAuthorizationState()
    }

    /// データ処理設定にアクセス
    var processingSettings: MotionDataProcessor {
        return dataProcessor
    }

    // MARK: - Private Implementation

    private func canStartMotionUpdates() -> Bool {
        return authorizationState != .denied &&
               connectionState.isMotionAvailable &&
               !motionManager.isDeviceMotionActive
    }

    private func performStartMotionUpdates() async {
        motionManager.startDeviceMotionUpdates(to: operationQueue) { [weak self] motion, error in
            Task { @MainActor in
                await self?.handleMotionUpdate(motion: motion, error: error)
            }
        }

        // 少し待ってから状態確認
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        if motionManager.isDeviceMotionActive {
            updateState = .active
            retryCount = 0
        } else {
            handleStartError(HeadphoneMotionError.startFailed)
        }
    }

    private func handleMotionUpdate(motion: CMDeviceMotion?, error: Error?) async {
        if let error = error {
            handleMotionError(error)
            return
        }

        guard let motion = motion else {
            handleMotionError(HeadphoneMotionError.noData)
            return
        }

        // 前回データとの時間差計算
        let deltaTime = lastMotionData?.timestamp != nil ?
            motion.timestamp - lastMotionData!.timestamp : nil

        // MotionDataオブジェクト作成
        let motionData = MotionData(from: motion, deltaTime: deltaTime)

        // キャリブレーション適用
        let calibratedData = applyCalibration(to: motionData)

        // データ処理・フィルタリング・イベント検出
        let (processedData, detectedEvents) = dataProcessor.processMotionData(calibratedData)

        // データ更新
        latestMotionData = processedData
        lastMotionData = motionData

        // バッファ管理
        motionDataBuffer.append(processedData)
        if motionDataBuffer.count > bufferSize {
            motionDataBuffer.removeFirst()
        }

        // パブリッシュ
        motionDataSubject.send(processedData)

        // イベントをパブリッシュ
        for event in detectedEvents {
            motionEventSubject.send(event)
        }
    }

    private func applyCalibration(to data: MotionData) -> MotionData {
        guard let offset = calibrationOffset else { return data }

        // 簡易的なオフセット補正（実際の実装では回転行列を使用）
        let adjustedAttitude = AttitudeData(
            roll: data.attitude.roll - offset.roll,
            pitch: data.attitude.pitch - offset.pitch,
            yaw: data.attitude.yaw - offset.yaw
        )

        // データをコピーして姿勢のみ更新
        return MotionData(
            timestamp: data.timestamp,
            attitude: adjustedAttitude,
            rotationRate: data.rotationRate,
            userAcceleration: data.userAcceleration,
            gravity: data.gravity,
            receivedAt: data.receivedAt,
            deltaTime: data.deltaTime
        )
    }


    private func handleStartError(_ error: Error) {
        updateState = .error(error)
        errorMessage = error.localizedDescription

        // 自動再試行
        if retryCount < maxRetryCount {
            scheduleRetry()
        }
    }

    private func handleMotionError(_ error: Error) {
        updateState = .error(error)
        errorMessage = error.localizedDescription

        // 連続エラーの場合は再試行
        if retryCount < maxRetryCount {
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        retryCount += 1
        let delay = min(pow(2.0, Double(retryCount)), 30.0) // 指数バックオフ（最大30秒）

        retryTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            guard !Task.isCancelled else { return }

            await MainActor.run {
                if self.canStartMotionUpdates() {
                    Task {
                        await self.performStartMotionUpdates()
                    }
                }
            }
        }
    }

    private func updateAuthorizationState() {
        let status = CMHeadphoneMotionManager.authorizationStatus()
        print("🔐 updateAuthorizationState() - CMHeadphoneMotionManager.authorizationStatus: \(status)")

        switch status {
        case .authorized:
            authorizationState = .authorized
            print("  → Setting authorizationState to: authorized")
        case .denied, .restricted:
            authorizationState = .denied
            print("  → Setting authorizationState to: denied")
        case .notDetermined:
            authorizationState = .notDetermined
            print("  → Setting authorizationState to: notDetermined")
        @unknown default:
            authorizationState = .notDetermined
            print("  → Setting authorizationState to: notDetermined (unknown)")
        }
    }

    private func updateConnectionState() {
        // AudioRouteMonitorの状態を確認
        print("🎧 updateConnectionState()")
        print("  - isHeadphonesConnected: \(audioRouteMonitor.isHeadphonesConnected)")
        print("  - potentiallySupportsMotion: \(audioRouteMonitor.potentiallySupportsMotion)")
        print("  - connectedHeadphoneType: \(audioRouteMonitor.connectedHeadphoneType)")
        print("  - isDeviceMotionAvailable: \(motionManager.isDeviceMotionAvailable)")

        if audioRouteMonitor.isHeadphonesConnected && audioRouteMonitor.potentiallySupportsMotion {
            // モーション対応ヘッドホンが接続されている場合
            if motionManager.isDeviceMotionAvailable {
                connectionState = .connectedMotionAvailable
                print("  → Setting state to: connectedMotionAvailable")
            } else {
                connectionState = .connectedUnsupported
                print("  → Setting state to: connectedUnsupported (motion not available)")
            }
        } else if audioRouteMonitor.isHeadphonesConnected {
            // ヘッドホンは接続されているがモーション非対応
            connectionState = .connectedUnsupported
            print("  → Setting state to: connectedUnsupported (non-motion headphones)")
        } else {
            // ヘッドホンが接続されていない
            connectionState = .disconnected
            print("  → Setting state to: disconnected")
        }
    }
}

// MARK: - MotionData Extension for Calibration

extension MotionData {
    init(timestamp: TimeInterval, attitude: AttitudeData, rotationRate: RotationData,
         userAcceleration: AccelerationData, gravity: AccelerationData,
         receivedAt: Date, deltaTime: TimeInterval?) {
        self.timestamp = timestamp
        self.attitude = attitude
        self.rotationRate = rotationRate
        self.userAcceleration = userAcceleration
        self.gravity = gravity
        self.receivedAt = receivedAt
        self.deltaTime = deltaTime
    }
}

// MARK: - Error Types

enum HeadphoneMotionError: LocalizedError {
    case notAvailable
    case permissionDenied
    case startFailed
    case noData
    case connectionLost

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "ヘッドホンモーションが利用できません"
        case .permissionDenied:
            return "モーション権限が拒否されています"
        case .startFailed:
            return "モーション更新の開始に失敗しました"
        case .noData:
            return "モーションデータを取得できません"
        case .connectionLost:
            return "ヘッドホンとの接続が失われました"
        }
    }
}
