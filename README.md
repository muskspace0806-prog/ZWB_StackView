# ZWBTagContainerView

一个轻量、灵活的 iOS 流式标签容器，支持**纯文字**、**纯图片**、**图文混合**三种 item 类型，自动换行，图片统一高度宽度自适应，三种水平对齐方式，适配 UITableViewCell / UICollectionViewCell 复用场景。

---

## 效果预览

| 左对齐 | 居中对齐 | 右对齐 |
|--------|----------|--------|
| 文字/图片/图文混合 | 文字/图片/图文混合 | 文字/图片/图文混合 |

---

## 依赖

```ruby
pod 'Kingfisher', '~> 7.0'              # 网络图片加载
pod 'SnapKit',    '~> 5.0'              # 内部子视图布局
pod 'ZWB_SwiftSVGAPlayer', '~> 1.0.3'   # SVGA 动画播放（svga item 类型）
```

执行 `pod install` 后使用 `.xcworkspace` 打开项目。

---

## 核心类型

### ZWBImageSource — 图片来源

```swift
// 纯本地
.local(UIImage)

// 纯网络，placeholder 可选
.remote(url: URL, placeholder: UIImage?)

// 本地优先，本地为 nil 时自动走网络（适合缓存场景）
.localOrRemote(local: UIImage?, url: URL, placeholder: UIImage?)
```

### ZWBTagItem — item 类型

```swift
// 纯文字
.text("Swift")

// 纯图片，可点击
.image(source: ZWBImageSource, tapHandler: (() -> Void)?)

// SVGA 动画，可点击（需 ZWB_SwiftSVGAPlayer）
.svga(url: URL, tapHandler: (() -> Void)?)

// 图文混合，整体可点击
.mixed(
    source: ZWBImageSource,
    text: String,
    layout: ZWBImageTextLayout,   // .imageLeft 或 .imageRight
    spacing: CGFloat,
    tapHandler: (() -> Void)?
)
```

### ZWBAlignment — 对齐方式

```swift
.left     // 左对齐
.center   // 居中对齐
.right    // 右对齐
```

### ZWBTagConfig — 样式配置

```swift
var horizontalSpacing: CGFloat      // item 水平间距，默认 8
var verticalSpacing: CGFloat        // 行间距，默认 8
var contentInset: UIEdgeInsets      // 容器内边距，默认四周 8
var imageHeight: CGFloat            // 图片统一高度，宽度按比例自适应，默认 40
var textFont: UIFont                // 文字字体
var textColor: UIColor              // 文字颜色
var textBackgroundColor: UIColor    // 纯文字 item 背景色
var mixedBackgroundColor: UIColor   // 图文混合 item 背景色
var textInset: UIEdgeInsets         // 文字 item 内边距
var mixedInset: UIEdgeInsets        // 图文混合 item 内边距
var itemCornerRadius: CGFloat       // item 圆角，默认 6
var alignment: ZWBAlignment         // 对齐方式，默认 .left

// ── 跑马灯（item 超出阈值时自动横向滚动）──
var marqueeItemCountThreshold: Int  // 超过多少个 item 触发自动轮播，0=关闭（默认）
var marqueeSpeed: CGFloat           // 滚动速度 pt/s，默认 50；正值向左，负值向右（阿语）
var marqueeItemSpacing: CGFloat     // 轮播模式下 item 间距，默认 20
var marqueeStartDelay: TimeInterval // 滚动启动前停顿时长(秒)，默认 1.5，避免加载即滚动的突兀
```

---

## 使用方式

### 基础用法

```swift
let container = ZWBTagContainerView()
view.addSubview(container)

// SnapKit 约束
container.snp.makeConstraints { make in
    make.top.equalTo(someView.snp.bottom).offset(12)
    make.leading.trailing.equalToSuperview().inset(16)
    // 高度由内容自动撑开，不需要写死
}

// 设置数据
container.setItems([
    .text("Swift"),
    .text("UIKit"),
    .image(source: .local(UIImage(named: "icon")!), tapHandler: nil),
])
```

### 配置样式

```swift
var config = ZWBTagConfig()
config.alignment         = .center
config.imageHeight       = 36
config.horizontalSpacing = 10
config.verticalSpacing   = 10
config.itemCornerRadius  = 8
config.contentInset      = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)

container.update(items: items, config: config)
```

### 纯文字

```swift
let items: [ZWBTagItem] = ["iOS", "Swift", "UIKit", "SwiftUI"].map { .text($0) }
container.setItems(items)
```

### 纯图片

```swift
// 本地
.image(source: .local(UIImage(named: "star")!), tapHandler: {
    print("点击了本地图片")
})

// 网络
let url = URL(string: "https://example.com/image.png")!
let ph  = UIImage(named: "placeholder")
.image(source: .remote(url: url, placeholder: ph), tapHandler: {
    print("点击了网络图片")
})

// 本地优先，本地无图走网络
.image(source: .localOrRemote(local: cachedImage, url: url, placeholder: ph), tapHandler: nil)
```

### 图文混合

```swift
let icon = UIImage(systemName: "bell.fill")
    .withTintColor(.systemOrange, renderingMode: .alwaysOriginal)

// 左图右字
.mixed(source: .local(icon), text: "通知", layout: .imageLeft, spacing: 5, tapHandler: {
    print("点击了图文混合 item")
})

// 右图左字 + 网络图
let url = URL(string: "https://example.com/badge.png")!
.mixed(source: .remote(url: url, placeholder: nil), text: "热门", layout: .imageRight, spacing: 6, tapHandler: nil)
```

### 混合排列（文字 + 图片 + 图文混合自由组合）

```swift
let items: [ZWBTagItem] = [
    .text("公告"),
    .image(source: .local(UIImage(named: "icon")!), tapHandler: nil),
    .text("最新"),
    .mixed(source: .local(UIImage(named: "badge")!), text: "精选", layout: .imageLeft, spacing: 4, tapHandler: nil),
]
container.setItems(items)
```

---

### SVGA 动画

`svga` item 使用 [ZWB_SwiftSVGAPlayer](https://github.com/muskspace0806-prog/ZWB_SwiftSVGAPlayer) 播放在线/本地 SVGA，正方形显示（宽高等于 `config.imageHeight`），循环播放，复用时自动停止释放。

```swift
let url = URL(string: "https://example.com/medal.svga")!
container.setItems([
    .svga(url: url, tapHandler: { print("点击了 SVGA 勋章") }),
])
```

---

## 自动滚动（跑马灯）

当 item 数量超过 `marqueeItemCountThreshold` 时，容器自动切换为无限横向轮播。内容从起点直接铺满（向左滚动从左边界、阿语向右滚动从右边界），启动前停顿 `marqueeStartDelay` 秒再滚动，避免页面加载即滚动的突兀感。

```swift
var config = ZWBTagConfig()
config.imageHeight              = 32
config.marqueeItemCountThreshold = 5      // 超过 5 个开始滚动
config.marqueeSpeed             = 50      // 正值向左滚；阿语场景用 -50 向右滚
config.marqueeItemSpacing       = 9
config.marqueeStartDelay        = 1.5     // 停顿 1.5 秒再开始滚动

container.update(items: items, config: config)
```

| 配置项 | 说明 |
|--------|------|
| `marqueeItemCountThreshold` | 超过多少个 item 触发滚动，0 关闭（默认） |
| `marqueeSpeed` | 滚动速度 pt/s，正值向左 / 负值向右（阿语） |
| `marqueeItemSpacing` | 轮播模式下 item 间距 |
| `marqueeStartDelay` | 启动前停顿时长（秒），默认 1.5 |

---

## 适配 Cell 复用

在 `prepareForReuse` 里调用 `reset()`，会自动取消正在进行的网络图片请求，防止图片串行。

```swift
class MyCell: UITableViewCell {

    private let tagContainer = ZWBTagContainerView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        contentView.addSubview(tagContainer)
        tagContainer.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalToSuperview().offset(-12)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        tagContainer.reset()   // 清空旧数据，取消网络请求
    }

    func configure(with items: [ZWBTagItem], config: ZWBTagConfig) {
        tagContainer.update(items: items, config: config)
    }
}
```

---

## 布局说明

| 层级 | 布局方式 | 原因 |
|------|----------|------|
| 页面结构（ScrollView、Container 等） | SnapKit | 静态层级，约束清晰 |
| item 内部子视图（imageView / label） | SnapKit | 相对位置固定，SnapKit 直观 |
| item 在容器内的流式折行排列 | frame 手动计算 | 子视图数量动态、需要折行，AutoLayout 无法直接表达 |

---

## 文件结构

```
ZWB_StackView/
├── ZWBTagContainerView.swift   # 核心工具类
├── ViewController.swift        # Demo
├── Podfile
└── README.md
```

---

## 环境要求

- iOS 13.0+
- Swift 5.0+
- Xcode 14+
