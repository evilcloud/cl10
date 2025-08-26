import AppKit
import Foundation

enum Constants {
    static let capacity = 10
    static let maxTextBytes = 256 * 1024
    static let socketDir = "/tmp"
    static let socketNamePrefix = "cl10-"
    static let markerUTI = "com.cl10.marker"
    static let connectTimeoutMs: Int = 200  // Int, not Int32
    static let ioTimeoutSec: Int = 2  // Int, not Int32
    static let version = "0.1.0-mvp"
}
