<h3 align="left">
  <a href="./README.md">中文</a> | <strong>English</strong>
</h3>

# ZWBTagContainerView

A lightweight and flexible iOS flow-style tag container. It supports text items, image items, mixed image-text items, SVGA items, automatic wrapping, configurable alignment, and cell reuse scenarios.

## Dependencies

```ruby
pod 'Kingfisher', '~> 7.0'
pod 'SnapKit',    '~> 5.0'
pod 'ZWB_SwiftSVGAPlayer', '~> 1.0.3'
```

Run `pod install` and open the `.xcworkspace` file.

## Core Types

```swift
.local(UIImage)
.remote(url: URL, placeholder: UIImage?)
.localOrRemote(local: UIImage?, url: URL, placeholder: UIImage?)

.text("Swift")
.image(source: ZWBImageSource, tapHandler: (() -> Void)?)
.svga(url: URL, tapHandler: (() -> Void)?)
.mixed(source: ZWBImageSource, text: String, layout: ZWBImageTextLayout, spacing: CGFloat, tapHandler: (() -> Void)?)
```

## Basic Usage

```swift
let container = ZWBTagContainerView()
view.addSubview(container)

container.snp.makeConstraints { make in
    make.top.equalTo(someView.snp.bottom).offset(12)
    make.leading.trailing.equalToSuperview().inset(16)
}

container.setItems([
    .text("Swift"),
    .text("UIKit"),
    .image(source: .local(UIImage(named: "icon")!), tapHandler: nil),
])
```

## Configuration

```swift
var config = ZWBTagConfig()
config.alignment = .center
config.imageHeight = 36
config.horizontalSpacing = 10
config.verticalSpacing = 10
config.itemCornerRadius = 8
config.contentInset = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)

container.update(items: items, config: config)
```

## Marquee Mode

When item count exceeds `marqueeItemCountThreshold`, the container switches to infinite horizontal scrolling.

```swift
var config = ZWBTagConfig()
config.marqueeItemCountThreshold = 5
config.marqueeSpeed = 50
config.marqueeItemSpacing = 9
config.marqueeStartDelay = 1.5

container.update(items: items, config: config)
```

## Cell Reuse

Call `reset()` inside `prepareForReuse()` to cancel image requests and clear state.

```swift
override func prepareForReuse() {
    super.prepareForReuse()
    tagContainer.reset()
}
```

## Highlights

- Text, image, mixed image-text, and SVGA item types.
- Left, center, and right alignment.
- Unified image height with proportional width.
- Automatic wrapping and automatic height.
- Marquee support for overflowing item lists.
- Designed for table/collection cell reuse.
