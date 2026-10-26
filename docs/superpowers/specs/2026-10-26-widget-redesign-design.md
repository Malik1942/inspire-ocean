# Widget redesign

Date: 2026-10-26

Bring the existing iOS widgets into the current token system and make saved
images, enriched links, whispers and Ask reachable from the Home Screen.

## Design

Use the existing OceanType, OceanSpacing, OceanRadius and OceanSurface roles.
Keep WidgetKit's native margins and removable background. Section labels use the shared New York serif role in a warm tone; titles use New York on medium and large families; metadata stays SF.
Tinted and clear appearances retain image detail through desaturated images.

Quick Capture keeps its small, medium and circular families. Small remains
one tap using the preferred input. Medium has two equal-width Thought and Whisper capsules, with 12 pt between
them and the shared 16 pt control insets. The redundant Home Screen Oryne
header is removed. Rectangular and inline Lock Screen launchers make capture
available without a circular slot. Voice still opens the existing recorder.

The medium capture layout groups its serif title with the existing supporting
line, 6 pt apart. A fixed 24 pt gap separates this group from the two actions;
the whole group is vertically centered rather than stretched between edges.
An extra 4 pt inset inside WidgetKit's margins gives the title and actions
the same leading/trailing alignment. Accessibility sizes omit the helper line.

Resurfacing keeps its stable kind and shared daily selection. Small and medium
show an attached image or enriched link thumbnail, the thought's kind and
source domain when present. Large adds a reading area and the same two-action row as Capture. Ask is
a separate quiet link in its header, not a third capture button. The thought opens through its existing node link; actions have
their own links. User content is privacy sensitive. Accessory layouts stay
compact and use system ink. No empty-state spacers push text out of a Lock
Screen rectangle.

The provider bounds thumbnail decoding before producing the timeline. Missing
or invalid images fall back to text. Repeated title/snippet text is omitted.
An unreadable store asks the user to open Oryne; no eligible thought explains
that thoughts need time to return. Neither state pretends a memory was found.
All widget copy and gallery metadata ship in English and Simplified Chinese.

## Scope and verification

Existing capture flows, daily selection, model schema, watch complications and
token definitions remain intact. Add only an Ask deep-link entry to the
existing tab. Generate the local Xcode project, build app and extensions, run
SharedTests, validate token use and localization, and inspect rendered widget
families with populated, empty, inaccessible-store and long-text examples.

The Ask entry parks an open composer through its existing put-away path,
preserving its draft. Loading pictures finish before it parks. Recording or
saving keeps the existing completion path; navigation never discards a take.
Fixed 44 pt action labels cap at the largest standard type size; saved words
continue to follow accessibility sizes, with secondary content reduced.
An unreadable-store timeline retries after 30 minutes instead of waiting
until the next day's pick.
