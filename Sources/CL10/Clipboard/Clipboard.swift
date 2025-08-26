import AppKit
import Foundation

final class Clipboard {
    private let pb = NSPasteboard.general
    private var lastSeenChangeCount: Int = NSPasteboard.general.changeCount

    func writeText(_ s: String) {
        pb.clearContents()
        pb.declareTypes([.string, NSPasteboard.PasteboardType(Constants.markerUTI)], owner: nil)
        pb.setString(s, forType: .string)
        pb.setString("1", forType: NSPasteboard.PasteboardType(Constants.markerUTI))
        lastSeenChangeCount = pb.changeCount
    }

    func readNewTextIfAvailable() -> String? {
        let cc = pb.changeCount
        guard cc != lastSeenChangeCount else { return nil }
        lastSeenChangeCount = cc
        if pb.string(forType: NSPasteboard.PasteboardType(Constants.markerUTI)) != nil {
            return nil
        }
        if let s = pb.string(forType: .string) { return s }
        return nil
    }
}
