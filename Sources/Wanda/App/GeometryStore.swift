import CoreGraphics
import Foundation

public struct GeometryStore {
    public static let defaultFrame = CGRect(x: 100, y: 100, width: 900, height: 560)

    private let defaults: UserDefaults
    private let key = "wanda.window.frame"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func save(frame: CGRect) {
        defaults.set(NSStringFromRect(NSRectFromCGRect(frame)), forKey: key)
    }

    public func load(validatingAgainst visibleFrame: CGRect) -> CGRect {
        guard
            let string = defaults.string(forKey: key),
            !string.isEmpty
        else {
            return Self.defaultFrame
        }

        let frame = NSRectFromString(string)
        guard frame.width >= 320, frame.height >= 200, visibleFrame.intersects(frame) else {
            return Self.defaultFrame
        }

        return frame
    }
}
