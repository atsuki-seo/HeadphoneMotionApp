//
//  AudioRouteMonitor.swift
//  HeadphoneMotionApp
//
//  Created by atsuki.seo on 2025/10/23.
//

import Foundation
import AVFoundation
import Combine

/// オーディオルート変更を監視し、ヘッドホンの接続状態を追跡するクラス
/// AVAudioSession.routeChangeNotificationを監視して接続状態変化を検出
@MainActor
class AudioRouteMonitor: ObservableObject {

    // MARK: - Published Properties

    @Published var currentRoute: AudioRoute = .none
    @Published var isHeadphonesConnected: Bool = false
    @Published var connectedHeadphoneType: HeadphoneType = .unknown
    @Published var potentiallySupportsMotion: Bool = false

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()
    private let audioSession = AVAudioSession.sharedInstance()

    // MARK: - Route Change Publisher

    private let routeChangeSubject = PassthroughSubject<AudioRouteChange, Never>()

    var routeChangePublisher: AnyPublisher<AudioRouteChange, Never> {
        routeChangeSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    init() {
        setupAudioSession()
        startMonitoring()
        updateCurrentRoute()
    }

    deinit {
        cancellables.removeAll()
    }

    // MARK: - Public Interface

    /// 現在のオーディオルート情報を強制更新
    func refreshRouteInfo() {
        updateCurrentRoute()
    }

    /// ヘッドホンの詳細情報を取得
    func getHeadphoneDetails() -> HeadphoneDetails? {
        guard isHeadphonesConnected else { return nil }

        let route = audioSession.currentRoute
        let outputs = route.outputs

        for output in outputs {
            if let details = createHeadphoneDetails(from: output) {
                return details
            }
        }

        return nil
    }

    // MARK: - Private Implementation

    private func setupAudioSession() {
        do {
            // オーディオセッションを設定（外音取り込み対応）
            try audioSession.setCategory(.playback, mode: .default, options: [.allowBluetoothA2DP])
            try audioSession.setActive(true)
        } catch {
            print("AudioSession setup failed: \(error)")
        }
    }

    private func startMonitoring() {
        // AVAudioSession.routeChangeNotificationを監視
        NotificationCenter.default
            .publisher(for: AVAudioSession.routeChangeNotification)
            .compactMap { notification in
                self.parseRouteChangeNotification(notification)
            }
            .sink { [weak self] routeChange in
                self?.handleRouteChange(routeChange)
            }
            .store(in: &cancellables)
    }

    private func stopMonitoring() {
        cancellables.removeAll()
    }

    private func parseRouteChangeNotification(_ notification: Notification) -> AudioRouteChange? {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return nil
        }

        let previousRoute = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription

        return AudioRouteChange(
            reason: reason,
            previousRoute: previousRoute,
            currentRoute: audioSession.currentRoute
        )
    }

    private func handleRouteChange(_ change: AudioRouteChange) {
        updateCurrentRoute()

        // ルート変更をパブリッシュ
        routeChangeSubject.send(change)

        // ログ出力（デバッグ用）
        logRouteChange(change)
    }

    private func updateCurrentRoute() {
        let route = audioSession.currentRoute
        let (audioRoute, headphoneType, supportsMotion) = analyzeRoute(route)

        currentRoute = audioRoute
        isHeadphonesConnected = audioRoute.isHeadphones
        connectedHeadphoneType = headphoneType
        potentiallySupportsMotion = supportsMotion
    }

    private func analyzeRoute(_ route: AVAudioSessionRouteDescription) -> (AudioRoute, HeadphoneType, Bool) {
        let outputs = route.outputs

        for output in outputs {
            let routeType = classifyOutput(output)
            let headphoneType = identifyHeadphoneType(output)
            let supportsMotion = estimateMotionSupport(headphoneType, output: output)

            if routeType != .none {
                return (routeType, headphoneType, supportsMotion)
            }
        }

        return (.none, .unknown, false)
    }

    private func classifyOutput(_ output: AVAudioSessionPortDescription) -> AudioRoute {
        switch output.portType {
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
            return .bluetoothHeadphones
        case .headphones, .headsetMic:
            return .wiredHeadphones
        case .builtInSpeaker:
            return .speaker
        case .builtInReceiver:
            return .receiver
        default:
            return .other
        }
    }

    private func identifyHeadphoneType(_ output: AVAudioSessionPortDescription) -> HeadphoneType {
        guard output.portType == .bluetoothA2DP || output.portType == .bluetoothLE else {
            return output.portType == .headphones ? .wired : .unknown
        }

        // ポート名やUID文字列からAirPodsの種類を推定
        let portName = output.portName.lowercased()

        if portName.contains("airpods pro") {
            return .airPodsProGen1  // 世代判定は困難なのでGen1として扱う
        } else if portName.contains("airpods max") {
            return .airPodsMax
        } else if portName.contains("airpods") {
            return .airPodsStandard
        } else if portName.contains("beats") && (portName.contains("fit pro") || portName.contains("studio")) {
            return .beatsWithMotion
        }

        return .bluetoothOther
    }

    private func estimateMotionSupport(_ headphoneType: HeadphoneType, output: AVAudioSessionPortDescription) -> Bool {
        switch headphoneType {
        case .airPodsProGen1, .airPodsProGen2, .airPodsMax, .beatsWithMotion:
            return true
        case .airPodsStandard, .bluetoothOther, .wired, .unknown:
            return false
        }
    }

    private func createHeadphoneDetails(from output: AVAudioSessionPortDescription) -> HeadphoneDetails? {
        let routeType = classifyOutput(output)
        guard routeType.isHeadphones else { return nil }

        return HeadphoneDetails(
            portName: output.portName,
            portType: output.portType,
            uid: output.uid,
            headphoneType: identifyHeadphoneType(output),
            estimatedMotionSupport: estimateMotionSupport(identifyHeadphoneType(output), output: output),
            channels: output.channels?.count ?? 0,
            dataSources: output.dataSources?.map { $0.dataSourceName } ?? []
        )
    }

    private func logRouteChange(_ change: AudioRouteChange) {
        print("🎧 Audio Route Change:")
        print("  Reason: \(change.reason)")
        print("  Current: \(change.currentRoute.outputs.map { $0.portName }.joined(separator: ", "))")
        print("  Previous: \(change.previousRoute?.outputs.map { $0.portName }.joined(separator: ", ") ?? "None")")
        print("  Motion Support Estimated: \(potentiallySupportsMotion)")
    }
}

// MARK: - Supporting Types

/// オーディオルートの種類
enum AudioRoute: CaseIterable {
    case none
    case speaker
    case receiver
    case wiredHeadphones
    case bluetoothHeadphones
    case other

    var isHeadphones: Bool {
        return self == .wiredHeadphones || self == .bluetoothHeadphones
    }

    var description: String {
        switch self {
        case .none: return "なし"
        case .speaker: return "スピーカー"
        case .receiver: return "レシーバー"
        case .wiredHeadphones: return "有線ヘッドホン"
        case .bluetoothHeadphones: return "Bluetoothヘッドホン"
        case .other: return "その他"
        }
    }
}

/// ヘッドホンの種類（モーション対応可否の推定用）
enum HeadphoneType: CaseIterable {
    case unknown
    case wired
    case airPodsStandard  // 通常のAirPods（モーション非対応）
    case airPodsProGen1   // AirPods Pro 第1世代
    case airPodsProGen2   // AirPods Pro 第2世代
    case airPodsMax       // AirPods Max
    case beatsWithMotion  // Beats Fit Pro, Studio Pro等
    case bluetoothOther   // その他のBluetoothヘッドホン

    var description: String {
        switch self {
        case .unknown: return "不明"
        case .wired: return "有線ヘッドホン"
        case .airPodsStandard: return "AirPods"
        case .airPodsProGen1: return "AirPods Pro (第1世代)"
        case .airPodsProGen2: return "AirPods Pro (第2世代)"
        case .airPodsMax: return "AirPods Max"
        case .beatsWithMotion: return "Beats (モーション対応)"
        case .bluetoothOther: return "Bluetoothヘッドホン"
        }
    }

    var expectedMotionSupport: Bool {
        switch self {
        case .airPodsProGen1, .airPodsProGen2, .airPodsMax, .beatsWithMotion:
            return true
        default:
            return false
        }
    }
}

/// ルート変更の詳細情報
struct AudioRouteChange {
    let reason: AVAudioSession.RouteChangeReason
    let previousRoute: AVAudioSessionRouteDescription?
    let currentRoute: AVAudioSessionRouteDescription
    let timestamp: Date = Date()
}

/// ヘッドホンの詳細情報
struct HeadphoneDetails {
    let portName: String
    let portType: AVAudioSession.Port
    let uid: String
    let headphoneType: HeadphoneType
    let estimatedMotionSupport: Bool
    let channels: Int
    let dataSources: [String]
}

// MARK: - Extensions

extension AVAudioSession.RouteChangeReason: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .unknown: return "Unknown"
        case .newDeviceAvailable: return "New Device Available"
        case .oldDeviceUnavailable: return "Old Device Unavailable"
        case .categoryChange: return "Category Change"
        case .override: return "Override"
        case .wakeFromSleep: return "Wake From Sleep"
        case .noSuitableRouteForCategory: return "No Suitable Route"
        case .routeConfigurationChange: return "Route Configuration Change"
        @unknown default: return "Unknown Reason"
        }
    }
}
