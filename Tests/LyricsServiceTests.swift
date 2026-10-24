import Foundation

final class StubProtocol: URLProtocol {
    static var status = 200
    static var body = Data()
    static var requests = 0
    static var searchBody: Data?
    static var queuedStatuses: [Int] = []
    static var transportError: URLError?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        if let error = Self.transportError { client?.urlProtocol(self, didFailWithError: error); return }
        let queued = Self.queuedStatuses.isEmpty ? nil : Self.queuedStatuses.removeFirst()
        let search = request.url!.path.hasSuffix("/search") ? Self.searchBody : nil
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: queued ?? (search == nil ? Self.status : 200), httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: search ?? Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct LookupTests {
    static func main() {
        let request = LyricsService.request(title: "곡 & title", artist: "A+B", album: "Album / deluxe", duration: 123.6)
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        precondition(items.first { $0.name == "track_name" }?.value == "곡 & title")
        precondition(items.first { $0.name == "artist_name" }?.value == "A+B")
        precondition(items.first { $0.name == "duration" }?.value == "124")
        precondition(LyricsService.request(title: "t", artist: "a", album: "", duration: .nan).url!.query!.contains("duration") == false)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let service = LyricsService(session: URLSession(configuration: config))
        func fetch(_ key: String) -> String? {
            var done = false
            var result: String?
            service.fetch(key: key, title: "t", artist: "a", album: "b", duration: 10) { result = $0; done = true }
            let deadline = Date().addingTimeInterval(8)
            while !done && Date() < deadline { _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
            precondition(done, "Callback timed out")
            return result
        }
        StubProtocol.body = Data(#"{"syncedLyrics":"[00:01.00]sample","plainLyrics":"plain","instrumental":false}"#.utf8)
        precondition(fetch("success") == "[00:01.00]sample")
        let count = StubProtocol.requests
        precondition(fetch("success") == "[00:01.00]sample")
        precondition(StubProtocol.requests == count, "Cached track must not trigger a new request")
        StubProtocol.status = 404
        precondition(fetch("missing") == nil)
        StubProtocol.status = 200
        StubProtocol.body = Data("not JSON".utf8)
        precondition(fetch("malformed") == nil)
        StubProtocol.body = Data(#"{"plainLyrics":"plain only","instrumental":false}"#.utf8)
        precondition(fetch("plain") == "plain only")
        StubProtocol.body = Data(#"{"plainLyrics":"ignore","instrumental":true}"#.utf8)
        precondition(fetch("instrumental") == nil)
        StubProtocol.status = 404
        StubProtocol.searchBody = Data(#"[{"trackName":"t","artistName":"a","duration":11,"syncedLyrics":"[00:01.00]matched"},{"trackName":"t","artistName":"different artist","duration":10,"syncedLyrics":"[00:01.00]wrong"}]"#.utf8)
        precondition(fetch("album-mismatch") == "[00:01.00]matched", "Search should match the same song from a different album")
        StubProtocol.searchBody = Data(#"[{"trackName":"t","artistName":"different artist","duration":10,"plainLyrics":"wrong"},{"trackName":"t","artistName":"a","duration":100,"plainLyrics":"wrong version"}]"#.utf8)
        precondition(fetch("reject-wrong-song") == nil, "Reject other artists and recordings with different duration")
        StubProtocol.searchBody = nil
        StubProtocol.status = 200
        StubProtocol.body = Data(#"{"plainLyrics":"recovered"}"#.utf8)
        StubProtocol.queuedStatuses = [503, 200]
        let beforeRetry = StubProtocol.requests
        precondition(fetch("recover-after-503") == "recovered")
        precondition(StubProtocol.requests == beforeRetry + 2)
        StubProtocol.status = 503
        precondition(fetch("busy-server") == nil)
        precondition(service.status.contains("혼잡 (503)"))
        StubProtocol.transportError = URLError(.notConnectedToInternet)
        precondition(fetch("offline") == nil)
        precondition(service.status.contains("인터넷 연결 없음"))
        StubProtocol.transportError = nil
        StubProtocol.status = 200
        StubProtocol.body = Data("[]".utf8)
        precondition(fetch("invalid-format") == nil)
        precondition(service.status.contains("응답 형식 오류"))
        var staleCalled = false
        service.fetch(key: "cancelled", title: "t", artist: "a", album: "", duration: 10) { _ in staleCalled = true }
        service.cancel()
        let deadline = Date().addingTimeInterval(0.2)
        while Date() < deadline { _ = RunLoop.current.run(mode: .default, before: deadline) }
        precondition(!staleCalled, "Cancelled requests must not update a new track")
        print("PASS: request encoding, duration validation, synced/plain lyrics, cache, missing/malformed/instrumental responses, album fallback, wrong-song rejection, transient retry, overload/offline/format diagnostics, cancellation")
    }
}
