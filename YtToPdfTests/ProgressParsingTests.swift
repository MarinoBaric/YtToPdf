import Foundation
import Synchronization
import Testing
@testable import YtToPdf

@Suite("Progress parsing")
struct ProgressParsingTests {
    @Test(arguments: [
        ("YTTOPDF-PROGRESS 500 1000 NA", 0.5),
        ("YTTOPDF-PROGRESS 250 NA 1000", 0.25),
        ("YTTOPDF-PROGRESS 2000 1000 1000", 1.0),
    ])
    func readsYtDlpTemplateLines(_ line: String, _ expected: Double) {
        #expect(YouTubeService.downloadProgress(from: line) == expected)
    }

    @Test(arguments: ["YTTOPDF-PROGRESS 10 NA NA", "[download] 10.0% of 2.00MiB", "YTTOPDF-PROGRESS NA 100 NA", ""])
    func ignoresOtherYtDlpLines(_ line: String) {
        #expect(YouTubeService.downloadProgress(from: line) == nil)
    }

    @Test func readsFFmpegProgress() {
        #expect(AudioConverter.progress(from: "out_time_us=30000000", duration: 120) == 0.25)
        #expect(AudioConverter.progress(from: "out_time_us=999000000", duration: 120) == 1)
        #expect(AudioConverter.progress(from: "out_time_us=N/A", duration: 120) == nil)
        #expect(AudioConverter.progress(from: "progress=continue", duration: 120) == nil)
        #expect(AudioConverter.progress(from: "out_time_us=1000", duration: 0) == nil)
    }

    @Test func readsWhisperProgress() {
        #expect(WhisperService.progress(from: "whisper_print_progress_callback: progress =  41%") == 0.41)
        #expect(WhisperService.progress(from: "whisper_print_progress_callback: progress = 100%") == 1)
        #expect(WhisperService.progress(from: "whisper_init_from_file: loading model") == nil)
    }

    @Test func monotonicProgressNeverGoesBackwards() {
        let reported = Mutex<[Double]>([])
        let progress = MonotonicProgress { value in reported.withLock { $0.append(value) } }
        for value in [0.2, 0.41, 0.83, 1.0, 0.83, 1.0] { progress.update(value) }
        #expect(reported.withLock { $0 } == [0.2, 0.41, 0.83, 1.0])
    }
}
