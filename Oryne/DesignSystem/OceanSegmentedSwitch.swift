import SwiftUI

/// Two ways of looking at one page (the Library's Recent and Currents),
/// as Weather switches its layers: glyph cells in the page's tool group,
/// the one in use on a selected fill. The words stay for VoiceOver. It
/// lives inside an `OceanToolGroup` (a `PageTitleRow`'s tools), beside the
/// page's other tools past an `OceanToolDivider`.
struct OceanSegmentedSwitch<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: LocalizedStringKey, systemImage: String)]

    @Namespace private var thumb
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.oceanToolCellWidth) private var cellWidth

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                cell(options[index])
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func cell(_ option: (value: Value, title: LocalizedStringKey, systemImage: String)) -> some View {
        let selected = option.value == selection
        return Button {
            withAnimation(reduceMotion ? OceanMotion.quick : OceanMotion.standard) {
                selection = option.value
            }
        } label: {
            Image(systemName: option.systemImage)
                .font(OceanType.glyph)
                .foregroundStyle(selected ? OceanTheme.foam : OceanTheme.mist)
                .frame(width: cellWidth, height: OceanControlSize.height)
                .background {
                    if selected {
                        Capsule()
                            .fill(OceanTheme.selected)
                            .padding(OceanSpacing.tight)
                            .matchedGeometryEffect(id: "thumb", in: thumb)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A hairline between two kinds of tool in one group, as Weather draws
/// between its layers and its wind.
struct OceanToolDivider: View {
    var body: some View {
        Rectangle()
            .fill(OceanTheme.faint)
            .frame(width: 1, height: OceanControlSize.height / 2)
            .padding(.horizontal, OceanSpacing.tight)
            .accessibilityHidden(true)
    }
}
