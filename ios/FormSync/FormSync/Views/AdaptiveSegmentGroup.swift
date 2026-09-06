import SwiftUI

struct AdaptiveSegmentGroup<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let gridColumns: Int?
    let content: (Item) -> Content

    init(
        items: [Item],
        gridColumns: Int? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.items = items
        self.gridColumns = gridColumns
        self.content = content
    }

    var body: some View {
        Group {
            if let gridColumns, gridColumns > 1 {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: AppTheme.spacingXS),
                        count: gridColumns
                    ),
                    spacing: AppTheme.spacingXS
                ) {
                    ForEach(items) { item in
                        content(item)
                    }
                }
            } else {
                HStack(spacing: AppTheme.spacingXS) {
                    ForEach(items) { item in
                        content(item)
                    }
                }
            }
        }
        .padding(AppTheme.spacingXS)
        .background(AppTheme.segmentBackground, in: RoundedRectangle(cornerRadius: AppTheme.radiusM, style: .continuous))
    }
}
