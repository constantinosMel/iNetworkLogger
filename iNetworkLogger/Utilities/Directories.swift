import Foundation

enum Directories {
    static func libraryDirectory() -> String {
        #if os(iOS)
        return NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true)[0]
        #else
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library").path
        #endif
    }
} 