import AVFoundation
import SwiftUI
import Foundation

@Observable
@MainActor
public final class AudioPlayer: NSObject, AVAudioPlayerDelegate {
    // MARK: - Properties
    
    public var isPlaying: Bool = false
    public var currentTime: TimeInterval = 0
    public var duration: TimeInterval = 0
    public var currentRecordingID: UUID?
    
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    
    // MARK: - Initialization
    
    public override init() {
        super.init()
    }
    
    // MARK: - Methods
    
    public func play(url: URL, recordingID: UUID) {
        if currentRecordingID == recordingID, let player = audioPlayer {
            player.play()
            isPlaying = true
            startTimer()
            return
        }
        
        stop()
        
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            
            if player.play() {
                audioPlayer = player
                currentRecordingID = recordingID
                duration = player.duration
                isPlaying = true
                startTimer()
            } else {
                print("AudioPlayer error: Failed to start playback.")
            }
        } catch {
            print("AudioPlayer error: \(error.localizedDescription)")
            stop()
        }
    }
    
    public func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopTimer()
    }
    
    public func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        currentRecordingID = nil
        stopTimer()
    }
    
    public func togglePlay(url: URL, recordingID: UUID) {
        if currentRecordingID == recordingID {
            if isPlaying {
                pause()
            } else {
                play(url: url, recordingID: recordingID)
            }
        } else {
            play(url: url, recordingID: recordingID)
        }
    }
    
    // MARK: - AVAudioPlayerDelegate
    
    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.handlePlaybackFinished()
        }
    }
    
    private func handlePlaybackFinished() {
        isPlaying = false
        currentRecordingID = nil
        currentTime = 0
        stopTimer()
    }
    
    // MARK: - Private Helpers
    
    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.updateCurrentTime()
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateCurrentTime() {
        if let player = audioPlayer, player.isPlaying {
            currentTime = player.currentTime
        }
    }
}
