import AppKit
@main struct LayoutTests {
 static func main() throws {
  let texts = ["A previous phrase with enough words to wrap onto a second line", "The current phrase has room to breathe", "The next phrase waits quietly", "Another phrase", "A fifth phrase", "A sixth phrase"]
  for size in [CGSize(width:1512,height:982), CGSize(width:1920,height:1080), CGSize(width:1080,height:1920)] {
   let state = LyricsFrame(trackID:"test",texts:texts,activeIndex:1,synced:true)
   let rows = LyricsLayout.placements(state,size:size)
   let focus=rows.first { $0.index == 1 }!
   precondition(rows.filter { $0.opacity > 0 }.count == 4)
   precondition(LyricsLayout.area(size).contains(focus.rect))
   precondition(focus.opacity == 1)
   let previous=rows.first { $0.index == 0 }!
   let next=rows.first { $0.index == 2 }!
   precondition(previous.rect.minY-focus.rect.maxY >= size.height*0.017)
   precondition(focus.rect.minY-next.rect.maxY >= size.height*0.017)
   precondition(previous.opacity < next.opacity && next.opacity < focus.opacity)
   let moved=LyricsLayout.placements(LyricsFrame(trackID:"test",texts:texts,activeIndex:2,synced:true),size:size).first { $0.index == 1 }!
   precondition(moved.rect.minY > focus.rect.minY, "The old current row must slide upwards")
   let data=try JSONEncoder().encode(state)
   let decoded = try JSONDecoder().decode(LyricsFrame.self,from:data)
   precondition(decoded == state)
  }
  let six = ["one", "two", "three", "four", "five", "six"]
  for index in [-1, 0, 1, 4, 5] {
   let rows = LyricsLayout.placements(LyricsFrame(trackID:"edges",texts:six,activeIndex:index,synced:true),size:CGSize(width:1512,height:982))
   precondition(rows.filter { $0.opacity > 0 }.count == 4)
  }
  precondition(LyricsLayout.placements(LyricsFrame(trackID:"empty",texts:[],activeIndex:-1,synced:true),size:CGSize(width:1512,height:982)).isEmpty)
  print("PASS: reading anchor, safe bounds, paragraph spacing, emphasis, scrolling direction, frame serialization, empty lyrics")
 }
}
