import SwiftUI

struct RenderDebugPanel: View {
    let fps: Double?
    let info: RenderDebugInfo?
    let availableGeometries: [String]
    let selectedGeometry: String
    let onSelectGeometry: ((String) -> Void)?
    let modelTextureEnabled: Bool
    let onToggleModelTexture: (() -> Void)?
    let leadingPadding: CGFloat
    let topPadding: CGFloat
    let contentLeadingPadding: CGFloat

    init(
        fps: Double?,
        info: RenderDebugInfo?,
        availableGeometries: [String],
        selectedGeometry: String,
        onSelectGeometry: ((String) -> Void)?,
        modelTextureEnabled: Bool = true,
        onToggleModelTexture: (() -> Void)? = nil,
        leadingPadding: CGFloat = 16,
        topPadding: CGFloat = 12,
        contentLeadingPadding: CGFloat = 4
    ) {
        self.fps = fps
        self.info = info
        self.availableGeometries = availableGeometries
        self.selectedGeometry = selectedGeometry
        self.onSelectGeometry = onSelectGeometry
        self.modelTextureEnabled = modelTextureEnabled
        self.onToggleModelTexture = onToggleModelTexture
        self.leadingPadding = leadingPadding
        self.topPadding = topPadding
        self.contentLeadingPadding = contentLeadingPadding
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Render Debug")
                .font(.system(.caption, design: .rounded))
                .foregroundColor(.white.opacity(0.9))

            debugRow(label: "FPS",      value: fps.map { String(format: "%.1f", $0) } ?? "-")
            debugRow(label: "Session",  value: info.map { String($0.sessionId.prefix(8)) } ?? "-")
            debugRow(label: "Geometry", value: info?.geometryName ?? "-",
                     tint: info != nil ? .green : nil,
                     underline: info != nil)
            debugRow(label: "Pipelines", value: info.map { String($0.pipelineCacheCount) } ?? "-")
            debugRow(label: "Snapshot",  value: info.map { $0.snapshotReady ? "ready" : "waiting" } ?? "-")
            debugRow(label: "Texture",   value: info.map { $0.textureReady ? "ready" : "none" } ?? "-")
            debugRow(label: "Model",
                     value: info.map { $0.modelStatus.rawValue } ?? "-",
                     tint:  info.map { statusColor($0.modelStatus) })
            debugRow(label: "Submeshes",
                     value: info.map { "\($0.submeshCount) (\($0.texturedSubmeshCount) textured)" } ?? "-",
                     tint:  info.map { $0.submeshCount > 0 ? .cyan : .white.opacity(0.7) })
            debugRow(label: "CamZ",
                     value: info.map { String(format: "%.2f", $0.cameraDistance) } ?? "-")
            if let onToggleModelTexture {
                HStack(spacing: 4) {
                    Text("ModelTex:")
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 62, alignment: .leading)
                    Button {
                        onToggleModelTexture()
                    } label: {
                        Text(modelTextureEnabled ? "on" : "off")
                            .foregroundColor(modelTextureEnabled ? .green : .white)
                            .underline(modelTextureEnabled, color: .green)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 5)
                            .background(Color.white.opacity(modelTextureEnabled ? 0.12 : 0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Toggle model texture")
                    .accessibilityValue(modelTextureEnabled ? "enabled" : "disabled")
                }
            }

            if !availableGeometries.isEmpty, let onSelectGeometry {
                HStack(spacing: 4) {
                    Text("Select:")
                        .foregroundColor(.white.opacity(0.7))
                    ForEach(availableGeometries, id: \.self) { name in
                        Button {
                            onSelectGeometry(name)
                        } label: {
                            Text(name)
                                .foregroundColor(name == selectedGeometry ? .green : .white)
                                .underline(name == selectedGeometry, color: .green)
                                .padding(.vertical, 2)
                                .padding(.horizontal, 5)
                                .background(Color.white.opacity(name == selectedGeometry ? 0.12 : 0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Select geometry: \(name)")
                        .accessibilityValue(name == selectedGeometry ? "selected" : "not selected")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.leading, contentLeadingPadding)
        .padding(6)
        .background(Color.black.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .font(.system(.caption, design: .monospaced))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Render debug panel")
        .fixedSize(horizontal: true, vertical: false)
        .padding(.leading, leadingPadding)
        .padding(.top, topPadding)
    }

    private func debugRow(
        label: String,
        value: String,
        tint: Color? = nil,
        underline: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(label):")
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 62, alignment: .leading)
            Text(value)
                .foregroundColor(tint ?? .white)
                .underline(underline, color: tint ?? .white)
        }
    }

    private func statusColor(_ status: ModelLoadStatus) -> Color {
        switch status {
        case .ok:                                    return .green
        case .missingAttributes:                     return .yellow
        case .missing, .unsupportedIndexType, .failed: return .red
        case .loading:                               return .orange
        case .notApplicable:                         return .white.opacity(0.7)
        }
    }
}
