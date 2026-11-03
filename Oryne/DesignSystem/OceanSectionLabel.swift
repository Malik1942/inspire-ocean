import SwiftUI

/// Every label over what it names: a section (Drifted in, Currents,
/// Nearby), a block (Summary, Transcript, Drawn from), a field's name, a
/// Settings header. Oryne's word, so SF `sectionLabel` in mist, a little
/// tracked, with a 2 pt lead-in over the gutter; one voice for every label,
/// so a section and a block are told apart by the space above them, never
/// by their type.
///
/// With an accessory (a quiet Link, Listen and the language menu) the row
/// is the controls' 44 pt; what follows sits right under it.
struct OceanSectionLabel<Accessory: View>: View {
    let title: Text
    var systemImage: String? = nil
    let accessory: Accessory

    init(_ title: Text, systemImage: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.systemImage = systemImage
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: OceanSpacing.gap) {
            label
            if Accessory.self != EmptyView.self {
                Spacer(minLength: OceanSpacing.gap)
                accessory
            }
        }
    }

    private var label: some View {
        Group {
            if let systemImage {
                Label { title } icon: { Image(systemName: systemImage) }
                    .labelStyle(OceanControlLabelStyle())
            } else {
                title
            }
        }
        .oceanText(OceanType.sectionLabel)
        .foregroundStyle(OceanTheme.mist)
        .padding(.leading, OceanSpacing.hairline)
        .accessibilityAddTraits(.isHeader)
    }
}

extension OceanSectionLabel {
    init(_ titleKey: LocalizedStringKey, systemImage: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.init(Text(titleKey), systemImage: systemImage, accessory: accessory)
    }
}

extension OceanSectionLabel where Accessory == EmptyView {
    init(_ title: Text, systemImage: String? = nil) {
        self.init(title, systemImage: systemImage) { EmptyView() }
    }

    init(_ titleKey: LocalizedStringKey, systemImage: String? = nil) {
        self.init(Text(titleKey), systemImage: systemImage)
    }
}
