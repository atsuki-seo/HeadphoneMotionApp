# HeadphoneMotionApp

## 📱 プロジェクト概要

**HeadphoneMotionApp**は、AppleのCMHeadphoneMotionManagerを活用したヘッドホンモーション検証用iOSアプリケーションです。AirPods ProやAirPods Maxなどの対応ヘッドホンから取得できるモーションデータの精度と特性を詳細に検証することを目的としています。

### 🎯 検証目的
- ヘッドホンモーションセンサーの精度測定
- リアルタイムモーション追跡の性能評価
- 片耳装着時の動作特性確認
- モーションイベント検出アルゴリズムの検証
- 音響ガイドシステムの効果測定

## 🔧 技術仕様

### アーキテクチャ
- **フレームワーク**: SwiftUI + Combine
- **言語**: Swift 5.9+
- **最小対応**: iOS 17.0+
- **Xcode**: 15.0+

### 主要フレームワーク
```swift
import CoreMotion          // CMHeadphoneMotionManager
import AVFoundation        // オーディオエンジン
import SwiftUI            // ユーザーインターフェース
import Combine            // リアクティブプログラミング
import Accelerate         // 信号処理
```

### プロジェクト構造
```
HeadphoneMotionApp/
├── Models/
│   ├── MotionData.swift           # モーションデータ構造定義
│   ├── HeadphoneMotionManager.swift # CoreMotion統合管理
│   └── AudioRouteMonitor.swift    # オーディオルート監視
├── ViewModels/
│   └── MotionViewModel.swift      # UI用データバインディング
├── Views/
│   ├── ContentView.swift          # メインインターフェース
│   ├── MotionVisualizerView.swift # データ可視化
│   ├── DebugPanelView.swift       # デバッグ情報表示
│   └── SettingsView.swift         # 設定画面
└── Utils/
    └── Filters.swift              # 信号フィルタリング
```

## 🎧 対応デバイス

### 動作確認済みヘッドホン
| デバイス | モーション対応 | 推奨度 | 備考 |
|---------|---------------|--------|------|
| AirPods Pro (第1世代) | ✅ | ⭐⭐⭐ | 最適化済み |
| AirPods Pro (第2世代) | ✅ | ⭐⭐⭐ | 最適化済み |
| AirPods Max | ✅ | ⭐⭐⭐ | 高精度 |
| Beats Fit Pro | ✅ | ⭐⭐ | 対応 |
| Beats Studio Pro | ✅ | ⭐⭐ | 対応 |
| AirPods (第3世代) | ❌ | - | 非対応 |
| その他Bluetoothヘッドホン | ❌ | - | 非対応 |

### システム要件
- **iOS**: 17.0以上
- **デバイス**: iPhone/iPad
- **権限**: モーション＆フィットネス
- **接続**: Bluetooth（対応ヘッドホン必須）

## 🚀 主要機能

### 1. リアルタイムモーション追跡
```swift
// 取得可能なモーションデータ
struct MotionData {
    let attitude: AttitudeData      // 姿勢（roll/pitch/yaw）
    let rotationRate: RotationData  // 回転率（rad/s）
    let userAcceleration: AccelerationData  // ユーザー加速度
    let gravity: AccelerationData   // 重力ベクトル
    let timestamp: TimeInterval     // タイムスタンプ
}
```

### 2. モーションイベント検出
- **lookingDown**: 下向き姿勢検出
- **lookingUp**: 上向き姿勢検出
- **headShake**: 首振り動作検出
- **headNod**: うなずき動作検出
- **suddenMovement**: 急激な動き検出

### 3. 片耳使用対応音響システム
特化設計された音響ガイド機能:
- **右折音**: 高音域（1400Hz）+ 速いテンポ（3回×100ms）
- **左折音**: 低音域（500Hz）+ ゆったりテンポ（2回×200ms）
- **直進音**: 中音域（700Hz）+ 短クリック
- **注意音**: 超低音域（300Hz）+ 帯域制限ノイズ

### 4. データ可視化
- 3D姿勢ビジュアライザー
- リアルタイムグラフ表示
- セッション統計
- CSV形式データエクスポート

## 📊 検証項目

### 測定可能なメトリクス
1. **精度**: 静止時のセンサードリフト
2. **応答性**: モーション開始からデータ取得までの遅延
3. **更新頻度**: データ更新レート（通常30-60Hz）
4. **安定性**: 長時間使用での性能維持
5. **片耳対応**: 片耳装着時の検出精度

### データ形式
```csv
timestamp,roll,pitch,yaw,rotX,rotY,rotZ,accX,accY,accZ,gravX,gravY,gravZ
1698123456.789,-0.1,0.05,1.2,0.01,-0.02,0.1,0.02,0.01,0.98,0.1,-0.05,0.98
```

## 📱 使用方法

### 1. 初期セットアップ
1. 対応ヘッドホンをiOSデバイスに接続
2. アプリを起動し、モーション権限を許可
3. 「設定」タブで校正とテストを実行

### 2. 基本操作
```
メインタブ「モーション」:
├── [開始/停止] - モーション記録の開始/停止
├── [校正] - ゼロ位置の校正実行
├── [音響ON/OFF] - 音響ガイドの有効/無効
└── [データクリア] - 履歴のクリア
```

### 3. デバッグモード
「デバッグ」タブから詳細情報を確認:
- 生データの数値表示
- 接続状態の診断
- エラーログの確認
- パフォーマンス統計

### 4. 推奨設定
- **外音取り込みモード**の使用を推奨
- **片耳装着**でも完全動作
- **校正**は使用開始時に必須実行

## ⚠️ 注意事項

### 既知の制限事項
1. **シミュレーター**: 実機のみ動作（モーションセンサー必須）
2. **権限**: 初回起動時のモーション権限許可が必要
3. **バッテリー**: 連続使用時のヘッドホンバッテリー消費
4. **干渉**: 他のBluetooth機器との電波干渉

### トラブルシューティング
```
❌ 「ヘッドホン未接続」
→ Bluetooth設定を確認し、対応デバイスを接続

❌ 「権限拒否」
→ 設定アプリ > プライバシー > モーション で許可

❌ 「モーション非対応」
→ AirPods Pro/Max等の対応デバイスに変更

❌ 「データ取得失敗」
→ ヘッドホンの再接続とアプリ再起動
```

## 👨‍💻 開発情報

### ビルド要件
```bash
# Xcode 15.0以上
xcode-select --install

# iOS 17.0 SDK
# macOS 13.0以上
```

### Bundle Identifier
```
jp.ac.yuge.HeadphoneMotionApp
```

### バージョン
- **Marketing Version**: 1.0
- **Build**: 1

### プライバシー権限
```xml
<!-- Info.plist -->
<key>NSMotionUsageDescription</key>
<string>ヘッドホンのモーションデータを取得し、頭部動作を検出するために使用します</string>
```

## 📈 今後の展開

### 計画中の機能
- [ ] 複数セッションの比較分析
- [ ] 機械学習によるパターン認識
- [ ] クラウド同期とデータ共有
- [ ] Apple WatchとのデータResize連携

---

**開発者**: Atsuki Seo
**作成日**: 2025年10月23日
**用途**: 研究・検証用途専用