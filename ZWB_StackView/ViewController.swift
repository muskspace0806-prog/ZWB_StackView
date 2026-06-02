//
//  ViewController.swift
//  ZWB_StackView
//
//  Created by hule on 2026/6/2.
//

import UIKit
import SnapKit

class ViewController: UIViewController {

    // MARK: - UI

    private let scrollView  = UIScrollView()
    private let contentView = UIView()

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "ZWBTagContainerView Demo"
        setupScrollView()
        buildDemo()
    }

    // MARK: - ScrollView（SnapKit）

    private func setupScrollView() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        scrollView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalToSuperview()   // 固定宽度，高度由内容撑开
        }
    }

    // MARK: - 构建 Demo

    private func buildDemo() {
        var last: ConstraintRelatableTarget = contentView.snp.top

        last = addSection("① 纯文字 · 左对齐",              items: textItems(),                     alignment: .left,   below: last)
        last = addSection("② 纯文字 · 居中",                items: textItems(),                     alignment: .center, below: last)
        last = addSection("③ 纯文字 · 右对齐",              items: textItems(),                     alignment: .right,  below: last)
        last = addSection("④ 本地图片 · 左对齐",             items: localImageItems(),               alignment: .left,   below: last)
        last = addSection("⑤ 网络图片 · 居中",              items: remoteImageItems(),               alignment: .center, below: last)
        last = addSection("⑥ 本地/网络混合图片 · 右对齐",    items: mixedSourceItems(),              alignment: .right,  below: last)
        last = addSection("⑦ 图文混合（左图右字）· 左对齐",  items: mixedItems(layout: .imageLeft),  alignment: .left,   below: last)
        last = addSection("⑧ 图文混合（右图左字）· 居中",    items: mixedItems(layout: .imageRight), alignment: .center, below: last)
        last = addSection("⑨ 全类型混排 · 右对齐",          items: allItems(),                      alignment: .right,  below: last)

        // 最后一个 section 底部到 contentView 底部
        contentView.snp.makeConstraints { make in
            make.bottom.equalTo(last).offset(24)
        }
    }

    // MARK: - 添加分组（SnapKit）

    @discardableResult
    private func addSection(
        _ title: String,
        items: [ZWBTagItem],
        alignment: ZWBAlignment,
        below anchor: ConstraintRelatableTarget
    ) -> ConstraintRelatableTarget {

        // 分组标题
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .secondaryLabel
        contentView.addSubview(titleLabel)

        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(anchor).offset(20)
            make.leading.equalToSuperview().offset(16)
            make.trailing.equalToSuperview().offset(-16)
        }

        // 分隔线
        let sep = UIView()
        sep.backgroundColor = .separator
        contentView.addSubview(sep)

        sep.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(6)
            make.leading.equalToSuperview().offset(16)
            make.trailing.equalToSuperview().offset(-16)
            make.height.equalTo(0.5)
        }

        // 标签容器
        let container = ZWBTagContainerView()
        var cfg = ZWBTagConfig()
        cfg.alignment         = alignment
        cfg.imageHeight       = 36
        cfg.horizontalSpacing = 10
        cfg.verticalSpacing   = 10
        cfg.contentInset      = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        container.update(items: items, config: cfg)
        container.backgroundColor    = UIColor.systemGray6
        container.layer.cornerRadius = 10
        contentView.addSubview(container)

        container.snp.makeConstraints { make in
            make.top.equalTo(sep.snp.bottom).offset(8)
            make.leading.equalToSuperview().offset(16)
            make.trailing.equalToSuperview().offset(-16)
            // 高度由 intrinsicContentSize 驱动，不写死
        }

        return container.snp.bottom
    }

    // MARK: - 测试数据

    private func textItems() -> [ZWBTagItem] {
        ["Swift", "UIKit", "Auto Layout", "StackView", "iOS", "Xcode", "SwiftUI", "Combine"]
            .map { .text($0) }
    }

    private func localImageItems() -> [ZWBTagItem] {
        let list: [(String, String)] = [
            ("star.fill", "星形"), ("heart.fill", "心形"), ("bolt.fill", "闪电"),
            ("cloud.fill", "云朵"), ("flame.fill", "火焰"), ("leaf.fill",  "叶子")
        ]
        return list.map { sym, desc in
            let img = UIImage(systemName: sym)?.withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
            return .image(source: .local(img!), tapHandler: { [weak self] in
                self?.showAlert("本地图片", "点击了「\(desc)」")
            })
        }
    }

    private func remoteImageItems() -> [ZWBTagItem] {
        let ph = UIImage(systemName: "photo")?.withTintColor(.systemGray3, renderingMode: .alwaysOriginal)
        return (1...6).map { i in
            let url = URL(string: "https://picsum.photos/seed/zwb\(i)/80/80")!
            return .image(source: .remote(url: url, placeholder: ph), tapHandler: { [weak self] in
                self?.showAlert("网络图片", "点击了第 \(i) 张")
            })
        }
    }

    private func mixedSourceItems() -> [ZWBTagItem] {
        let ph = UIImage(systemName: "photo")?.withTintColor(.systemGray3, renderingMode: .alwaysOriginal)
        return (1...6).map { i in
            let local: UIImage? = i.isMultiple(of: 2)
                ? UIImage(systemName: "checkmark.circle.fill")?.withTintColor(.systemGreen, renderingMode: .alwaysOriginal)
                : nil
            let url = URL(string: "https://picsum.photos/seed/mix\(i)/80/80")!
            return .image(
                source: .localOrRemote(local: local, url: url, placeholder: ph),
                tapHandler: { [weak self] in
                    self?.showAlert("混合来源", "第 \(i) 张 → \(i.isMultiple(of: 2) ? "本地" : "网络")")
                }
            )
        }
    }

    private func mixedItems(layout: ZWBImageTextLayout) -> [ZWBTagItem] {
        let list: [(String, String)] = [
            ("person.fill", "用户"), ("bell.fill", "通知"), ("cart.fill", "购物车"),
            ("magnifyingglass", "搜索"), ("gearshape.fill", "设置"), ("envelope.fill", "邮件")
        ]
        return list.map { sym, text in
            let img = UIImage(systemName: sym)?.withTintColor(.systemOrange, renderingMode: .alwaysOriginal)
            return .mixed(source: .local(img!), text: text, layout: layout, spacing: 5,
                          tapHandler: { [weak self] in self?.showAlert("图文混合", "「\(text)」被点击") })
        }
    }

    private func allItems() -> [ZWBTagItem] {
        let ph    = UIImage(systemName: "photo")?.withTintColor(.systemGray3, renderingMode: .alwaysOriginal)
        let star  = UIImage(systemName: "star.fill")?.withTintColor(.systemYellow, renderingMode: .alwaysOriginal)
        let url1  = URL(string: "https://picsum.photos/seed/all1/80/80")!
        let url2  = URL(string: "https://picsum.photos/seed/all2/80/80")!

        return [
            .text("公告"),
            .image(source: .local(star!), tapHandler: { [weak self] in self?.showAlert("本地图", "") }),
            .text("最新动态"),
            .image(source: .remote(url: url1, placeholder: ph), tapHandler: { [weak self] in self?.showAlert("网络图", "") }),
            .mixed(source: .local(star!), text: "精选", layout: .imageLeft, spacing: 4, tapHandler: nil),
            .text("iOS开发"),
            .mixed(source: .localOrRemote(local: nil, url: url2, placeholder: ph),
                   text: "热门", layout: .imageRight, spacing: 4,
                   tapHandler: { [weak self] in self?.showAlert("混合图文", "热门") }),
            .text("SwiftUI"),
        ]
    }

    // MARK: - 工具

    private func showAlert(_ title: String, _ msg: String) {
        let ac = UIAlertController(title: title, message: msg, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "OK", style: .default))
        present(ac, animated: true)
    }
}
