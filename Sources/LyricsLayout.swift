import AppKit

struct LyricsFrame: Codable, Equatable {
    let trackID: String
    let texts: [String]
    let activeIndex: Int
    let synced: Bool
}
struct LyricPlacement {
    let index: Int
    let rect: CGRect
    let opacity: Float
}
enum LyricsLayout {
    static func area(_ size: CGSize) -> CGRect {
        CGRect(x: size.width * 0.51, y: size.height * 0.27, width: size.width * 0.37, height: size.height * 0.45)
    }
    static func attributes(_ size: CGSize) -> [NSAttributedString.Key: Any] {
        let font = min(size.height * 0.039, size.width * 0.029)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = font * 0.02
        return [.font: NSFont.systemFont(ofSize: font, weight: .bold), .foregroundColor: NSColor.white, .paragraphStyle: paragraph]
    }
    static func text(_ frame: LyricsFrame, at index: Int) -> String {
        frame.texts[index].isEmpty ? "•••" : frame.texts[index]
    }
    static func placements(_ frame: LyricsFrame, size: CGSize) -> [LyricPlacement] {
        guard !frame.texts.isEmpty else { return [] }
        let area = area(size)
        let attributes = attributes(size)
        let gap = size.height * 0.018
        let focus = max(0, min(frame.activeIndex, frame.texts.count - 1))
        let visibleStart = max(0, min(focus - 1, frame.texts.count - 4))
        let visibleEnd = min(frame.texts.count - 1, visibleStart + 3)
        // Keep an extra row outside each edge for the scrolling animation.
        let indices = max(0, visibleStart - 1)...min(frame.texts.count - 1, visibleEnd + 1)
        var heights: [Int: CGFloat] = [:]
        for index in indices {
            heights[index] = ceil((text(frame, at: index) as NSString).boundingRect(with: CGSize(width: area.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes).height)
        }
        // Fill the four-row window even during the intro and final phrases.
        let precedingHeight = (visibleStart..<focus).reduce(CGFloat.zero) { $0 + heights[$1]! + gap }
        let focusTop = area.maxY - size.height * 0.025 - precedingHeight
        var bottoms: [Int: CGFloat] = [focus: focusTop - heights[focus]!]
        if focus > indices.lowerBound {
            for index in stride(from: focus - 1, through: indices.lowerBound, by: -1) {
                bottoms[index] = bottoms[index + 1]! + heights[index + 1]! + gap
            }
        }
        if focus < indices.upperBound {
            for index in (focus + 1)...indices.upperBound {
                bottoms[index] = bottoms[index - 1]! - gap - heights[index]!
            }
        }
        return indices.map { index in
            let opacity: Float = (index < visibleStart || index > visibleEnd) ? 0 : (!frame.synced ? 1 : (index == frame.activeIndex ? 1 : (index < frame.activeIndex ? 0.22 : 0.36)))
            return LyricPlacement(index: index, rect: CGRect(x: area.minX, y: bottoms[index]!, width: area.width, height: heights[index]!), opacity: opacity)
        }
    }
}
