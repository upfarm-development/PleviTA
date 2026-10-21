// Where this app keeps files of its own (the artwork cache, the Home copy, the playback log).

import Foundation

enum StorageLocation {
    static var base: URL {
        #if os(tvOS)
        let directory = FileManager.SearchPathDirectory.cachesDirectory
        #else
        let directory = FileManager.SearchPathDirectory.applicationSupportDirectory
        #endif
        return FileManager.default.urls(for: directory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }
}
