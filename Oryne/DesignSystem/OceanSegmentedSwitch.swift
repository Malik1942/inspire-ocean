import SwiftUI

/// Two ways of looking at one page (the Library's Recent and Currents): the
/// search field's matte capsule, with the one in use a step brighter inside
/// it. A Secondary control in two parts: it scrolls with the page, so no
/// glass, and it is 44 pt tall like every control. It hugs its labels, each
/// part as wide as the widest, so it never reads as a second field under
/// the search.
struct OceanSegmentedSwitch<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: LocalizedStringKey)]

    @Namespace private var thumb
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        EqualWidthRow {
            ForEach(options.indices, id: \.self) { index in
                part(options[index])
            }
        }
        .padding(4)
        .frame(height: OceanControlSize.height)
        .background(OceanSurface(shape: Capsule()))
        .accessibilityElement(children: .contain)
    }

    private func part(_ option: (value: Value, title: LocalizedStringKey)) -> some View {
        let selected = option.value == selection
        return Button {
            withAnimation(reduceMotion ? OceanMotion.quick : OceanMotion.standard) {
                selection = option.value
            }
        } label: {
            Text(option.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(selected ? OceanTheme.foam : OceanTheme.mist)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if selected {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
                            .matchedGeometryEffect(id: "thumb", in: thumb)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Its children in a row, each as wide as the widest of them.
private struct EqualWidthRow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let ideals = subviews.map { $0.sizeThatFits(.unspecified) }
        let widest = ideals.map(\.width).max() ?? 0
        let height = proposal.height ?? ideals.map(\.height).max() ?? 0
        return CGSize(width: widest * CGFloat(subviews.count), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        guard !subviews.isEmpty else { return }
        let width = bounds.width / CGFloat(subviews.count)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + CGFloat(index) * width, y: bounds.minY),
                          proposal: ProposedViewSize(width: width, height: bounds.height))
        }
    }
}
