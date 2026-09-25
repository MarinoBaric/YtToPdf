import Testing
@testable import YtToPdf

@Suite("yt-dlp error classification")
struct YtDlpErrorClassifierTests {
    @Test(arguments: [
        ("ERROR: [youtube] abc: Private video. Sign in if you've been granted access to this video", YouTubeError.privateVideo),
        ("ERROR: [youtube] abc: Sign in to confirm your age. This video may be inappropriate for some users.", .ageRestricted),
        ("ERROR: [youtube] abc: Join this channel to get access to members-only content like this video.", .membersOnly),
        ("ERROR: [youtube] abc: Sign in to confirm you’re not a bot. Use --cookies-from-browser", .botCheck),
        ("ERROR: [youtube] abc: This live event will begin in 3 hours.", .liveOrUpcoming),
        ("ERROR: [youtube] aaaaaaaaaaa: This video is unavailable", .unavailable),
        ("ERROR: [youtube] abc: Video unavailable. This video has been removed by the uploader", .unavailable),
        ("ERROR: [youtube] abc: Unable to download API page: <urlopen error [Errno 8] nodename nor servname provided, or not known>", .noNetwork),
        ("ERROR: [youtube] abc: Failed to extract any player response; please report this issue on https://github.com/yt-dlp/yt-dlp/issues?q= , filling out the appropriate issue template. Confirm you are on the latest version using  yt-dlp -U", .ytDlpOutdated),
        ("ERROR: Unsupported URL: https://example.com", .invalidURL),
    ])
    func recognisesKnownFailures(_ stderr: String, _ expected: YouTubeError) {
        #expect(YtDlpErrorClassifier.classify(stderr) == expected)
    }

    @Test func ignoresWarningsWhenAnErrorLineExists() {
        let stderr = """
        WARNING: [youtube] Unable to download API page: timed out, retrying
        ERROR: [youtube] abc: Private video. Sign in if you've been granted access
        """
        #expect(YtDlpErrorClassifier.classify(stderr) == .privateVideo)
    }

    @Test func unknownErrorsKeepTheirMessage() {
        let stderr = "ERROR: [youtube] abc123: Something entirely new happened"
        #expect(YtDlpErrorClassifier.classify(stderr) == .toolFailed("Something entirely new happened"))
    }

    @Test func outdatedErrorOffersTheUpgradeCommand() {
        #expect(YouTubeError.ytDlpOutdated.fixCommand == "brew upgrade yt-dlp")
        #expect(YouTubeError.privateVideo.fixCommand == nil)
    }
}
