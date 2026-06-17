import SwiftUI

struct DiagnosticView: View {
    let diagnostics: [DiagnosticIssue]

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("诊断信息 (\(diagnostics.count))", systemImage: "exclamationmark.bubble")
                    .font(.headline)
                    .foregroundColor(diagnostics.contains { $0.title.contains("失败") || $0.title.contains("错误") } ? .red : .orange)

                ForEach(diagnostics) { issue in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text(issue.title)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }

                        Text(issue.detail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 22)

                        HStack(spacing: 4) {
                            Image(systemName: "lightbulb")
                                .font(.caption2)
                                .foregroundColor(.blue)
                            Text(issue.suggestion)
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        .padding(.leading, 22)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .groupBoxStyle(.card)
    }
}
