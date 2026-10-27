import SwiftUI
import WidgetKit

struct OceanWidgetImage: View {
    let data: Data

    var body: some View {
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .widgetAccentedRenderingMode(.desaturated)
                .scaledToFill()
                .accessibilityHidden(true)
        }
    }
}
