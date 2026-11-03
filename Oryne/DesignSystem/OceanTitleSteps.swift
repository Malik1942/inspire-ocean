import SwiftUI

extension OceanType {
    /// A thought's name where it is the subject (Tide's stage, its own
    /// page): it steps down a size as it grows, 34, 28 then 24 pt, rather
    /// than squeeze to fit. Stepped by how long it reads
    /// (`TitleLength.weighted`, a Chinese character counting 2) against
    /// `thoughtTitleSteps`, so a Chinese title steps where an English one
    /// twice as many characters long does.
    static func thoughtTitle(for title: String) -> OceanTextRole {
        let length = TitleLength.weighted(title)
        if length <= thoughtTitleSteps.long { return thoughtTitle }
        if length <= thoughtTitleSteps.longest { return thoughtTitleLong }
        return thoughtTitleLongest
    }
}
