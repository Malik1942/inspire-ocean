import SwiftUI

/// Display type for the Tide page: New York, Apple's serif, in three places
/// only (the page title, the italic section labels, the resurfacing title);
/// the system sans everywhere else. Both faces come from the system, share
/// optical sizing, and follow Dynamic Type.
enum OceanType {
    static var pageTitle: Font { .system(size: 40, weight: .regular, design: .serif) }
    static var sectionLabel: Font { .system(size: 21, weight: .regular, design: .serif).italic() }
    static var resurfacingTitle: Font { .system(size: 32, weight: .regular, design: .serif) }
}
