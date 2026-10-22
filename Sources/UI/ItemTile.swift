import AppKit
import SwiftUI

/// The 44 pt icon tile at the start of a history row. Images show their real
/// thumbnail; every other kind gets a small drawn glyph that says what the
/// item is at a glance.
struct ItemTile: View {
    let style: ItemStyle
    let thumbnail: NSImage?

    var body: some View {
        glyph
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    @ViewBuilder
    private var glyph: some View {
        switch style {
        case .url:
            BrowserGlyph()
        case .code:
            CodeGlyph()
        case .terminal:
            ZStack {
                Color(hex: "#07090A")
                Text("$_")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(hex: "#7CF29A"))
            }
        case .color(let hex):
            ZStack(alignment: .bottomTrailing) {
                Color(hex: hex)
                CornerTriangle()
                    .fill(Color(hex: "#16161D"))
                    .frame(width: 16, height: 16)
            }
        case .text:
            ZStack {
                Color(hex: "#14261F")
                Text("Aa")
                    .font(.system(size: 19, design: .serif).italic())
                    .foregroundStyle(Color(hex: "#8FE3C6"))
            }
        case .image:
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                SunsetGlyph()
            }
        case .file(let kind):
            if kind == .pdf {
                PDFGlyph()
            } else {
                ZStack {
                    Color(hex: kind.color)
                    Image(systemName: kind.symbol)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
        case .secret:
            ZStack {
                Color(hex: "#2B2214")
                Image(systemName: "key")
                    .font(.system(size: 17, weight: .semibold))
                    .rotationEffect(.degrees(-45))
                    .foregroundStyle(Color(hex: "#FFC062"))
            }
        }
    }
}

// MARK: - Glyphs

/// A tiny browser window: traffic lights, a title bar, two content blocks.
private struct BrowserGlyph: View {
    var body: some View {
        ZStack {
            Color(hex: "#10141C")
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 2.5) {
                    Circle().fill(Color(hex: "#FF5F57")).frame(width: 4, height: 4)
                    Circle().fill(Color(hex: "#FEBC2E")).frame(width: 4, height: 4)
                    Circle().fill(Color(hex: "#28C840")).frame(width: 4, height: 4)
                }
                Capsule().fill(Color(hex: "#7AB0FF")).frame(width: 24, height: 3)
                Capsule().fill(Color.white.opacity(0.25)).frame(width: 30, height: 2)
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(hex: "#2A3448"))
                    RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.1))
                }
                .frame(height: 7)
            }
            .padding(6)
        }
    }
}

/// Three indented rows of syntax-colored dashes.
private struct CodeGlyph: View {
    private let rows: [(indent: CGFloat, dashes: [(width: CGFloat, hex: String)])] = [
        (0, [(10, "#C792EA"), (4, "#EEEEEE"), (8, "#82AAFF")]),
        (4, [(6, "#82AAFF"), (12, "#C792EA")]),
        (0, [(8, "#C3E88D"), (9, "#C792EA")]),
    ]

    var body: some View {
        ZStack {
            Color(hex: "#0D0F14")
            VStack(alignment: .leading, spacing: 4) {
                ForEach(rows.indices, id: \.self) { index in
                    HStack(spacing: 2.5) {
                        ForEach(rows[index].dashes.indices, id: \.self) { dash in
                            Capsule()
                                .fill(Color(hex: rows[index].dashes[dash].hex))
                                .frame(width: rows[index].dashes[dash].width, height: 3)
                        }
                    }
                    .padding(.leading, rows[index].indent)
                }
            }
        }
    }
}

/// A placeholder landscape for images without a thumbnail.
private struct SunsetGlyph: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#3B2A6B"), Color(hex: "#C05A8A")],
                startPoint: .top, endPoint: .bottom
            )
            Circle()
                .fill(Color(hex: "#FFF1B8"))
                .frame(width: 11, height: 11)
                .offset(x: 8, y: -7)
            Mountains()
                .fill(Color(hex: "#2A1E3F"))
        }
    }
}

private struct Mountains: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.22))
        path.addLine(to: CGPoint(x: rect.width * 0.3, y: rect.maxY - rect.height * 0.42))
        path.addLine(to: CGPoint(x: rect.width * 0.5, y: rect.maxY - rect.height * 0.26))
        path.addLine(to: CGPoint(x: rect.width * 0.72, y: rect.maxY - rect.height * 0.46))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.2))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A sheet of paper with a red PDF tag.
private struct PDFGlyph: View {
    var body: some View {
        ZStack {
            Color(hex: "#2A2620")
            ZStack(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 3) {
                    Capsule().fill(Color(hex: "#2B2B2B")).frame(width: 14, height: 2)
                    Capsule().fill(Color(hex: "#BDB6A8")).frame(width: 18, height: 2)
                    Capsule().fill(Color(hex: "#BDB6A8")).frame(width: 15, height: 2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
                .frame(width: 26, height: 33, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 3).fill(Color(hex: "#F5F1E8"))
                )
                Text("PDF")
                    .font(.system(size: 6.5, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 2).fill(Color(hex: "#E5484D")))
                    .offset(x: -3, y: -4)
            }
        }
    }
}

/// The lower-right half of a square.
private struct CornerTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
