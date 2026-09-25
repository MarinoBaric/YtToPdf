import Foundation
import Testing
@testable import YtToPdf

@Suite("YouTubeLink")
struct YouTubeLinkTests {
    @Test(arguments: [
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://youtube.com/watch?v=dQw4w9WgXcQ&t=42s&list=PL123",
        "http://m.youtube.com/watch?feature=share&v=dQw4w9WgXcQ",
        "https://music.youtube.com/watch?v=dQw4w9WgXcQ",
        "www.youtube.com/watch?v=dQw4w9WgXcQ",
        "youtube.com/watch?v=dQw4w9WgXcQ",
        "https://youtu.be/dQw4w9WgXcQ",
        "https://youtu.be/dQw4w9WgXcQ?si=abc123&t=10",
        "youtu.be/dQw4w9WgXcQ",
        "https://www.youtube.com/shorts/dQw4w9WgXcQ",
        "https://youtube.com/shorts/dQw4w9WgXcQ?feature=share",
        "https://www.youtube.com/live/dQw4w9WgXcQ",
        "https://www.youtube.com/embed/dQw4w9WgXcQ",
        "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ",
        "  https://www.youtube.com/watch?v=dQw4w9WgXcQ  \n",
    ])
    func acceptsVideoLinks(_ input: String) {
        #expect(YouTubeLink(string: input)?.videoID == "dQw4w9WgXcQ")
    }

    @Test(arguments: [
        "",
        "hello world",
        "https://vimeo.com/123456",
        "https://www.youtube.com/",
        "https://www.youtube.com/playlist?list=PL123",
        "https://www.youtube.com/@somechannel",
        "https://www.youtube.com/watch?v=tooShort",
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ!",
        "https://notyoutube.com/watch?v=dQw4w9WgXcQ",
        "https://youtube.com.evil.example/watch?v=dQw4w9WgXcQ",
    ])
    func rejectsEverythingElse(_ input: String) {
        #expect(YouTubeLink(string: input) == nil)
    }

    @Test func buildsCanonicalAndTimestampURLs() throws {
        let link = try #require(YouTubeLink(string: "https://youtu.be/dQw4w9WgXcQ?si=tracking"))
        #expect(link.watchURL.absoluteString == "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        #expect(link.watchURL(at: 83.9).absoluteString == "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=83s")
    }
}
