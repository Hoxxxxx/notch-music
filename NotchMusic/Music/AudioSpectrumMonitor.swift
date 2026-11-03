import Accelerate
import AppKit
import CoreAudio
import Foundation
import os

enum MusicSpectrumSettings {
    static let enabled = "NotchMusic.musicSpectrumEnabled"
}

enum MusicSpectrumStatus: Equatable {
    case disabled
    case waitingForPlayback
    case unsupported
    case starting
    case running
    case failed(String)

    var text: String {
        switch self {
        case .disabled:
            return "未启用"
        case .waitingForPlayback:
            return "等待 Apple Music 播放"
        case .unsupported:
            return "需要 macOS 14.2 或更新版本"
        case .starting:
            return "正在连接音频"
        case .running:
            return "正在分析 Apple Music"
        case .failed(let message):
            return message
        }
    }
}

@MainActor
final class AudioSpectrumMonitor: ObservableObject {
    @Published private(set) var levels = [CGFloat](
        repeating: 0,
        count: AudioSpectrumAnalyzer.bandCount
    )
    @Published private(set) var status: MusicSpectrumStatus = .disabled

    var isSupported: Bool {
        if #available(macOS 14.2, *) {
            return true
        }
        return false
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: MusicSpectrumSettings.enabled)
    }

    private var capture: AppleMusicTapCapture?
    private var displayTask: Task<Void, Never>?
    private var defaultsObserver: NSObjectProtocol?
    private var playbackActive = false
    private var captureGeneration = UUID()

    init() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshCaptureState()
            }
        }
        refreshCaptureState()
    }

    func setPlaybackActive(_ isPlaying: Bool) {
        guard playbackActive != isPlaying else { return }
        playbackActive = isPlaying
        refreshCaptureState()
    }

    func stop() {
        stopCapture(status: .disabled)
        capture = nil
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
            self.defaultsObserver = nil
        }
    }

    func openPrivacySettings() {
        let value = "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture"
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }

    private func refreshCaptureState() {
        guard isEnabled else {
            stopCapture(status: .disabled)
            return
        }
        guard isSupported else {
            stopCapture(status: .unsupported)
            return
        }
        guard playbackActive else {
            stopCapture(status: .waitingForPlayback)
            return
        }
        guard capture == nil else { return }
        startCapture()
    }

    private func startCapture() {
        guard let music = NSWorkspace.shared.runningApplications.first(
            where: { $0.bundleIdentifier == "com.apple.Music" }
        ) else {
            status = .failed("Apple Music 未运行")
            return
        }

        let generation = UUID()
        captureGeneration = generation
        status = .starting

        let capture = AppleMusicTapCapture()
        self.capture = capture
        capture.start(processID: music.processIdentifier) { [weak self] result in
            Task { @MainActor in
                guard let self, self.captureGeneration == generation else {
                    capture.stop()
                    return
                }

                switch result {
                case .success:
                    self.status = .running
                    self.startDisplayUpdates(store: capture.levelStore)
                case .failure(let error):
                    self.capture = nil
                    capture.stop()
                    self.clearLevels()
                    self.status = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func stopCapture(status newStatus: MusicSpectrumStatus) {
        captureGeneration = UUID()
        displayTask?.cancel()
        displayTask = nil
        capture?.stop()
        capture = nil
        clearLevels()

        if case .failed = status, newStatus == .waitingForPlayback {
            return
        }
        status = newStatus
    }

    private func startDisplayUpdates(store: SpectrumLevelStore) {
        displayTask?.cancel()
        displayTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.levels = store.read()
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
        }
    }

    private func clearLevels() {
        levels = [CGFloat](
            repeating: 0,
            count: AudioSpectrumAnalyzer.bandCount
        )
    }
}

private final class AppleMusicTapCapture: @unchecked Sendable {
    let levelStore = SpectrumLevelStore()

    private let queue = DispatchQueue(label: "NotchMusic.AudioSpectrumCapture")
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var analyzer: AudioSpectrumAnalyzer?

    func start(
        processID: pid_t,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        queue.async {
            self.stopLocked()

            guard #available(macOS 14.2, *) else {
                DispatchQueue.main.async {
                    completion(.failure(SpectrumCaptureError.unsupportedSystem))
                }
                return
            }

            do {
                try self.startLocked(processID: processID)
                DispatchQueue.main.async {
                    completion(.success(()))
                }
            } catch {
                self.stopLocked()
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    func stop() {
        queue.async {
            self.stopLocked()
        }
    }

    @available(macOS 14.2, *)
    private func startLocked(processID: pid_t) throws {
        guard let processObject = Self.processObjectID(forPID: processID) else {
            throw SpectrumCaptureError.processUnavailable
        }

        let description = CATapDescription(
            stereoMixdownOfProcesses: [processObject]
        )
        description.name = "NotchMusic Spectrum"
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(description, &newTapID)
        guard tapStatus == noErr, newTapID != kAudioObjectUnknown else {
            throw SpectrumCaptureError.tapCreationFailed(tapStatus)
        }
        tapID = newTapID

        let format = try Self.tapFormat(tapID)
        guard format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBytesPerFrame > 0 else {
            throw SpectrumCaptureError.unsupportedAudioFormat
        }

        try createAggregateDevice(tapUUID: description.uuid)
        analyzer = AudioSpectrumAnalyzer(
            sampleRate: format.mSampleRate,
            store: levelStore
        )
        try createIOProc()
        try Self.check(
            AudioDeviceStart(aggregateDeviceID, ioProcID),
            error: SpectrumCaptureError.deviceStartFailed
        )
    }

    private func stopLocked() {
        if let ioProcID {
            if aggregateDeviceID != kAudioObjectUnknown {
                AudioDeviceStop(aggregateDeviceID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            }
            self.ioProcID = nil
        }
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            if #available(macOS 14.2, *) {
                AudioHardwareDestroyProcessTap(tapID)
            }
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        analyzer = nil
        levelStore.clear()
    }

    @available(macOS 14.2, *)
    private func createAggregateDevice(tapUUID: UUID) throws {
        var description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "NotchMusic Spectrum",
            kAudioAggregateDeviceUIDKey: "NotchMusic.Spectrum.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUUID.uuidString,
                    kAudioSubTapDriftCompensationKey: true
                ]
            ]
        ]

        if let outputUID = Self.defaultOutputDeviceUID() {
            description[kAudioAggregateDeviceMainSubDeviceKey] = outputUID
            description[kAudioAggregateDeviceClockDeviceKey] = outputUID
            description[kAudioAggregateDeviceSubDeviceListKey] = [
                [
                    kAudioSubDeviceUIDKey: outputUID,
                    kAudioSubDeviceDriftCompensationKey: true
                ]
            ]
        }

        var deviceID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(
            description as CFDictionary,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            throw SpectrumCaptureError.aggregateCreationFailed(status)
        }
        aggregateDeviceID = deviceID
    }

    private func createIOProc() throws {
        guard let analyzer else {
            throw SpectrumCaptureError.audioFormatUnavailable
        }

        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(
            &procID,
            aggregateDeviceID,
            nil
        ) { _, inputData, _, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(
                UnsafeMutablePointer(mutating: inputData)
            )
            analyzer.process(buffers: buffers)
        }

        guard status == noErr, let procID else {
            throw SpectrumCaptureError.ioProcCreationFailed(status)
        }
        ioProcID = procID
    }

    @available(macOS 14.2, *)
    private static func processObjectID(forPID pid: pid_t) -> AudioObjectID? {
        var processID = pid
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var objectID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &processID) { pointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<pid_t>.size),
                pointer,
                &size,
                &objectID
            )
        }
        guard status == noErr, objectID != kAudioObjectUnknown else {
            return nil
        }
        return objectID
    }

    @available(macOS 14.2, *)
    private static func tapFormat(
        _ tapID: AudioObjectID
    ) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(
            AudioObjectGetPropertyData(
                tapID,
                &address,
                0,
                nil,
                &size,
                &format
            ),
            error: { _ in SpectrumCaptureError.audioFormatUnavailable }
        )
        return format
    }

    private static func defaultOutputDeviceUID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        ) == noErr, deviceID != kAudioObjectUnknown else {
            return nil
        }

        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(
            deviceID,
            &uidAddress,
            0,
            nil,
            &uidSize,
            &uid
        ) == noErr, let uid else {
            return nil
        }
        return uid.takeRetainedValue() as String
    }

    private static func check(
        _ status: OSStatus,
        error: (OSStatus) -> SpectrumCaptureError
    ) throws {
        guard status == noErr else {
            throw error(status)
        }
    }
}

private enum SpectrumCaptureError: LocalizedError {
    case processUnavailable
    case tapCreationFailed(OSStatus)
    case aggregateCreationFailed(OSStatus)
    case ioProcCreationFailed(OSStatus)
    case deviceStartFailed(OSStatus)
    case unsupportedSystem
    case unsupportedAudioFormat
    case audioFormatUnavailable

    var errorDescription: String? {
        switch self {
        case .processUnavailable:
            return "无法连接 Apple Music 音频"
        case .unsupportedSystem:
            return "需要 macOS 14.2 或更新版本"
        case .tapCreationFailed, .deviceStartFailed:
            return "无法启动频谱。请在系统设置中允许 NotchMusic 录制系统音频"
        case .aggregateCreationFailed, .ioProcCreationFailed:
            return "无法创建音频分析设备"
        case .unsupportedAudioFormat, .audioFormatUnavailable:
            return "当前音频格式暂不支持"
        }
    }
}

private final class SpectrumLevelStore: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(
        initialState: [CGFloat](
            repeating: 0,
            count: AudioSpectrumAnalyzer.bandCount
        )
    )

    func store(_ bands: UnsafeBufferPointer<Float>) {
        lock.withLockUnchecked { values in
            for index in values.indices {
                let value = index < bands.count ? bands[index] : 0
                values[index] = CGFloat(min(max(value, 0), 1))
            }
        }
    }

    func read() -> [CGFloat] {
        lock.withLockUnchecked { $0 }
    }

    func clear() {
        lock.withLockUnchecked { values in
            for index in values.indices {
                values[index] = 0
            }
        }
    }
}

private final class AudioSpectrumAnalyzer: @unchecked Sendable {
    static let bandCount = 16

    private let fftSize = 1024
    private let binCount = 512
    private let log2n = vDSP_Length(10)
    private let sampleRate: Double
    private let store: SpectrumLevelStore
    private let fftSetup: FFTSetup?

    private let samples: UnsafeMutablePointer<Float>
    private let window: UnsafeMutablePointer<Float>
    private let windowed: UnsafeMutablePointer<Float>
    private let realPart: UnsafeMutablePointer<Float>
    private let imagPart: UnsafeMutablePointer<Float>
    private let magnitudes: UnsafeMutablePointer<Float>
    private let smoothedBands: UnsafeMutablePointer<Float>
    private var sampleIndex = 0

    private let lowerBins: [Int]
    private let upperBins: [Int]
    private let amplitudeScale: Float

    init(sampleRate: Double, store: SpectrumLevelStore) {
        self.sampleRate = sampleRate > 0 ? sampleRate : 48_000
        self.store = store
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))

        samples = .allocate(capacity: fftSize)
        window = .allocate(capacity: fftSize)
        windowed = .allocate(capacity: fftSize)
        realPart = .allocate(capacity: binCount)
        imagPart = .allocate(capacity: binCount)
        magnitudes = .allocate(capacity: binCount)
        smoothedBands = .allocate(capacity: Self.bandCount)

        samples.initialize(repeating: 0, count: fftSize)
        windowed.initialize(repeating: 0, count: fftSize)
        realPart.initialize(repeating: 0, count: binCount)
        imagPart.initialize(repeating: 0, count: binCount)
        magnitudes.initialize(repeating: 0, count: binCount)
        smoothedBands.initialize(repeating: 0, count: Self.bandCount)

        var windowSum: Float = 0
        for index in 0..<fftSize {
            let value = 0.5 * (
                1 - cos(2 * Float.pi * Float(index) / Float(fftSize - 1))
            )
            window.advanced(by: index).pointee = value
            windowSum += value
        }
        amplitudeScale = 1 / max(windowSum, 1)

        let ranges = Self.makeBandRanges(
            sampleRate: self.sampleRate,
            fftSize: fftSize,
            binCount: binCount
        )
        lowerBins = ranges.lower
        upperBins = ranges.upper
    }

    deinit {
        samples.deallocate()
        window.deallocate()
        windowed.deallocate()
        realPart.deallocate()
        imagPart.deallocate()
        magnitudes.deallocate()
        smoothedBands.deallocate()
        if let fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
        }
    }

    func process(buffers: UnsafeMutableAudioBufferListPointer) {
        guard !buffers.isEmpty else { return }

        if buffers.count == 1 {
            let buffer = buffers[0]
            guard let data = buffer.mData,
                  buffer.mDataByteSize > 0 else {
                return
            }
            let channelCount = max(Int(buffer.mNumberChannels), 1)
            let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let frameCount = sampleCount / channelCount
            let input = data.assumingMemoryBound(to: Float.self)

            for frame in 0..<frameCount {
                var value: Float = 0
                for channel in 0..<channelCount {
                    value += input[frame * channelCount + channel]
                }
                append(value / Float(channelCount))
            }
            return
        }

        let frameCount = buffers.reduce(Int.max) { result, buffer in
            guard buffer.mData != nil,
                  buffer.mNumberChannels > 0 else {
                return result
            }
            let count = Int(buffer.mDataByteSize)
                / (Int(buffer.mNumberChannels) * MemoryLayout<Float>.size)
            return min(result, count)
        }
        guard frameCount != Int.max, frameCount > 0 else { return }

        for frame in 0..<frameCount {
            var value: Float = 0
            var channelTotal = 0
            for buffer in buffers {
                guard let data = buffer.mData,
                      buffer.mNumberChannels > 0 else {
                    continue
                }
                let input = data.assumingMemoryBound(to: Float.self)
                for channel in 0..<Int(buffer.mNumberChannels) {
                    value += input[frame * Int(buffer.mNumberChannels) + channel]
                    channelTotal += 1
                }
            }
            if channelTotal > 0 {
                append(value / Float(channelTotal))
            }
        }
    }

    private func append(_ value: Float) {
        samples.advanced(by: sampleIndex).pointee = value
        sampleIndex += 1
        if sampleIndex == fftSize {
            analyze()
            sampleIndex = 0
        }
    }

    private func analyze() {
        guard let fftSetup else { return }

        vDSP_vmul(
            samples,
            1,
            window,
            1,
            windowed,
            1,
            vDSP_Length(fftSize)
        )

        var split = DSPSplitComplex(realp: realPart, imagp: imagPart)
        windowed.withMemoryRebound(
            to: DSPComplex.self,
            capacity: binCount
        ) { pointer in
            vDSP_ctoz(pointer, 2, &split, 1, vDSP_Length(binCount))
        }
        vDSP_fft_zrip(
            fftSetup,
            &split,
            1,
            log2n,
            FFTDirection(FFT_FORWARD)
        )
        vDSP_zvmags(
            &split,
            1,
            magnitudes,
            1,
            vDSP_Length(binCount)
        )

        var count = Int32(binCount)
        vvsqrtf(magnitudes, magnitudes, &count)
        var scale = amplitudeScale
        vDSP_vsmul(
            magnitudes,
            1,
            &scale,
            magnitudes,
            1,
            vDSP_Length(binCount)
        )

        for band in 0..<Self.bandCount {
            let lower = lowerBins[band]
            let upper = upperBins[band]
            var sum: Float = 0
            for bin in lower...upper {
                sum += magnitudes[bin]
            }
            let magnitude = sum / Float(upper - lower + 1)
            let decibels = 20 * log10f(max(magnitude, 0.000_000_1))
            let normalized = min(max((decibels + 68) / 58, 0), 1)
            let target = powf(normalized, 1.35)
            let current = smoothedBands.advanced(by: band).pointee
            let coefficient: Float = target > current ? 0.68 : 0.18
            smoothedBands.advanced(by: band).pointee =
                current + (target - current) * coefficient
        }

        let bands = UnsafeBufferPointer(
            start: smoothedBands,
            count: Self.bandCount
        )
        store.store(bands)
    }

    private static func makeBandRanges(
        sampleRate: Double,
        fftSize: Int,
        binCount: Int
    ) -> (lower: [Int], upper: [Int]) {
        let minimumFrequency = 55.0
        let maximumFrequency = min(16_000, sampleRate / 2)
        let ratio = maximumFrequency / minimumFrequency
        var lower: [Int] = []
        var upper: [Int] = []
        var previousUpper = 0

        for band in 0..<bandCount {
            let lowFraction = Double(band) / Double(bandCount)
            let highFraction = Double(band + 1) / Double(bandCount)
            let lowHz = minimumFrequency * pow(ratio, lowFraction)
            let highHz = minimumFrequency * pow(ratio, highFraction)

            var lowBin = Int(lowHz / sampleRate * Double(fftSize))
            var highBin = Int(highHz / sampleRate * Double(fftSize)) - 1
            lowBin = min(max(lowBin, 1), binCount - 1)
            highBin = min(max(highBin, lowBin), binCount - 1)
            lowBin = min(max(lowBin, previousUpper + 1), binCount - 1)
            highBin = max(highBin, lowBin)
            previousUpper = highBin
            lower.append(lowBin)
            upper.append(highBin)
        }
        return (lower, upper)
    }
}
