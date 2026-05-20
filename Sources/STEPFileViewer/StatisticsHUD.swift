import SwiftUI

struct StatisticsHUD: View {
    let stats: ModelStatistics
    let fileName: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            if let name = fileName {
                Text(name)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.bottom, 2)
            }
            if stats.hasGeometry {
                row("tris", value: format(stats.triangles))
                if stats.quads > 0 { row("quads", value: format(stats.quads)) }
                if stats.ngons > 0 { row("ngons", value: format(stats.ngons)) }
                if stats.lines > 0 { row("lines", value: format(stats.lines)) }
                if stats.points > 0 { row("points", value: format(stats.points)) }
                row("verts", value: format(stats.vertices))
                if stats.meshes > 1 { row("meshes", value: format(stats.meshes)) }
                Divider()
                    .frame(width: 100)
                    .overlay(Color.white.opacity(0.18))
                    .padding(.vertical, 2)
                row("x", value: dim(stats.sizeX))
                row("y", value: dim(stats.sizeY))
                row("z", value: dim(stats.sizeZ))
            } else if fileName != nil {
                Text("no geometry")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    private func row(_ label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.92))
                .frame(minWidth: 56, alignment: .trailing)
        }
    }

    private func format(_ n: Int) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.groupingSeparator = ","
        return nf.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func dim(_ v: Float) -> String {
        if v == 0 { return "0" }
        let absV = abs(v)
        if absV >= 1000 { return String(format: "%.0f", v) }
        if absV >= 10 { return String(format: "%.2f", v) }
        return String(format: "%.3f", v)
    }
}
