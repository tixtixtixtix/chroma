//
//  ChromaHarness.swift
//
//  Run with: droppykit run
//
//  Not named main.swift on purpose: Swift treats that name as top-level code,
//  which cannot coexist with @main.
//

import Foundation
import DroppyKit
import DroppyKitHarness
import Chroma

@main
struct ChromaHarness: DropletHarnessApp {
    static var manifestURL: URL? {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("droplet.json")
    }
    static func makeDroplet() -> any Droplet { ChromaDroplet() }
}
