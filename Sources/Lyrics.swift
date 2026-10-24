import Foundation

struct LyricLine: Equatable {
    let time: TimeInterval
    let text: String
}
struct SongLyrics {
    let lines: [LyricLine]
    let plain: [String]
    var available: Bool { !lines.isEmpty || !plain.isEmpty }
    init(_ source: String) {
        let regex = try! NSRegularExpression(pattern: #"\[(\d+):([0-5]\d(?:\.\d+)?)\]"#)
        let offsetRegex = try! NSRegularExpression(pattern: #"\[offset:([+-]?\d+)\]"#, options: .caseInsensitive)
        let ns = source as NSString
        let offset = offsetRegex.firstMatch(in: source, range: NSRange(location: 0, length: ns.length))
            .flatMap { Double(ns.substring(with: $0.range(at: 1))) }.map { $0 / 1000 } ?? 0
        var parsed: [LyricLine] = []
        for raw in source.components(separatedBy: .newlines) {
            let line = raw as NSString
            let matches = regex.matches(in: raw, range: NSRange(location: 0, length: line.length))
            guard let last = matches.last else { continue }
            let text = line.substring(from: NSMaxRange(last.range)).trimmingCharacters(in: .whitespaces)
            for match in matches {
                let minutes = Double(line.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(line.substring(with: match.range(at: 2))) ?? 0
                parsed.append(LyricLine(time: max(0, minutes * 60 + seconds + offset), text: text))
            }
        }
        var grouped: [LyricLine] = []
        for line in parsed.sorted(by: { $0.time < $1.time }) {
            if let last = grouped.last, last.time == line.time {
                grouped[grouped.count - 1] = LyricLine(time: line.time, text: [last.text, line.text].filter { !$0.isEmpty }.joined(separator: "\n"))
            } else { grouped.append(line) }
        }
        lines = grouped
        plain = source.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("[") }
    }
    func activeIndex(at position: TimeInterval) -> Int {
        lines.lastIndex(where: { $0.time <= position }) ?? -1
    }
}


struct LyricsRecord: Decodable {
    let trackName: String?
    let artistName: String?
    let duration: Double?
    let syncedLyrics: String?
    let plainLyrics: String?
    let instrumental: Bool?
    var source: String? {
        guard instrumental != true else { return nil }
        for text in [syncedLyrics, plainLyrics].compactMap({ $0 }) {
            if SongLyrics(text).available { return text }
        }
        return nil
    }
}

final class LyricsService {
    private let session: URLSession
    private var task: URLSessionDataTask?
    private var requestID = UUID()
    private var cache: [String: (source: String?, status: String, expires: Date)] = [:]
    private(set) var status = ""
    init(session: URLSession = .shared) { self.session = session }

    func cancel() {
        requestID = UUID()
        task?.cancel()
        task = nil
    }

    static func request(title: String, artist: String, album: String, duration: Double) -> URLRequest {
        var url = URLComponents(string: "https://lrclib.net/api/get")!
        url.queryItems = [URLQueryItem(name: "track_name", value: title),
                          URLQueryItem(name: "artist_name", value: artist),
                          URLQueryItem(name: "album_name", value: album)]
        if duration.isFinite && duration > 0 && duration < 86400 {
            url.queryItems?.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded()))))
        }
        var request = URLRequest(url: url.url!, timeoutInterval: 15)
        request.setValue("LockSleeve/0.2 (https://github.com/donghyun-0503/lockSleeve)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    // Accessed on the main queue; stale or cancelled requests never deliver results.
    func fetch(key: String, title: String, artist: String, album: String, duration: Double,
               completion: @escaping (String?) -> Void) {
        cancel()
        if let entry = cache[key], entry.expires > Date() {
            status = entry.status
            completion(entry.source)
            return
        }
        status = "가사 찾는 중…"
        let id = requestID
        func finish(_ source: String?, _ message: String) {
            guard self.requestID == id else { return }
            self.task = nil
            self.status = message
            if self.cache.count >= 50 { self.cache.removeAll() }
            self.cache[key] = (source, message, Date().addingTimeInterval(source == nil ? 60 : 3600))
            completion(source)
        }
        func fetchSearch() {
            var url = URLComponents(string: "https://lrclib.net/api/search")!
            url.queryItems = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
            var request = URLRequest(url: url.url!, timeoutInterval: 15)
            request.setValue("LockSleeve/0.2 (https://github.com/donghyun-0503/lockSleeve)", forHTTPHeaderField: "User-Agent")
            self.load(request, id: id) { data, response, error in
                let code = (response as? HTTPURLResponse)?.statusCode
                let records = data.flatMap { try? JSONDecoder().decode([LyricsRecord].self, from: $0) }
                DispatchQueue.main.async {
                    guard self.requestID == id else { return }
                    guard error == nil, code == 200, let records else {
                        finish(nil, Self.failureMessage(code: code, error: error, invalidResponse: code == 200))
                        return
                    }
                    let source = Self.bestMatch(records, title: title, artist: artist, duration: duration)?.source
                    finish(source, source == nil ? "이 곡의 가사를 찾지 못했어요" : "가사 연결됨")
                }
            }
        }
        load(Self.request(title: title, artist: artist, album: album, duration: duration), id: id) { data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode
            let record = data.flatMap { try? JSONDecoder().decode(LyricsRecord.self, from: $0) }
            DispatchQueue.main.async {
                guard self.requestID == id else { return }
                if error == nil, code == 200, let record, let source = record.source {
                    finish(source, "가사 연결됨")
                } else if error == nil, code == 404 || code == 429 || (code ?? 0) >= 500 || (code == 200 && record != nil) {
                    fetchSearch()
                } else {
                    finish(nil, Self.failureMessage(code: code, error: error, invalidResponse: code == 200))
                }
            }
        }
    }

    // Retry temporary failures once; cancel invalidates both running and delayed work.
    private func load(_ request: URLRequest, id: UUID, attempt: Int = 0,
                      completion: @escaping (Data?, URLResponse?, Error?) -> Void) {
        guard requestID == id else { return }
        task = session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self, self.requestID == id else { return }
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                let network = (error as? URLError)?.code
                let temporary = code == 429 || (500...599).contains(code)
                    || network == .timedOut || network == .networkConnectionLost
                if temporary && attempt == 0 {
                    self.status = "가사 서버 응답 재시도 중…"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                        self?.load(request, id: id, attempt: attempt + 1, completion: completion)
                    }
                } else { completion(data, response, error) }
            }
        }
        task?.resume()
    }

    static func failureMessage(code: Int?, error: Error?, invalidResponse: Bool = false) -> String {
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet: return "인터넷 연결 없음 · 재시도 예정"
            case .timedOut: return "가사 서버 응답 지연 · 재시도 예정"
            default: return "가사 통신 오류 (\(error.errorCode)) · 재시도 예정"
            }
        }
        if code == 429 { return "가사 서버 요청 제한 (429) · 재시도 예정" }
        if let code, (500...599).contains(code) { return "가사 서버 혼잡 (\(code)) · 재시도 예정" }
        if invalidResponse { return "가사 서버 응답 형식 오류 · 재시도 예정" }
        return "가사 조회 오류 (HTTP \(code ?? 0)) · 재시도 예정"
    }

    static func bestMatch(_ records: [LyricsRecord], title: String, artist: String, duration: Double) -> LyricsRecord? {
        func normalize(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
        }
        return records.filter {
            normalize($0.trackName ?? "") == normalize(title) && normalize($0.artistName ?? "") == normalize(artist)
                && (duration <= 0 || abs(($0.duration ?? -100) - duration) <= 3) && $0.source != nil
        }.sorted {
            let leftSynced = !SongLyrics($0.syncedLyrics ?? "").lines.isEmpty
            let rightSynced = !SongLyrics($1.syncedLyrics ?? "").lines.isEmpty
            if leftSynced != rightSynced { return leftSynced }
            return abs(($0.duration ?? 0) - duration) < abs(($1.duration ?? 0) - duration)
        }.first
    }
}
