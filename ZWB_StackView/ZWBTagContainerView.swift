//
//  ZWBTagContainerView.swift
//  ZWB_StackView
//
//  Created by hule on 2026/6/2.
//
//  流式标签容器，支持：
//    - 纯文字 / 纯图片（可点击）/ 图文混合（可点击）
//    - 图片来源：本地 / 网络（Kingfisher）/ 本地优先网络兜底
//    - 三种对齐：left / center / right
//    - 数据不固定，自动换行
//    - 适配 Cell 复用场景
//
//  布局说明：
//    - 容器内子 item 的流式折行排列使用 frame 手动计算
//      （子 view 数量动态、需要折行，AutoLayout 无法直接胜任）
//    - item 内部子视图（imageView / label）使用 SnapKit 约束

import UIKit
import Kingfisher
import SnapKit

// MARK: - 图片来源

enum ZWBImageSource {
    /// 纯本地图片
    case local(UIImage)
    /// 纯网络图片，placeholder 可选
    case remote(url: URL, placeholder: UIImage?)
    /// 本地优先：本地为 nil 时走网络
    case localOrRemote(local: UIImage?, url: URL, placeholder: UIImage?)
}

// MARK: - 对齐

enum ZWBAlignment {
    case left, center, right
}

// MARK: - 图文混合方向

enum ZWBImageTextLayout {
    case imageLeft    // 图左文右
    case imageRight   // 图右文左
}

// MARK: - Item 数据模型

enum ZWBTagItem {
    /// 纯文字
    case text(String)
    /// 纯图片，高度固定宽度自适应，可点击
    case image(source: ZWBImageSource, tapHandler: (() -> Void)?)
    /// 图文混合，整体可点击
    case mixed(
        source: ZWBImageSource,
        text: String,
        layout: ZWBImageTextLayout,
        spacing: CGFloat,
        tapHandler: (() -> Void)?
    )
}

// MARK: - 配置（批量设置避免多次 reload）

struct ZWBTagConfig {
    var horizontalSpacing: CGFloat    = 8
    var verticalSpacing: CGFloat      = 8
    var contentInset: UIEdgeInsets    = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
    var imageHeight: CGFloat          = 40
    var textFont: UIFont              = .systemFont(ofSize: 14)
    var textColor: UIColor            = .darkText
    var textBackgroundColor: UIColor  = UIColor.systemGray5
    var mixedBackgroundColor: UIColor = UIColor.systemGray5
    var textInset: UIEdgeInsets       = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
    var mixedInset: UIEdgeInsets      = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
    var itemCornerRadius: CGFloat     = 6
    var alignment: ZWBAlignment       = .left

    static let `default` = ZWBTagConfig()
}

// MARK: - ZWBTagContainerView

class ZWBTagContainerView: UIView {

    // MARK: 私有属性

    private var items: [ZWBTagItem] = []
    private var itemViews: [UIView] = []
    private var config: ZWBTagConfig = .default

    private var needsRebuild: Bool = false
    private var cachedLayoutWidth: CGFloat = 0
    private var _intrinsicHeight: CGFloat = 0

    // MARK: 初始化

    override init(frame: CGRect) { super.init(frame: frame) }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    // MARK: 公开 API

    /// 批量更新配置 + 数据，只触发一次 reload（推荐 cell 里使用）
    func update(items: [ZWBTagItem], config: ZWBTagConfig = .default) {
        self.config = config
        self.items  = items
        scheduleRebuild()
    }

    /// 仅更新数据
    func setItems(_ items: [ZWBTagItem]) {
        self.items = items
        scheduleRebuild()
    }

    /// 仅更新配置
    func setConfig(_ config: ZWBTagConfig) {
        self.config = config
        scheduleRebuild()
    }

    /// Cell prepareForReuse 时调用，取消网络请求并清空视图
    func reset() {
        cancelAllDownloads()
        items = []
        itemViews.forEach { $0.removeFromSuperview() }
        itemViews = []
        needsRebuild = false
        cachedLayoutWidth = 0
        _intrinsicHeight = 0
        invalidateIntrinsicContentSize()
    }

    // MARK: Layout

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: _intrinsicHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if needsRebuild { rebuildViews() }
        guard bounds.width > 0, bounds.width != cachedLayoutWidth else { return }
        cachedLayoutWidth = bounds.width
        layoutItems()
    }

    // MARK: 调度

    private func scheduleRebuild() {
        needsRebuild = true
        cachedLayoutWidth = 0
        setNeedsLayout()
    }

    // MARK: 视图重建

    private func rebuildViews() {
        needsRebuild = false
        cancelAllDownloads()
        itemViews.forEach { $0.removeFromSuperview() }
        itemViews = []
        for item in items {
            let v = makeView(for: item)
            addSubview(v)
            itemViews.append(v)
        }
    }

    private func cancelAllDownloads() {
        itemViews.forEach { wrapper in
            wrapper.subviews.compactMap { $0 as? UIImageView }.forEach {
                $0.kf.cancelDownloadTask()
            }
        }
    }

    // MARK: 视图工厂

    private func makeView(for item: ZWBTagItem) -> UIView {
        switch item {
        case .text(let str):
            return makeTextView(text: str)
        case .image(let source, let handler):
            return makeImageOnlyView(source: source, tapHandler: handler)
        case .mixed(let source, let text, let layout, let spacing, let handler):
            return makeMixedView(source: source, text: text, layout: layout, spacing: spacing, tapHandler: handler)
        }
    }

    // MARK: 纯文字 item
    // 内部用 SnapKit 约束 label 内容，外层 frame 由流式算法决定

    private func makeTextView(text: String) -> UIView {
        let label = PaddedLabel(insets: config.textInset)
        label.text = text
        label.font = config.textFont
        label.textColor = config.textColor
        label.backgroundColor = config.textBackgroundColor
        label.layer.cornerRadius = config.itemCornerRadius
        label.layer.masksToBounds = true
        // PaddedLabel 通过 intrinsicContentSize 给出尺寸，流式算法读取后设置 frame
        return label
    }

    // MARK: 纯图片 item
    // wrapper.frame 由流式算法设置；imageView 用 SnapKit 填满 wrapper

    private func makeImageOnlyView(source: ZWBImageSource, tapHandler: (() -> Void)?) -> UIView {
        let wrapper = TappableView()
        wrapper.tapHandler = tapHandler
        wrapper.layer.cornerRadius = config.itemCornerRadius
        wrapper.layer.masksToBounds = true

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        wrapper.addSubview(imageView)

        // SnapKit：imageView 填满 wrapper
        imageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        // 用 placeholder 先定 wrapper 尺寸
        let ph = placeholder(for: source)
        let initW = calcImageWidth(for: ph)
        wrapper.frame = CGRect(x: 0, y: 0, width: initW, height: config.imageHeight)

        loadImage(source: source, into: imageView) { [weak self, weak wrapper] img in
            guard let self, let wrapper else { return }
            let newW = self.calcImageWidth(for: img)
            wrapper.frame = CGRect(x: wrapper.frame.origin.x,
                                   y: wrapper.frame.origin.y,
                                   width: newW,
                                   height: self.config.imageHeight)
            self.cachedLayoutWidth = 0
            self.setNeedsLayout()
        }

        return wrapper
    }

    // MARK: 图文混合 item
    // wrapper.frame 由流式算法设置；内部 imageView / label 用 SnapKit 约束

    private func makeMixedView(
        source: ZWBImageSource,
        text: String,
        layout: ZWBImageTextLayout,
        spacing: CGFloat,
        tapHandler: (() -> Void)?
    ) -> UIView {

        let wrapper = TappableView()
        wrapper.tapHandler = tapHandler
        wrapper.backgroundColor = config.mixedBackgroundColor
        wrapper.layer.cornerRadius = config.itemCornerRadius
        wrapper.layer.masksToBounds = true

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.layer.cornerRadius = 2
        imageView.layer.masksToBounds = true

        let label = UILabel()
        label.text = text
        label.font = config.textFont
        label.textColor = config.textColor
        label.numberOfLines = 1

        wrapper.addSubview(imageView)
        wrapper.addSubview(label)

        // 用 placeholder 先布局
        let ph = placeholder(for: source)
        let initImgW = calcImageWidth(for: ph)
        applyMixedConstraints(
            wrapper: wrapper, imageView: imageView, label: label,
            imgWidth: initImgW, layout: layout, spacing: spacing
        )

        loadImage(source: source, into: imageView) { [weak self, weak wrapper, weak imageView, weak label] img in
            guard let self, let wrapper, let imageView, let label else { return }
            let newImgW = self.calcImageWidth(for: img)
            self.applyMixedConstraints(
                wrapper: wrapper, imageView: imageView, label: label,
                imgWidth: newImgW, layout: layout, spacing: spacing
            )
            self.cachedLayoutWidth = 0
            self.setNeedsLayout()
        }

        return wrapper
    }

    /// 用 SnapKit 设置混合 item 内部约束，图片宽度确定后可重复调用更新
    private func applyMixedConstraints(
        wrapper: UIView,
        imageView: UIImageView,
        label: UILabel,
        imgWidth: CGFloat,
        layout: ZWBImageTextLayout,
        spacing: CGFloat
    ) {
        let il = config.mixedInset.left
        let ir = config.mixedInset.right
        let it = config.mixedInset.top
        let ib = config.mixedInset.bottom
        let ih = config.imageHeight
        let labelSize = label.sizeThatFits(CGSize(width: .greatestFiniteMagnitude, height: ih))
        let totalW = il + imgWidth + spacing + labelSize.width + ir
        let totalH = it + max(ih, labelSize.height) + ib

        // 先移除旧约束再重设
        imageView.snp.remakeConstraints { make in
            make.width.equalTo(imgWidth)
            make.height.equalTo(ih)
            make.centerY.equalToSuperview()
            switch layout {
            case .imageLeft:  make.leading.equalToSuperview().offset(il)
            case .imageRight: make.trailing.equalToSuperview().offset(-ir)
            }
        }

        label.snp.remakeConstraints { make in
            make.centerY.equalToSuperview()
            make.width.equalTo(labelSize.width)
            switch layout {
            case .imageLeft:
                make.leading.equalTo(imageView.snp.trailing).offset(spacing)
            case .imageRight:
                make.leading.equalToSuperview().offset(il)
            }
        }

        // wrapper 的 frame 由流式算法控制，这里只更新尺寸部分
        wrapper.frame = CGRect(
            x: wrapper.frame.origin.x,
            y: wrapper.frame.origin.y,
            width: totalW,
            height: totalH
        )
    }

    // MARK: 流式排列（frame 计算）

    private func layoutItems() {
        let maxW = bounds.width - config.contentInset.left - config.contentInset.right

        // 第一步：按行分组
        var rows: [[(view: UIView, size: CGSize)]] = []
        var currentRow: [(view: UIView, size: CGSize)] = []
        var currentRowW: CGFloat = 0

        for view in itemViews {
            let size = naturalSize(of: view)
            if currentRow.isEmpty {
                currentRow.append((view, size))
                currentRowW = size.width
            } else {
                let needed = currentRowW + config.horizontalSpacing + size.width
                if needed <= maxW {
                    currentRow.append((view, size))
                    currentRowW = needed
                } else {
                    rows.append(currentRow)
                    currentRow = [(view, size)]
                    currentRowW = size.width
                }
            }
        }
        if !currentRow.isEmpty { rows.append(currentRow) }

        // 第二步：逐行计算 frame
        var offsetY = config.contentInset.top
        for row in rows {
            let rowW = row.reduce(0) { $0 + $1.size.width }
                     + CGFloat(max(row.count - 1, 0)) * config.horizontalSpacing
            let rowH = row.map { $0.size.height }.max() ?? 0

            let startX: CGFloat
            switch config.alignment {
            case .left:   startX = config.contentInset.left
            case .right:  startX = config.contentInset.left + maxW - rowW
            case .center: startX = config.contentInset.left + (maxW - rowW) / 2
            }

            var offsetX = startX
            for (view, size) in row {
                view.frame = CGRect(
                    x: offsetX,
                    y: offsetY + (rowH - size.height) / 2,
                    width: size.width,
                    height: size.height
                )
                offsetX += size.width + config.horizontalSpacing
            }
            offsetY += rowH + config.verticalSpacing
        }

        // 更新容器高度
        let total = rows.isEmpty
            ? config.contentInset.top + config.contentInset.bottom
            : offsetY - config.verticalSpacing + config.contentInset.bottom

        if _intrinsicHeight != total {
            _intrinsicHeight = total
            invalidateIntrinsicContentSize()
            superview?.setNeedsLayout()
        }
    }

    // MARK: 图片加载（Kingfisher 统一入口）

    private func loadImage(
        source: ZWBImageSource,
        into imageView: UIImageView,
        completion: ((UIImage?) -> Void)? = nil
    ) {
        switch source {
        case .local(let img):
            imageView.image = img
            completion?(img)

        case .remote(let url, let ph):
            imageView.image = ph
            imageView.kf.setImage(
                with: url,
                placeholder: ph,
                options: [.transition(.fade(0.2)), .cacheOriginalImage]
            ) { result in
                completion?(try? result.get().image)
            }

        case .localOrRemote(let local, let url, let ph):
            if let local {
                imageView.image = local
                completion?(local)
            } else {
                imageView.image = ph
                imageView.kf.setImage(
                    with: url,
                    placeholder: ph,
                    options: [.transition(.fade(0.2)), .cacheOriginalImage]
                ) { result in
                    completion?(try? result.get().image)
                }
            }
        }
    }

    // MARK: 工具

    private func placeholder(for source: ZWBImageSource) -> UIImage? {
        switch source {
        case .local(let img):                     return img
        case .remote(_, let ph):                  return ph
        case .localOrRemote(let l, _, let ph):    return l ?? ph
        }
    }

    private func calcImageWidth(for image: UIImage?) -> CGFloat {
        guard let img = image, img.size.height > 0 else { return config.imageHeight }
        return (img.size.width / img.size.height) * config.imageHeight
    }

    private func naturalSize(of view: UIView) -> CGSize {
        if let label = view as? PaddedLabel { return label.intrinsicContentSize }
        return view.bounds.size   // TappableView 的 frame 已在创建时确定
    }
}

// MARK: - PaddedLabel

private class PaddedLabel: UILabel {
    let insets: UIEdgeInsets
    init(insets: UIEdgeInsets) { self.insets = insets; super.init(frame: .zero) }
    required init?(coder: NSCoder) { self.insets = .zero; super.init(coder: coder) }
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }
    override var intrinsicContentSize: CGSize {
        let b = super.intrinsicContentSize
        return CGSize(width: b.width + insets.left + insets.right,
                      height: b.height + insets.top + insets.bottom)
    }
}

// MARK: - TappableView

private class TappableView: UIView {
    var tapHandler: (() -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(onTap)))
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    @objc private func onTap() { tapHandler?() }
}
