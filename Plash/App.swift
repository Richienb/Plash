import Cocoa
import Combine
import AppCenter
import AppCenterCrashes
import Defaults

/*
TODO: When targeting macOS 11:
- Use `App` protocol.
- Use SwiftUI Settings window.
- Remove `Principal class` key in Info.plist. It's not needed anymore.
- Remove storyboard.
- Present windows using SwiftUI.
*/

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
	var cancellables = Set<AnyCancellable>()

	let menu = SSMenu()
	let powerSourceWatcher = PowerSourceWatcher()

	lazy var statusItem = with(NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)) {
		$0.isVisible = true
		$0.behavior = [.removalAllowed, .terminationOnRemoval]
		$0.menu = menu
		$0.button?.image = Constants.menuBarIcon
	}

	lazy var statusItemButton = statusItem.button!

	lazy var webViewController = WebViewController()

	lazy var desktopWindow = with(DesktopWindow(screen: Defaults[.display].screen)) {
		$0.contentView = webViewController.webView
		$0.contentView?.isHidden = true
	}

	var isBrowsingMode = false {
		didSet {
			desktopWindow.isInteractive = isBrowsingMode
			desktopWindow.alphaValue = isBrowsingMode ? 1 : CGFloat(Defaults[.opacity])
			resetTimer()
		}
	}

	var isEnabled = true {
		didSet {
			statusItemButton.appearsDisabled = !isEnabled

			if isEnabled {
				loadUserURL()
				desktopWindow.makeKeyAndOrderFront(self)
			} else {
				// TODO: Properly unload the web view instead of just clearing and hiding it.
				desktopWindow.orderOut(self)
				loadURL(URL("about:blank"))
			}
		}
	}

	var reloadTimer: Timer?

	var webViewError: Error? {
		didSet {
			if let error = webViewError {
				statusItemButton.toolTip = "Error: \(error.localizedDescription)"
				statusItemButton.contentTintColor = .systemRed

				// TODO: Also present the error when the user just added it from the input box as then it's also "interactive".
				if isBrowsingMode {
					NSApp.presentError(error)
				}

				return
			}

			statusItemButton.contentTintColor = nil
		}
	}

	func applicationWillFinishLaunching(_ notification: Notification) {
		UserDefaults.standard.register(defaults: [
			"NSApplicationCrashOnExceptions": true
		])
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
		AppCenter.start(
			withAppSecret: "27131b3e-4b25-4a92-b0d3-7bb6883f7343",
			services: [
				Crashes.self
			]
		)

		_ = statusItemButton
		_ = desktopWindow

		// This is needed to make the window appear.
		// TODO: Find out why.
		desktopWindow.isInteractive = false

		setUpEvents()
		showWelcomeScreenIfNeeded()
	}

	func setEnabledStatus() {
		isEnabled = !(Defaults[.deactivateOnBattery] && powerSourceWatcher?.powerSource.isUsingBattery == true)
	}

	func resetTimer() {
		reloadTimer?.invalidate()
		reloadTimer = nil

		guard !isBrowsingMode else {
			return
		}

		guard let reloadInterval = Defaults[.reloadInterval] else {
			return
		}

		reloadTimer = Timer.scheduledTimer(withTimeInterval: reloadInterval, repeats: true) { [self] _ in
			loadUserURL()
		}
	}

	func recreateWebView() {
		webViewController.recreateWebView()
		desktopWindow.contentView = webViewController.webView
	}

	func recreateWebViewAndReload() {
		recreateWebView()
		loadUserURL()
	}

	func loadUserURL() {
		loadURL(Defaults[.url])
	}

	func loadURL(_ url: URL?) {
		webViewError = nil

		guard var url = url else {
			return
		}

		do {
			url = try replacePlaceholders(of: url) ?? url
		} catch {
			error.presentAsModal()
			return
		}

		// TODO: This is just a quick fix. The proper fix is to create a new web view below the existing one (with no opacity), load the URL, if it succeeds, we fade out the old one while fading in the new one. If it fails, we discard the new web view.
		if !url.isFileURL, !Reachability.isOnlineExtensive() {
			webViewError = NSError.appError("No internet connection.")
			return
		}

		// TODO: Report the bug to Apple.
		// WKWebView has a bug where it can only load a local file once. So if you load file A, load file B, and load file A again, it errors. And if you load the same file as the existing one, nothing happens. Quality engineering.
		if url.isFileURL {
			recreateWebView()
		}

		webViewController.loadURL(url)

		// TODO: Add a callback to `loadURL` when it's done loading instead.
		// TODO: Fade in the web view.
		delay(seconds: 1) { [self] in
			desktopWindow.contentView?.isHidden = false
		}
	}

	func openLocalWebsite() {
		NSApp.activate(ignoringOtherApps: true)

		let panel = NSOpenPanel()
		panel.canChooseFiles = false
		panel.canChooseDirectories = true
		panel.canCreateDirectories = false
		panel.title = "Open Local Website"
		panel.message = "Choose a directory with a “index.html” file."

		// Ensure it's above the window when in "Browsing Mode".
		panel.level = .floating

		if
			let url = Defaults[.url],
			url.isFileURL
		{
			panel.directoryURL = url
		}

		panel.begin { [weak self] in
			guard
				let self = self,
				$0 == .OK,
				let url = panel.url
			else {
				return
			}

			guard url.appendingPathComponent("index.html", isDirectory: false).exists else {
				NSAlert.showModal(message: "Please choose a directory that contains a “index.html” file.")
				self.openLocalWebsite()
				return
			}

			do {
				try SecurityScopedBookmarkManager.saveBookmark(for: url)
			} catch {
				NSApp.presentError(error)
				return
			}

			Defaults[.url] = url
		}
	}

	/**
	Replaces app-specific placeholder strings in the given URL with a corresponding value.
	*/
	func replacePlaceholders(of url: URL) throws -> URL? {
		// Here we swap out `[[screenWidth]]` and `[[screenHeight]]` for their actual values.
		// We proceed only if we have an `NSScreen` to work with.
		guard let screen = desktopWindow.targetScreen?.withFallbackToMain ?? .main else {
			return nil
		}

		return try url
			.replacingPlaceholder("[[screenWidth]]", with: String(format: "%.0f", screen.visibleFrameWithoutStatusBar.width))
			.replacingPlaceholder("[[screenHeight]]", with: String(format: "%.0f", screen.visibleFrameWithoutStatusBar.height))
	}
}
