import SwiftUI

struct StatisticsHUD: View {
    let stats: ModelStatistics
    @Binding var wireframe: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            row("tris", value: format(stats.triangles))
            if stats.quads > 0 { row("quads", value: format(stats.quads)) }
            if stats.ngons > 0 { row("ngons", value: format(stats.ngons)) }
            if stats.lines > 0 { row("lines", value: format(stats.lines)) }
            if stats.points > 0 { row("points", value: format(stats.points)) }
            row("verts", value: format(stats.vertices))
            if stats.meshes > 1 { row("meshes", value: format(stats.meshes)) }

            divider
            row("x", value: dim(stats.sizeX))
            row("y", value: dim(stats.sizeY))
            row("z", value: dim(stats.sizeZ))

            divider
            wireframeButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
        )
    }

    private var divider: some View {
        Divider()
            .frame(width: 104)
            .overlay(Color.primary.opacity(0.15))
            .padding(.vertical, 2)
    }

    private var wireframeButton: some View {
        Button {
            wireframe.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 9, weight: .semibold))
                Text("wireframe")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(wireframe ? Color.white : Color.primary.opacity(0.85))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(wireframe ? Color.accentColor : Color.primary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .help("Toggle wireframe rendering")
    }

    private func row(_ label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
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
