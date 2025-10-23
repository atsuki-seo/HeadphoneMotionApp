//
//  MotionData.swift
//  HeadphoneMotionApp
//
//  Created by atsuki.seo on 2025/10/23.
//

import Foundation
import CoreMotion

/// ヘッドホンモーションデータを格納する構造体
/// CMDeviceMotionの情報を整理し、UIでの表示やデータ処理に適した形式で提供
struct MotionData: Identifiable, Hashable {
    let id = UUID()

    // MARK: - Core Motion Data

    /// タイムスタンプ（秒）
    let timestamp: TimeInterval

    /// 姿勢データ（ラジアン）
    let attitude: AttitudeData

    /// 回転率（rad/s）
    let rotationRate: RotationData

    /// ユーザー加速度（g）
    let userAcceleration: AccelerationData

    /// 重力ベクトル（g）
    let gravity: AccelerationData

    // MARK: - Derived Properties

    /// データ受信時刻
    let receivedAt: Date

    /// 前回データからの時間間隔
    let deltaTime: TimeInterval?

    init(from deviceMotion: CMDeviceMotion, deltaTime: TimeInterval? = nil) {
        self.timestamp = deviceMotion.timestamp
        self.receivedAt = Date()
        self.deltaTime = deltaTime

        // 姿勢データ
        self.attitude = AttitudeData(
            roll: deviceMotion.attitude.roll,
            pitch: deviceMotion.attitude.pitch,
            yaw: deviceMotion.attitude.yaw
        )

        // 回転率
        self.rotationRate = RotationData(
            x: deviceMotion.rotationRate.x,
            y: deviceMotion.rotationRate.y,
            z: deviceMotion.rotationRate.z
        )

        // ユーザー加速度
        self.userAcceleration = AccelerationData(
            x: deviceMotion.userAcceleration.x,
            y: deviceMotion.userAcceleration.y,
            z: deviceMotion.userAcceleration.z
        )

        // 重力
        self.gravity = AccelerationData(
            x: deviceMotion.gravity.x,
            y: deviceMotion.gravity.y,
            z: deviceMotion.gravity.z
        )
    }
}

// MARK: - Supporting Data Structures

/// 姿勢データ（roll/pitch/yaw）
struct AttitudeData: Hashable {
    /// ロール角（ラジアン）- 頭部の左右傾き
    let roll: Double

    /// ピッチ角（ラジアン）- 頭部の上下傾き
    let pitch: Double

    /// ヨー角（ラジアン）- 頭部の左右回転
    let yaw: Double

    // MARK: - Convenience Properties

    /// ロール角（度）
    var rollDegrees: Double { roll * 180.0 / .pi }

    /// ピッチ角（度）
    var pitchDegrees: Double { pitch * 180.0 / .pi }

    /// ヨー角（度）
    var yawDegrees: Double { yaw * 180.0 / .pi }

    /// 姿勢の大きさ（ラジアン）
    var magnitude: Double {
        sqrt(roll * roll + pitch * pitch + yaw * yaw)
    }
}

/// 回転データ（rad/s）
struct RotationData: Hashable {
    let x: Double  // ピッチ軸周り
    let y: Double  // ロール軸周り
    let z: Double  // ヨー軸周り

    /// 回転の大きさ（rad/s）
    var magnitude: Double {
        sqrt(x * x + y * y + z * z)
    }

    /// 回転の大きさ（degrees/s）
    var magnitudeDegrees: Double {
        magnitude * 180.0 / .pi
    }
}

/// 加速度データ（g）
struct AccelerationData: Hashable {
    let x: Double
    let y: Double
    let z: Double

    /// 加速度の大きさ（g）
    var magnitude: Double {
        sqrt(x * x + y * y + z * z)
    }
}

// MARK: - Motion Event Detection

/// 検出された動作イベント
enum MotionEvent: CaseIterable {
    case lookingDown      // 下向き
    case lookingUp        // 上向き
    case headShake        // 首振り
    case headNod          // うなずき
    case suddenMovement   // 急激な動き

    var description: String {
        switch self {
        case .lookingDown: return "下向き"
        case .lookingUp: return "上向き"
        case .headShake: return "首振り"
        case .headNod: return "うなずき"
        case .suddenMovement: return "急激な動き"
        }
    }
}

/// 動作イベント検出結果
struct DetectedMotionEvent: Identifiable {
    let id = UUID()
    let event: MotionEvent
    let timestamp: TimeInterval
    let confidence: Double  // 0.0 - 1.0
    let motionData: MotionData
}

// MARK: - Connection State

/// ヘッドホン接続状態
enum HeadphoneConnectionState {
    case disconnected              // 未接続
    case connected                // 接続済み
    case connectedUnsupported     // 接続済み（モーション非対応）
    case connectedMotionAvailable // 接続済み（モーション対応）

    var description: String {
        switch self {
        case .disconnected:
            return "ヘッドホン未接続"
        case .connected:
            return "ヘッドホン接続済み"
        case .connectedUnsupported:
            return "ヘッドホン接続済み（モーション非対応）"
        case .connectedMotionAvailable:
            return "ヘッドホン接続済み（モーション対応）"
        }
    }

    var isMotionAvailable: Bool {
        return self == .connectedMotionAvailable
    }
}

/// モーション権限状態
enum MotionAuthorizationState {
    case notDetermined
    case authorized
    case denied

    var description: String {
        switch self {
        case .notDetermined: return "権限未確認"
        case .authorized: return "権限許可済み"
        case .denied: return "権限拒否"
        }
    }
}

/// モーション更新状態
enum MotionUpdateState {
    case stopped
    case starting
    case active
    case error(Error)

    var description: String {
        switch self {
        case .stopped: return "停止中"
        case .starting: return "開始中"
        case .active: return "更新中"
        case .error(let error): return "エラー: \(error.localizedDescription)"
        }
    }
}