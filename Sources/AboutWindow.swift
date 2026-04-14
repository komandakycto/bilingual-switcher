import Cocoa

class AboutWindowController: NSWindowController {

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About Bilingual Switcher"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // App icon
        if let iconPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let icon = NSImage(contentsOfFile: iconPath) {
            let imageView = NSImageView(frame: NSRect(x: 120, y: 120, width: 80, height: 80))
            imageView.image = icon
            imageView.imageScaling = .scaleProportionallyUpOrDown
            contentView.addSubview(imageView)
        }

        let nameLabel = NSTextField(labelWithString: "Bilingual Switcher")
        nameLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        nameLabel.alignment = .center
        nameLabel.frame = NSRect(x: 20, y: 90, width: 280, height: 24)
        contentView.addSubview(nameLabel)

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let versionLabel = NSTextField(labelWithString: "Version \(version)")
        versionLabel.font = .systemFont(ofSize: 12)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        versionLabel.frame = NSRect(x: 20, y: 68, width: 280, height: 18)
        contentView.addSubview(versionLabel)

        let descLabel = NSTextField(labelWithString: "Switch text between English and Russian\nkeyboard layouts with a hotkey.")
        descLabel.font = .systemFont(ofSize: 11)
        descLabel.textColor = .secondaryLabelColor
        descLabel.alignment = .center
        descLabel.maximumNumberOfLines = 2
        descLabel.frame = NSRect(x: 20, y: 30, width: 280, height: 32)
        contentView.addSubview(descLabel)

        let linkButton = NSButton(title: "GitHub", target: self, action: #selector(openGitHub))
        linkButton.bezelStyle = .inline
        linkButton.frame = NSRect(x: 125, y: 8, width: 70, height: 22)
        contentView.addSubview(linkButton)
    }

    @objc private func openGitHub() {
        // Update this URL once the repo is published
        if let url = URL(string: "https://github.com/komandakycto/bilingual-switcher") {
            NSWorkspace.shared.open(url)
        }
    }
}
