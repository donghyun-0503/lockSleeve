import Foundation

@main struct LyricsTests {
    static func main() {
        let lrc = SongLyrics("[offset:-500]\n[00:02.50][01:02.50]repeat\n[00:05.00]\n[00:08.10]first\n[00:08.10]translation\n[00:99.00]invalid")
        precondition(lrc.lines.map(\.time) == [2, 4.5, 7.6, 62])
        precondition(lrc.lines[1].text.isEmpty)
        precondition(lrc.lines[2].text == "first\ntranslation")
        precondition(lrc.activeIndex(at: 0) == -1)
        precondition(lrc.activeIndex(at: 2) == 0)
        precondition(lrc.activeIndex(at: 5) == 1)
        precondition(lrc.activeIndex(at: 70) == 3)
        precondition(lrc.activeIndex(at: 3) == 0, "Seeking backward must select the earlier line")
        precondition(SongLyrics("hello\nworld").plain == ["hello", "world"])
        precondition(!SongLyrics("").available)
        precondition(!SongLyrics("[ar:Artist]\n[ti:Title]").available)
        precondition(SongLyrics("[00:00.00]한글 가사").lines.first?.text == "한글 가사")
        print("Lyrics parser: 12 checks passed")
    }
}
