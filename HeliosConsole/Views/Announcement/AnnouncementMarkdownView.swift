//
//  AnnouncementMarkdownView.swift
//  HeliosConsole
//
//  A lightweight Markdown renderer for announcement bodies.
//
//  SwiftUI's `Text` only auto-parses Markdown from string *literals*, and even
//  `AttributedString(markdown:)` handles only *inline* styling (bold, italic,
//  links) — not block elements. Announcement messages are authored with block
//  Markdown: `**bold**` section headings, `*italic*`, `-`/`*` bullet lists, and
//  blank-line paragraph breaks. This view parses those blocks and renders each
//  one, delegating inline styling within a line to `AttributedString(markdown:)`.
//
//  Font, foreground color, and line spacing are inherited from the environment,
//  so callers style it exactly like the `Text` it replaces:
//
//      AnnouncementMarkdownView(text: announcement.message)
//          .font(.system(size: 15))
//          .foregroundColor(.primary)
//

import SwiftUI

struct AnnouncementMarkdownView: View {
    let text: String

    private var blocks: [MarkdownBlock] { MarkdownBlock.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                switch block.kind {
                case .paragraph(let line):
                    inlineMarkdown(line)
                        .fixedSize(horizontal: false, vertical: true)

                case .bullets(let items):
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                inlineMarkdown(item)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Render a single line's inline Markdown (bold/italic/links) as `Text`,
    /// falling back to the raw string if parsing fails.
    private func inlineMarkdown(_ line: String) -> Text {
        Text(AnnouncementMarkdownView.inlineAttributed(line))
    }

    /// Parse inline Markdown for a single line, preserving surrounding whitespace.
    static func inlineAttributed(_ line: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: line, options: options)) ?? AttributedString(line)
    }
}

/// A parsed block of announcement Markdown.
private struct MarkdownBlock: Identifiable {
    enum Kind {
        case paragraph(String)
        case bullets([String])
    }

    let id = UUID()
    let kind: Kind

    /// Split a Markdown string into paragraph and bullet-list blocks.
    /// Consecutive bullet lines are grouped into one list; blank lines separate
    /// blocks (the enclosing `VStack` spacing provides the visual gap).
    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var bulletBuffer: [String] = []

        func flushBullets() {
            if !bulletBuffer.isEmpty {
                blocks.append(MarkdownBlock(kind: .bullets(bulletBuffer)))
                bulletBuffer.removeAll()
            }
        }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flushBullets()
                continue
            }

            if let bulletBody = bulletContent(of: line) {
                bulletBuffer.append(bulletBody)
            } else {
                flushBullets()
                blocks.append(MarkdownBlock(kind: .paragraph(line)))
            }
        }
        flushBullets()
        return blocks
    }

    /// If `line` is a Markdown bullet (`- ` or `* `), return the text after the
    /// marker; otherwise nil. A bare `*bold*` line is not treated as a bullet.
    private static func bulletContent(of line: String) -> String? {
        for marker in ["- ", "* "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}
