import SwiftUI
import Defaults

struct OpenURLView: View {
	@State private var urlString: String = {
		guard
			let url = Defaults[.url],
			!url.isFileURL
		else {
			return ""
		}

		return url.absoluteString.removingPercentEncoding ?? url.absoluteString
	}()

	private var normalizedUrlString: String {
		URL(humanString: urlString)?.absoluteString ?? urlString
	}

	let loadHandler: (URL) -> Void

	var body: some View {
		VStack(alignment: .trailing) {
			if SSApp.isFirstLaunch {
				HStack {
					HStack(spacing: 3) {
						Text("You could, for example,")
						Button("show the time.") {
							urlString = "https://time.pablopunk.com/?seconds&fg=white&bg=transparent"
						}
							.buttonStyle(LinkButtonStyle())
					}
					Spacer()
					Button("More ideas") {
						"https://github.com/sindresorhus/Plash/issues/1".openUrl()
					}
						.buttonStyle(LinkButtonStyle())
				}
					.box()
			}
			TextField(
				"sindresorhus.com",
				// `removingNewlines` is a workaround for a SwiftUI bug where it doesn't respect the line limit when pasting in multiple lines.
				// TODO: Report to Apple. Still an issue on macOS 11.
				text: $urlString.setMap(\.removingNewlines)
			)
				.lineLimit(1)
				.frame(minWidth: 400)
				.padding(.vertical)
			// TODO: Use `Button` when targeting macOS 11.
			NativeButton("Open", keyEquivalent: .return) {
				guard let url = URL(string: normalizedUrlString) else {
					return
				}

				loadHandler(url)
			}
				.disabled(!URL.isValid(string: normalizedUrlString))
		}
			.padding()
	}
}

struct OpenURLView_Previews: PreviewProvider {
	static var previews: some View {
		OpenURLView { _ in }
	}
}
