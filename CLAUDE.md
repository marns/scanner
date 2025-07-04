# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

StrayScanner is an iOS app for collecting RGB-D datasets using LiDAR-enabled devices. The app captures synchronized RGB video, depth maps, confidence maps, camera poses, and IMU data for computer vision research.

## Build Commands

```bash
# Install dependencies (CocoaPods)
pod install

# Open workspace (required after pod install)
open StrayScanner.xcworkspace

# Build from command line
xcodebuild -workspace StrayScanner.xcworkspace -scheme StrayScanner -configuration Debug build

# Run tests
xcodebuild -workspace StrayScanner.xcworkspace -scheme StrayScanner test
```

**Important**: Always use the `.xcworkspace` file, not the `.xcodeproj`, due to CocoaPods integration.

## Architecture Overview

### Hybrid UI Pattern
- **SwiftUI** for modern navigation and settings (`SessionList`, `SettingsView`)  
- **UIKit** for ARKit integration (`RecordSessionViewController`)
- SwiftUI views wrap UIKit controllers using `UIViewControllerRepresentable`

### Core Data Flow
1. **ARKit Session** → Real-time AR frames with RGB, depth, and pose data
2. **Parallel Encoders** → Process different data streams concurrently:
   - `VideoEncoder`: RGB → HEVC MP4
   - `DepthEncoder`: Depth maps → 16-bit PNG sequence  
   - `ConfidenceEncoder`: Confidence maps → PNG sequence
   - `OdometryEncoder`: Camera poses → CSV
   - `IMUEncoder`: Raw sensor data → CSV
3. **DatasetEncoder** → Orchestrates all encoders and manages frame sampling
4. **File Export** → ZIP archives for iOS Share Sheet

### Key Components

**Controllers**:
- `RecordSessionViewController`: Main recording interface using ARKit
- `CameraRenderer`: Metal-based real-time RGB/depth visualization

**Data Processing**:
- `DatasetEncoder`: Central orchestrator for all data streams
- Individual encoders for each data type (video, depth, IMU, etc.)
- `AppDaemon`: Background cleanup and session management

**Models**:
- Core Data `Recording` entity for metadata persistence
- File-based storage in app's Documents directory

## Important Patterns

### Settings Management
All user preferences are centralized in `SettingsConstants.swift`:
- UserDefaults keys as constants to prevent typos
- Default values defined once and reused across components
- Frame rate options and adaptive mode thresholds

### Adaptive Recording Mode
Intelligent frame selection based on movement thresholds:
- Position threshold (default: 15cm)
- Rotation threshold using forward vector comparison (default: 15°)
- Haptic feedback when frames are captured
- Toggle between fixed FPS and adaptive mode via recording screen button

### Memory Management
- Weak self pattern in async closures to prevent ARFrame retention
- Extract frame data before async dispatch to release ARFrames quickly
- Use `defer` blocks to ensure dispatch group balance

### Metal Rendering
- Custom Metal shaders for real-time RGB/depth visualization
- Tap gesture to switch between RGB and depth views
- Hardware-accelerated rendering for smooth performance

## Data Format

Each recording creates a structured dataset in app's Documents directory:
```
[hash]/
├── rgb.mp4              # HEVC video
├── depth/000000.png     # 16-bit depth maps (192x256, millimeters)
├── confidence/000000.png # Confidence maps (0-2 scale)
├── camera_matrix.csv    # 3x3 intrinsic matrix
├── odometry.csv         # Frame poses (timestamp, xyz, quaternion)
└── imu.csv             # Raw accelerometer/gyroscope (~100Hz)
```

## Device Requirements

- iOS 14.2+
- LiDAR-capable device (iPhone 12 Pro+, iPad Pro 2020+)
- Requires ARKit world tracking with scene depth

## Common Development Patterns

### Adding New Settings
1. Add constant to `SettingsConstants.swift`
2. Update `SettingsView.swift` with UI controls
3. Read settings in relevant components using the constant keys

### Frame Processing
- Always extract needed data from ARFrame before async dispatch
- Use weak self in closures that process frames
- Balance `dispatchGroup.enter()` and `leave()` calls

### Error Handling
- Encoders have status enums for different error types
- Show user-friendly alerts for device compatibility issues
- Graceful degradation when hardware features unavailable

## Testing Notes

- Test target: `StrayScannerTests`
- Tests require device with ARKit support
- Core Data tests use in-memory store
- Metal shader compilation requires actual iOS device