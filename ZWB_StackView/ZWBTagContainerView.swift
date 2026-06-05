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
//    - 超出指定数量时自动切换为无限轮播跑马灯（参考 GMMarqueeView）
//    - 适配 UITableViewCell / UICollectionViewCell 复用场景

import UIKit
import Kingfisher
import SnapKit
import SwiftSVGAPlayer

// MARK: - 图片来源

enum ZWBImageSource {
    case local(UIImage)
    case remote(url: URL, placeholder: UIImage?)
    case localOrRemote(local: UIImage?, url: URL, placeholder: UIImage?)
}

// MARK: - 对齐

enum ZWBAlignment {
    case left, center, right
}

// MARK: - 图文混合方向

enum ZWBImageTextLayout {
    case imageLeft
    case imageRight
}

// MARK: - Item 数据模型

enum ZWBTagItem {
    case text(String)
    case image(source: ZWBImageSource, tapHandler: (() -> Void)?)
    /// SVGA 动画标签（使用 ZWB_SwiftSVGAPlayer 播放）
    case svga(url: URL, tapHandler: (() -> Void)?)
    case mixed(
        source: ZWBImageSource,
        text: String,
        layout: ZWBImageTextLayout,
        spacing: CGFloat,
        tapHandler: (() -> Void)?
    )
}

// MARK: - 配置

struct ZWBTagConfig {
    // ── 静态布局 ──────────────────────────────────────────────
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

    // ── 跑马灯 ────────────────────────────────────────────────
    /// 超过多少个 item 时触发自动轮播；0 = 永不触发（默认关闭）
    var marqueeItemCountThreshold: Int = 0
    /// 滚动速度，单位 pt/s，默认 50；正值向左滚动，负值向右滚动（阿语场景）
    var marqueeSpeed: CGFloat          = 50
    /// item 之间的间距（轮播模式下使用，与 horizontalSpacing 独立）
    var marqueeItemSpacing: CGFloat    = 20
    /// 滚动启动前的停顿时长（秒），页面加载出来后先静止再滚动，避免突兀；默认 1.5
    var marqueeStartDelay: TimeInterval = 1.5

    static let `default` = ZWBTagConfig()
}

// MARK: - ZWBTagContainerView

class ZWBTagContainerView: UIView {

    // MARK: 私有 — 通用

    private var items: [ZWBTagItem] = []
    private var config: ZWBTagConfig = .default

    private var needsRebuild: Bool = false
    private var cachedLayoutWidth: CGFloat = 0
    private var _intrinsicHeight: CGFloat = 0

    // MARK: 私有 — 静态布局

    private var staticItemViews: [UIView] = []

    // MARK: 私有 — 轮播模式（参考 GMMarqueeView）

    /// 轮播模式下所有复制的 view（6 组）
    private var marqueeAllViews: [UIView] = []
    /// 单组原始 item 视图（用于点击索引对应）
    private var marqueeOriginalViews: [UIView] = []
    /// 单组内容宽度（不含末尾间距）
    private var singleContentWidth: CGFloat = 0
    /// 单组完整宽度（含末尾间距，用于无缝重置）
    private var singleGroupWidth: CGFloat = 0
    /// 当前整体偏移（用于校准）
    private var marqueeOffsetX: CGFloat = 0
    /// CADisplayLink
    private var displayLink: CADisplayLink?
    /// 防重入
    private var isUpdatingMarquee: Bool = false
    private var isTickingMarquee: Bool = false
    private var isLayingOutMarquee: Bool = false
    private var hasAdjustedInitialPosition: Bool = false
    /// 是否正在等待延迟启动滚动（避免重复调度）
    private var isWaitingToStartMarquee: Bool = false

    // MARK: 初始化

    override init(frame: CGRect) { super.init(frame: frame); clipsToBounds = true }
    required init?(coder: NSCoder) { super.init(coder: coder); clipsToBounds = true }

    // MARK: 公开 API

    func update(items: [ZWBTagItem], config: ZWBTagConfig = .default) {
        self.config = config
        self.items  = items
        scheduleRebuild()
    }

    func setItems(_ items: [ZWBTagItem]) {
        self.items = items
        scheduleRebuild()
    }

    func setConfig(_ config: ZWBTagConfig) {
        self.config = config
        scheduleRebuild()
    }

    /// Cell prepareForReuse 时调用
    func reset() {
        stopMarquee()
        cancelAllDownloads(in: staticItemViews)
        cancelAllDownloads(in: marqueeAllViews)
        // 停止所有 SVGA 播放器，避免内存泄漏
        stopAllSVGA(in: staticItemViews)
        stopAllSVGA(in: marqueeAllViews)
        staticItemViews.forEach { $0.removeFromSuperview() }
        marqueeAllViews.forEach { $0.removeFromSuperview() }
        staticItemViews.removeAll()
        marqueeAllViews.removeAll()
        marqueeOriginalViews.removeAll()
        items = []
        needsRebuild = false
        isUpdatingMarquee = false
        isTickingMarquee = false
        isLayingOutMarquee = false
        hasAdjustedInitialPosition = false
        singleContentWidth = 0
        singleGroupWidth = 0
        marqueeOffsetX = 0
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

        if isMarqueeMode {
            layoutMarqueeItems()
        } else {
            layoutStaticItems()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopMarquee()
        } else if isMarqueeMode, !isUpdatingMarquee, !marqueeAllViews.isEmpty {
            startMarquee()
        }
    }

    // MARK: 判断是否轮播模式

    private var isMarqueeMode: Bool {
        let threshold = config.marqueeItemCountThreshold
        return threshold > 0 && items.count > threshold
    }

    // MARK: 调度

    private func scheduleRebuild() {
        needsRebuild = true
        cachedLayoutWidth = 0
        stopMarquee()
        setNeedsLayout()
    }

    // MARK: 重建视图

    private func rebuildViews() {
        needsRebuild = false
        isUpdatingMarquee = true

        // 清理旧视图
        stopMarquee()
        cancelAllDownloads(in: staticItemViews)
        cancelAllDownloads(in: marqueeAllViews)
        staticItemViews.forEach { $0.removeFromSuperview() }
        marqueeAllViews.forEach { $0.removeFromSuperview() }
        staticItemViews.removeAll()
        marqueeAllViews.removeAll()
        marqueeOriginalViews.removeAll()
        hasAdjustedInitialPosition = false
        singleContentWidth = 0
        singleGroupWidth = 0
        marqueeOffsetX = 0

        if isMarqueeMode {
            buildMarqueeViews()
        } else {
            buildStaticViews()
        }

        // 异步收尾，确保布局完成后再启动
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isUpdatingMarquee = false
            if self.isMarqueeMode, self.window != nil {
                self.startMarquee()
            }
        }
    }

    // MARK: ── 静态模式 ──────────────────────────────────────────

    private func buildStaticViews() {
        for item in items {
            let v = makeView(for: item)
            addSubview(v)
            staticItemViews.append(v)
        }
    }

    private func layoutStaticItems() {
        let maxW = bounds.width - config.contentInset.left - config.contentInset.right
        var rows: [[(view: UIView, size: CGSize)]] = []
        var currentRow: [(view: UIView, size: CGSize)] = []
        var currentRowW: CGFloat = 0

        for view in staticItemViews {
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

        let total = rows.isEmpty
            ? config.contentInset.top + config.contentInset.bottom
            : offsetY - config.verticalSpacing + config.contentInset.bottom

        updateIntrinsicHeight(total)
    }

    // MARK: ── 轮播模式（参考 GMMarqueeView）─────────────────────

    private func buildMarqueeViews() {
        // 先构建一组原始 views，计算单组宽度
        var originals: [UIView] = []
        for item in items {
            let v = makeView(for: item)
            originals.append(v)
        }
        marqueeOriginalViews = originals

        // 单组宽度计算（所有 item 宽度之和 + 间距）
        let space = config.marqueeItemSpacing
        let sizes = originals.map { naturalSize(of: $0) }
        let totalItemW = sizes.reduce(0) { $0 + $1.width }
        singleContentWidth = totalItemW + space * CGFloat(max(originals.count - 1, 0))
        singleGroupWidth   = singleContentWidth + space  // 末尾加一个间距，衔接下一组

        // 复制 6 组，参考 GMMarqueeView，保证快速滚动不露底
        for _ in 0..<6 {
            for (index, original) in originals.enumerated() {
                let copy = makeCopyView(of: original, originalIndex: index)
                addSubview(copy)
                marqueeAllViews.append(copy)
            }
        }
    }

    /// 轮播模式下初始布局（每次 layoutSubviews 且宽度变化时调用）
    private func layoutMarqueeItems() {
        guard !isLayingOutMarquee else { return }
        isLayingOutMarquee = true
        defer { isLayingOutMarquee = false }

        guard !marqueeAllViews.isEmpty else { return }

        let space    = config.marqueeItemSpacing
        let groupCnt = items.count
        guard groupCnt > 0 else { return }

        let sizes = marqueeOriginalViews.map { naturalSize(of: $0) }
        let rowH = sizes.map { $0.height }.max() ?? config.imageHeight
        let total = config.contentInset.top + rowH + config.contentInset.bottom
        updateIntrinsicHeight(total)

        var x: CGFloat = 0

        for (i, view) in marqueeAllViews.enumerated() {
            let localIndex = i % groupCnt
            let size = sizes[localIndex]
            let y = config.contentInset.top + (rowH - size.height) / 2
            view.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
            x += size.width + space
        }

        if !hasAdjustedInitialPosition {
            if config.marqueeSpeed >= 0 {
                // 向左滚动：初始内容直接从左边界开始铺满，立即滚动（不先推到屏幕外，避免开头一大段空白）
                marqueeOffsetX = 0
            } else {
                // 向右滚动（阿语）：初始第一组内容右对齐到容器右边界，立即滚动
                let offset = bounds.width - singleContentWidth
                marqueeAllViews.forEach { $0.frame.origin.x += offset }
                marqueeOffsetX = offset
            }
            hasAdjustedInitialPosition = true
        }
    }

    /// 复制一个 view 用于轮播，保留点击能力
    private func makeCopyView(of original: UIView, originalIndex: Int) -> UIView {
        // 直接用 makeView 重新创建同类型视图（保留完整功能），
        // 并绑定 tag 用于点击索引
        let copy = makeView(for: items[originalIndex])
        copy.tag = originalIndex
        return copy
    }

    // MARK: ── CADisplayLink ──────────────────────────────────────

    private func startMarquee() {
        guard !isUpdatingMarquee, window != nil else { return }
        // 已在等待延迟启动，避免重复调度
        guard !isWaitingToStartMarquee else { return }
        stopMarquee()
        // 先停顿 config.marqueeStartDelay 秒再开始滚动，避免页面加载出来立即滚动的突兀感
        isWaitingToStartMarquee = true
        DispatchQueue.main.asyncAfter(deadline: .now() + config.marqueeStartDelay) { [weak self] in
            guard let self = self else { return }
            self.isWaitingToStartMarquee = false
            // 延迟期间状态可能已变化（被停止/不在窗口上），需重新校验
            guard !self.isUpdatingMarquee, self.window != nil,
                  !self.marqueeAllViews.isEmpty, self.displayLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(self.tickMarquee))
            link.add(to: .main, forMode: .common)
            self.displayLink = link
        }
    }

    private func stopMarquee() {
        isWaitingToStartMarquee = false
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tickMarquee() {
        guard !isUpdatingMarquee,
              !isLayingOutMarquee,
              !isTickingMarquee,
              !marqueeAllViews.isEmpty,
              singleGroupWidth > 0 else { return }

        isTickingMarquee = true
        defer { isTickingMarquee = false }

        // 每帧位移（speed pt/s ÷ 60fps）
        let delta = config.marqueeSpeed / 60.0
        marqueeOffsetX -= delta

        for view in marqueeAllViews {
            view.frame.origin.x -= delta
        }

        checkForwardLoop()
    }

    /// 向左滚动时：最左侧视图完全移出左边界超过一个 singleGroupWidth → 整体右移一组
    /// 向右滚动时：最右侧视图完全移出右边界超过一个 singleGroupWidth → 整体左移一组
    private func checkForwardLoop() {
        guard !isUpdatingMarquee, !isLayingOutMarquee,
              !marqueeAllViews.isEmpty, singleGroupWidth > 0 else { return }

        if config.marqueeSpeed >= 0 {
            // 向左滚动：最左侧视图完全移出左边界
            guard let leftmost = marqueeAllViews.min(by: { $0.frame.minX < $1.frame.minX }) else { return }
            if leftmost.frame.maxX <= -singleGroupWidth {
                for view in marqueeAllViews {
                    view.frame.origin.x += singleGroupWidth
                }
                marqueeOffsetX -= singleGroupWidth
            }
        } else {
            // 向右滚动：最右侧视图完全移出右边界
            guard let rightmost = marqueeAllViews.max(by: { $0.frame.maxX < $1.frame.maxX }) else { return }
            if rightmost.frame.minX >= bounds.width + singleGroupWidth {
                for view in marqueeAllViews {
                    view.frame.origin.x -= singleGroupWidth
                }
                marqueeOffsetX += singleGroupWidth
            }
        }
    }

    // MARK: 工具 — 视图创建

    private func makeView(for item: ZWBTagItem) -> UIView {
        switch item {
        case .text(let str):
            return makeTextView(text: str)
        case .image(let source, let handler):
            return makeImageOnlyView(source: source, tapHandler: handler)
        case .svga(let url, let handler):
            return makeSVGAView(url: url, tapHandler: handler)
        case .mixed(let source, let text, let layout, let spacing, let handler):
            return makeMixedView(source: source, text: text, layout: layout, spacing: spacing, tapHandler: handler)
        }
    }

    private func makeTextView(text: String) -> UIView {
        let label = PaddedLabel(insets: config.textInset)
        label.text = text
        label.font = config.textFont
        label.textColor = config.textColor
        label.backgroundColor = config.textBackgroundColor
        label.layer.cornerRadius = config.itemCornerRadius
        label.layer.masksToBounds = true
        return label
    }

    /// 创建 SVGA 播放视图（正方形，宽高等于 imageHeight）
    private func makeSVGAView(url: URL, tapHandler: (() -> Void)?) -> UIView {
        let wrapper = TappableView()
        wrapper.tapHandler = tapHandler
        wrapper.layer.cornerRadius = config.itemCornerRadius
        wrapper.layer.masksToBounds = true

        let svgaView = SwiftSVGAPlayerView()
        svgaView.clearsAfterStop = true
        svgaView.contentMode = .scaleAspectFit
        svgaView.backgroundColor = .clear
        wrapper.addSubview(svgaView)
        svgaView.snp.makeConstraints { $0.edges.equalToSuperview() }

        // SVGA 标签固定正方形尺寸
        let size = config.imageHeight
        wrapper.frame = CGRect(x: 0, y: 0, width: size, height: size)

        // 播放 SVGA 动画（循环播放）
        svgaView.play(.url(url), loop: .forever)
        return wrapper
    }

    private func makeImageOnlyView(source: ZWBImageSource, tapHandler: (() -> Void)?) -> UIView {
        let wrapper = TappableView()
        wrapper.tapHandler = tapHandler
        wrapper.layer.cornerRadius = config.itemCornerRadius
        wrapper.layer.masksToBounds = true

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        wrapper.addSubview(imageView)
        imageView.snp.makeConstraints { $0.edges.equalToSuperview() }

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

        let ph = placeholder(for: source)
        applyMixedConstraints(wrapper: wrapper, imageView: imageView, label: label,
                              imgWidth: calcImageWidth(for: ph), layout: layout, spacing: spacing)

        loadImage(source: source, into: imageView) { [weak self, weak wrapper, weak imageView, weak label] img in
            guard let self, let wrapper, let imageView, let label else { return }
            self.applyMixedConstraints(wrapper: wrapper, imageView: imageView, label: label,
                                       imgWidth: self.calcImageWidth(for: img), layout: layout, spacing: spacing)
            self.cachedLayoutWidth = 0
            self.setNeedsLayout()
        }
        return wrapper
    }

    private func applyMixedConstraints(
        wrapper: UIView, imageView: UIImageView, label: UILabel,
        imgWidth: CGFloat, layout: ZWBImageTextLayout, spacing: CGFloat
    ) {
        let il = config.mixedInset.left,  ir = config.mixedInset.right
        let it = config.mixedInset.top,   ib = config.mixedInset.bottom
        let ih = config.imageHeight
        let labelSize = label.sizeThatFits(CGSize(width: .greatestFiniteMagnitude, height: ih))

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
            case .imageLeft:  make.leading.equalTo(imageView.snp.trailing).offset(spacing)
            case .imageRight: make.leading.equalToSuperview().offset(il)
            }
        }
        wrapper.frame = CGRect(
            x: wrapper.frame.origin.x, y: wrapper.frame.origin.y,
            width: il + imgWidth + spacing + labelSize.width + ir,
            height: it + max(ih, labelSize.height) + ib
        )
    }

    // MARK: 工具 — 图片加载

    private func loadImage(source: ZWBImageSource, into imageView: UIImageView, completion: ((UIImage?) -> Void)? = nil) {
        switch source {
        case .local(let img):
            imageView.image = img
            completion?(img)
        case .remote(let url, let ph):
            imageView.image = ph
            imageView.kf.setImage(with: url, placeholder: ph,
                                  options: [.transition(.fade(0.2)), .cacheOriginalImage]) {
                completion?(try? $0.get().image)
            }
        case .localOrRemote(let local, let url, let ph):
            if let local {
                imageView.image = local; completion?(local)
            } else {
                imageView.image = ph
                imageView.kf.setImage(with: url, placeholder: ph,
                                      options: [.transition(.fade(0.2)), .cacheOriginalImage]) {
                    completion?(try? $0.get().image)
                }
            }
        }
    }

    // MARK: 工具 — 通用

    private func cancelAllDownloads(in views: [UIView]) {
        views.forEach { wrapper in
            wrapper.subviews.compactMap { $0 as? UIImageView }.forEach { $0.kf.cancelDownloadTask() }
        }
    }

    /// 停止所有 SVGA 播放器动画，释放资源
    private func stopAllSVGA(in views: [UIView]) {
        views.forEach { wrapper in
            wrapper.subviews.compactMap { $0 as? SwiftSVGAPlayerView }.forEach {
                $0.stop()
                $0.clear()
            }
        }
    }

    private func placeholder(for source: ZWBImageSource) -> UIImage? {
        switch source {
        case .local(let img):                  return img
        case .remote(_, let ph):               return ph
        case .localOrRemote(let l, _, let ph): return l ?? ph
        }
    }

    private func calcImageWidth(for image: UIImage?) -> CGFloat {
        guard let img = image, img.size.height > 0 else { return config.imageHeight }
        return (img.size.width / img.size.height) * config.imageHeight
    }

    private func naturalSize(of view: UIView) -> CGSize {
        if let label = view as? PaddedLabel { return label.intrinsicContentSize }
        return view.bounds.size
    }

    private func updateIntrinsicHeight(_ total: CGFloat) {
        if _intrinsicHeight != total {
            _intrinsicHeight = total
            invalidateIntrinsicContentSize()
            superview?.setNeedsLayout()
        }
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
