/// Size, spacing and radius tokens from docs/design/DESIGN-SPEC.md section 3
/// (style D). No shadows: separation comes from borders.
abstract final class Dimens {
  // Page.
  static const pagePadding = 24.0;

  /// Top padding of pushed screens (the back-link row).
  static const pageTopPushed = 8.0;

  /// Bottom padding. The bar is laid out below the page (not over it), so
  /// tab screens need only the spec's 24 above it; pushed screens get 32.
  static const pageBottom = 24.0;
  static const pageBottomPushed = 32.0;

  // Gaps.
  static const sectionGap = 24.0;
  static const cardGap = 16.0;
  static const gridGap = 16.0;
  static const buttonGap = 12.0;
  static const tightGap = 8.0;

  /// Between a label and the line under it.
  static const textGap = 4.0;

  // Cards.
  static const cardPadding = 24.0;
  static const smallCardPadding = 16.0;

  /// Horizontal padding of link cards and banners ("padding 16 20").
  static const linkCardPaddingH = 20.0;

  // Radii.
  static const radiusStatusCard = 20.0;
  static const radiusViewfinder = 24.0;
  static const radiusCard = 16.0;
  static const radiusAnswer = 14.0;
  static const radiusInner = 12.0;
  static const radiusPill = 999.0;

  // Borders.
  static const outlineWidth = 1.5;
  static const dividerWidth = 1.0;

  // Heights and touch targets.
  static const minTouchTarget = 48.0;
  static const buttonHeight = 56.0;
  static const listRowHeight = 72.0;
  static const listRowCircle = 40.0;
  static const listRowIcon = 22.0;
  static const footChipHeight = 72.0;
  static const footCheckCardHeight = 88.0;
  static const linkRowHeight = 48.0;
  static const captureControl = 64.0;
  static const shutter = 80.0;

  // Status card.
  static const statusIconCircle = 56.0;
  static const statusIcon = 32.0;

  // Icons.
  static const iconButtonIcon = 24.0;
  static const smallCardIcon = 20.0;
  static const inlineIcon = 16.0;
  static const iconCircle = 48.0;

  // Foot chips.
  static const chipDot = 12.0;
  static const chipDotRing = 2.0;

  /// Indent of the chip's second line (dot + gap).
  static const chipIndent = 20.0;

  // Home foot maps (DESIGN-SPEC §5: 84×188, 48 apart).
  static const homeFootWidth = 84.0;
  static const homeFootHeight = 188.0;
  static const homeFootGap = 48.0;

  // My feet foot maps (DESIGN-SPEC §5: 108×241, 40 apart).
  static const feetFootWidth = 108.0;
  static const feetFootHeight = 241.0;
  static const feetFootGap = 40.0;

  /// A top-zone row's dot is the level's radius × this (§8.1).
  static const zoneRowDotScale = 0.8;

  // Summary banner (§5): padding 16 20, gap 12, 44 circle, 26 icon.
  static const bannerCircle = 44.0;
  static const bannerIcon = 26.0;

  // Segmented control (§5): padding 4, gap 4, options min height 48.
  static const segmentPadding = 4.0;

  // Temperature tab (§8.2): site icon 22×48; chart 294×220.
  static const siteIconWidth = 22.0;
  static const siteIconHeight = 48.0;
  static const chartWidth = 294.0;
  static const chartHeight = 220.0;

  // Balance bar (Home).
  static const balanceBarHeight = 10.0;
  static const balanceTickWidth = 2.0;
  static const balanceTickHeight = 16.0;

  // Pills (DESIGN-SPEC §5): status tag padding 4 10 with an 18 px icon;
  // "ใหม่" chip padding 2 10.
  static const tagPaddingV = 4.0;
  static const tagPaddingH = 10.0;
  static const tagGap = 6.0;
  static const tagIcon = 18.0;
  static const chipPaddingV = 2.0;

  // Numbered steps.
  static const stepCircle = 32.0;
  static const stepTextGap = 12.0;

  // Details expander: header min height 56, padding 12 24; rows 12 0.
  static const expanderHeaderHeight = 56.0;
  static const expanderHeaderPaddingV = 12.0;
  static const detailRowPaddingV = 12.0;

  // Alerts list and empty state (DESIGN-SPEC §7.2).
  static const groupTitleGap = 16.0;
  static const emptyTop = 72.0;
  static const emptyCircle = 88.0;
  static const emptyIcon = 40.0;
  static const emptyTextMaxWidth = 300.0;

  // Alert detail gait note box icon.
  static const noteIcon = 24.0;

  // Bottom bar.
  static const bottomBarHeight = 80.0;
  static const bottomBarPadding = 8.0;
  static const tabPillWidth = 64.0;
  static const tabPillHeight = 32.0;
  static const badgeSize = 24.0;
  static const badgeRing = 2.0;
  static const badgeTop = -6.0;
  static const badgeRight = 2.0;
}
