import Foundation
import SystemPackage

public struct AsyncBytes: AsyncSequence, Sendable {
    public typealias Element = UInt8

    let fileHandle: FileHandle

    init(pipe: Pipe) {
        self.fileHandle = pipe.fileHandleForReading
    }

    public func makeAsyncIterator() -> AsyncStream<Element>.Iterator {
        let handle = fileHandle
        return AsyncStream { continuation in
            handle.readabilityHandler = { h in
                let data = h.availableData

                guard !data.isEmpty else {
                    handle.readabilityHandler = nil
                    continuation.finish()
                    return
                }

                for byte in data {
                    continuation.yield(byte)
                }
            }

            continuation.onTermination = { _ in
                handle.readabilityHandler = nil
            }
        }.makeAsyncIterator()
    }
}

extension Pipe {
    var asyncBytes: AsyncBytes { AsyncBytes(pipe: self) }
}
