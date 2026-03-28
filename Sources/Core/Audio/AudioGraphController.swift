@preconcurrency import AVFoundation

final class AudioGraphController: @unchecked Sendable {
    private let deviceManager: CoreAudioDeviceManager
    private let levelMonitor: AudioLevelMonitor

    private(set) var engine: AVAudioEngine?
    private(set) var recordingMixer: AVAudioMixerNode?
    private(set) var micMixer: AVAudioMixerNode?
    private(set) var sysPlayerNode: AVAudioPlayerNode?
    private(set) var graphInitialized = false
    private(set) var graphIncludesSystemAudio = false

    init(deviceManager: CoreAudioDeviceManager, levelMonitor: AudioLevelMonitor) {
        self.deviceManager = deviceManager
        self.levelMonitor = levelMonitor
    }

    var isEngineRunning: Bool {
        engine?.isRunning ?? false
    }

    func prepareEngine() {
        engine?.prepare()
    }

    func startEngine() throws {
        guard let engine else {
            throw AudioRecorderError.setupFailed
        }

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                Log("Engine start failed: \(error)", level: .error)
                throw AudioRecorderError.setupFailed
            }
        }
    }

    func stopEngine() {
        engine?.stop()
    }

    func teardownGraph() {
        guard graphInitialized else { return }

        deviceManager.restoreOutputSampleRate()
        levelMonitor.stopPublishing(resetToZero: true)

        if let engine {
            if let recordingMixer {
                engine.disconnectNodeInput(recordingMixer)
                engine.disconnectNodeOutput(recordingMixer)
                engine.detach(recordingMixer)
            }

            if let micMixer {
                engine.disconnectNodeInput(micMixer)
                engine.disconnectNodeOutput(micMixer)
                engine.detach(micMixer)
            }

            if let sysPlayerNode {
                engine.disconnectNodeInput(sysPlayerNode)
                engine.disconnectNodeOutput(sysPlayerNode)
                engine.detach(sysPlayerNode)
            }
        }

        recordingMixer = nil
        micMixer = nil
        sysPlayerNode = nil
        engine = nil
        graphInitialized = false
        graphIncludesSystemAudio = false

        Log("AudioRecorder graph torn down (Engine Released)")
    }

    func setupGraph(recordSystemAudio: Bool) {
        guard !graphInitialized else { return }

        Log("Initializing AudioRecorder graph (systemAudio: \(recordSystemAudio))...")

        let engine = AVAudioEngine()
        let recordingMixer = AVAudioMixerNode()
        let micMixer = AVAudioMixerNode()
        let mainMixer = engine.mainMixerNode
        mainMixer.outputVolume = 0.0

        self.engine = engine
        self.recordingMixer = recordingMixer
        self.micMixer = micMixer

        engine.attach(recordingMixer)
        engine.attach(micMixer)

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        Log("Hardware input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch")

        engine.connect(inputNode, to: micMixer, format: inputFormat)
        if inputFormat.channelCount >= 2 {
            micMixer.pan = -1.0
        }
        engine.connect(micMixer, to: recordingMixer, format: inputFormat)

        if recordSystemAudio {
            let systemFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48000,
                channels: 2,
                interleaved: false
            )

            if let systemFormat {
                let sysPlayerNode = AVAudioPlayerNode()
                engine.attach(sysPlayerNode)
                if inputFormat.channelCount >= 2 {
                    sysPlayerNode.pan = 1.0
                }
                engine.connect(sysPlayerNode, to: recordingMixer, format: systemFormat)
                self.sysPlayerNode = sysPlayerNode
            }
        }

        engine.connect(recordingMixer, to: mainMixer, format: inputFormat)
        Log("Graph connections established. Input: \(inputFormat.sampleRate)Hz \(inputFormat.channelCount)ch")

        graphInitialized = true
        graphIncludesSystemAudio = recordSystemAudio
        Log("AudioRecorder graph initialized")
    }
}
