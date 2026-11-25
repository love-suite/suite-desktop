import AppKit
import SuiteFilesCore
import SuiteFilesUI

/// The contents of a desktop stack, shown in a popover when the stack is opened.
final class StackViewController: NSViewController, NSCollectionViewDataSource {
    private let items: [FileItem]
    private let onOpen: (FileItem) -> Void
    private let collection = IconCollectionView()

    init(items: [FileItem], onOpen: @escaping (FileItem) -> Void) {
        self.items = items
        self.onOpen = onOpen
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        let cell = IconItemView.size
        let spacing: CGFloat = 4
        let inset: CGFloat = 10
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = cell
        layout.minimumInteritemSpacing = spacing
        layout.minimumLineSpacing = spacing
        layout.sectionInset = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)

        collection.collectionViewLayout = layout
        collection.dataSource = self
        collection.isSelectable = true
        collection.backgroundColors = [.clear]
        collection.register(IconItemView.self, forItemWithIdentifier: IconItemView.reuseID)
        collection.onDoubleClick = { [weak self] indexPath in
            guard let self, indexPath.item < self.items.count else { return }
            self.onOpen(self.items[indexPath.item])
        }

        // Up to 5 columns; past 4 rows the popover scrolls.
        let columns = min(max(items.count, 1), 5)
        let rows = (items.count + columns - 1) / columns
        func extent(_ count: Int, _ length: CGFloat) -> CGFloat {
            CGFloat(count) * length + CGFloat(max(count - 1, 0)) * spacing + 2 * inset
        }
        let size = NSSize(width: extent(columns, cell.width), height: extent(min(rows, 4), cell.height))
        collection.frame = NSRect(x: 0, y: 0, width: size.width, height: extent(rows, cell.height))

        let scroll = NSScrollView(frame: NSRect(origin: .zero, size: size))
        scroll.documentView = collection
        scroll.hasVerticalScroller = rows > 4
        scroll.drawsBackground = false
        view = scroll
        preferredContentSize = size
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: NSCollectionView,
                        itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let cell = collectionView.makeItem(withIdentifier: IconItemView.reuseID, for: indexPath)
        (cell as? IconItemView)?.configure(with: items[indexPath.item])
        return cell
    }
}
