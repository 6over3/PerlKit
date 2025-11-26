// MARK: - PerlKit.swift

import Foundation
import SystemPackage
import WasmKit
import WasmKitWASI

// MARK: - Error Types

/// Errors that can occur during PerlKit operations.
public enum PerlKitError: Error, CustomStringConvertible, Sendable {
    case initializationFailed(exitCode: Int32, perlError: String?)
    case moduleLoadFailed(String)
    case conversionFailed(String)
    case disposed(String)
    case operationFailed(String)
    case invalidArgument(String)
    case fileNotFound(String)
    case typeMismatch(expected: PerlValueType, actual: PerlValueType)

    public var description: String {
        switch self {
        case .initializationFailed(let code, let error):
            let errorMsg = error.map { " - \($0)" } ?? ""
            return "Perl initialization failed with exit code \(code)\(errorMsg)"
        case .moduleLoadFailed(let msg):
            return "Failed to load WASM module: \(msg)"
        case .conversionFailed(let msg):
            return "Type conversion failed: \(msg)"
        case .disposed(let what):
            return "\(what) has been disposed"
        case .operationFailed(let msg):
            return "Operation failed: \(msg)"
        case .invalidArgument(let msg):
            return "Invalid argument: \(msg)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .typeMismatch(let expected, let actual):
            return "Type mismatch: expected \(expected), got \(actual)"
        }
    }
}

// MARK: - Perl Types

/// Represents the type of a Perl value.
public enum PerlValueType: Int32, Sendable {
    case undef = 0
    case `true` = 1
    case `false` = 2
    case int = 3
    case double = 4
    case string = 5
    case array = 6
    case hash = 7
    case code = 8
    case ref = 9
}

/// Represents the calling context for Perl operations.
public enum PerlContext: Int32, Sendable {
    case void = 0
    case scalar = 1
    case list = 2
}

// MARK: - File System Wrapper

/// Content of a file in the virtual file system.
public enum FileContent: Sendable {
    case bytes(Data)
    case handle(FileDescriptor)
}

/// A simple file system wrapper for PerlKit.
public final class PerlFileSystem: @unchecked Sendable {
    private let memoryFS: MemoryFileSystem

    public init() throws {
        self.memoryFS = try MemoryFileSystem(preopens: ["/": "/"])
    }

    /// Adds a file with string content.
    public func addFile(at path: String, content: String) throws {
        try memoryFS.addFile(at: path, content: content)
    }

    /// Adds a file with binary content.
    public func addFile(at path: String, content: Data) throws {
        try memoryFS.addFile(at: path, content: Array(content))
    }

    /// Adds a file backed by a file descriptor.
    public func addFile(at path: String, handle: FileDescriptor) throws {
        try memoryFS.addFile(at: path, handle: handle)
    }

    /// Gets the content of a file.
    public func getFile(at path: String) throws -> FileContent {
        let content = try memoryFS.getFile(at: path)
        switch content {
        case .bytes(let bytes):
            return .bytes(Data(bytes))
        case .handle(let handle):
            return .handle(handle)
        }
    }

    /// Removes a file.
    public func removeFile(at path: String) throws {
        try memoryFS.removeFile(at: path)
    }

    internal var underlying: MemoryFileSystem {
        memoryFS
    }
}

// MARK: - Result Types

/// Result of a Perl evaluation or file execution.
public struct PerlResult: Sendable {
    public let success: Bool
    public let error: String?
    public let exitCode: Int32
}

// MARK: - Configuration

/// Options for creating a PerlKit instance.
public struct PerlKitOptions: Sendable {
    /// Environment variables to pass to Perl.
    public let environment: [String: String]

    /// Virtual filesystem to provide to Perl.
    public let fileSystem: PerlFileSystem?

    /// Whether to capture stdout (default: true).
    public let captureStdout: Bool

    /// Whether to capture stderr (default: true).
    public let captureStderr: Bool

    public init(
        environment: [String: String] = [:],
        fileSystem: PerlFileSystem? = nil,
        captureStdout: Bool = true,
        captureStderr: Bool = true
    ) {
        self.environment = environment
        self.fileSystem = fileSystem ?? (try? PerlFileSystem())
        self.captureStdout = captureStdout
        self.captureStderr = captureStderr
    }
}

// MARK: - WASM Exports Wrapper

/// Type-safe wrapper around ZeroPerl WASM exports.
private struct ZeroPerlExports {
    private let memory: Memory
    private let instance: Instance

    init(instance: Instance) throws {
        self.instance = instance
        guard let mem = instance.exports[memory: "memory"] else {
            throw PerlKitError.moduleLoadFailed("Memory export not found")
        }
        self.memory = mem
    }

    // MARK: - Memory Management

    func malloc(_ size: Int32) throws -> Int32 {
        try callInt32("malloc", size)
    }

    func free(_ ptr: Int32) throws {
        try callVoid("free", ptr)
    }

    // MARK: - Initialization

    func initialize() throws -> Int32 {
        try callInt32("zeroperl_init")
    }

    func initializeWithArgs(_ argc: Int32, _ argv: Int32) throws -> Int32 {
        try callInt32("zeroperl_init_with_args", argc, argv)
    }

    func freeInterpreter() throws {
        try callVoid("zeroperl_free_interpreter")
    }

    func shutdown() throws {
        try callVoid("zeroperl_shutdown")
    }

    func reset() throws -> Int32 {
        try callInt32("zeroperl_reset")
    }

    // MARK: - Execution

    func eval(codePtr: Int32, context: Int32, argc: Int32, argv: Int32) throws -> Int32 {
        try callInt32("zeroperl_eval", codePtr, context, argc, argv)
    }

    func runFile(pathPtr: Int32, argc: Int32, argv: Int32) throws -> Int32 {
        try callInt32("zeroperl_run_file", pathPtr, argc, argv)
    }

    // MARK: - Error Handling

    func lastError() throws -> Int32 {
        try callInt32("zeroperl_last_error")
    }

    func clearError() throws {
        try callVoid("zeroperl_clear_error")
    }

    // MARK: - Host Error Handling

    func setHostError(_ errorPtr: Int32) throws {
        try callVoid("zeroperl_set_host_error", errorPtr)
    }

    func getHostError() throws -> Int32 {
        try callInt32("zeroperl_get_host_error")
    }

    func clearHostError() throws {
        try callVoid("zeroperl_clear_host_error")
    }

    // MARK: - Status

    func isInitialized() throws -> Int32 {
        try callInt32("zeroperl_is_initialized")
    }

    func canEvaluate() throws -> Int32 {
        try callInt32("zeroperl_can_evaluate")
    }

    func flush() throws -> Int32 {
        try callInt32("zeroperl_flush")
    }

    // MARK: - Value Creation

    func newInt(_ value: Int32) throws -> Int32 {
        try callInt32("zeroperl_new_int", value)
    }

    func newUInt(_ value: UInt32) throws -> Int32 {
        let signed = Int32(bitPattern: value)
        return try callInt32("zeroperl_new_uint", signed)
    }

    func newDouble(_ value: Double) throws -> Int32 {
        guard let function = instance.exports[function: "zeroperl_new_double"] else {
            throw PerlKitError.moduleLoadFailed("Function 'zeroperl_new_double' not found")
        }
        let values: [Value] = [.f64(value.bitPattern)]
        let results = try function(values)
        guard let first = results.first, case .i32(let result) = first else {
            throw PerlKitError.operationFailed("No return value from zeroperl_new_double")
        }
        return Int32(bitPattern: result)
    }

    func newString(_ ptr: Int32, _ length: Int32) throws -> Int32 {
        try callInt32("zeroperl_new_string", ptr, length)
    }

    func newBool(_ value: Int32) throws -> Int32 {
        try callInt32("zeroperl_new_bool", value)
    }

    func newUndef() throws -> Int32 {
        try callInt32("zeroperl_new_undef")
    }

    // MARK: - Value Conversion

    func toInt(_ ptr: Int32, _ outPtr: Int32) throws -> Int32 {
        try callInt32("zeroperl_to_int", ptr, outPtr)
    }

    func toDouble(_ ptr: Int32, _ outPtr: Int32) throws -> Int32 {
        try callInt32("zeroperl_to_double", ptr, outPtr)
    }

    func toString(_ ptr: Int32, _ lenPtr: Int32) throws -> Int32 {
        try callInt32("zeroperl_to_string", ptr, lenPtr)
    }

    func toBool(_ ptr: Int32) throws -> Int32 {
        try callInt32("zeroperl_to_bool", ptr)
    }

    func isUndef(_ ptr: Int32) throws -> Int32 {
        try callInt32("zeroperl_is_undef", ptr)
    }

    func getType(_ ptr: Int32) throws -> Int32 {
        try callInt32("zeroperl_get_type", ptr)
    }

    // MARK: - Reference Counting

    func incref(_ ptr: Int32) throws {
        try callVoid("zeroperl_incref", ptr)
    }

    func decref(_ ptr: Int32) throws {
        try callVoid("zeroperl_decref", ptr)
    }

    func valueFree(_ ptr: Int32) throws {
        try callVoid("zeroperl_value_free", ptr)
    }

    // MARK: - Array Operations

    func newArray() throws -> Int32 {
        try callInt32("zeroperl_new_array")
    }

    func arrayPush(_ arrayPtr: Int32, _ valuePtr: Int32) throws {
        try callVoid("zeroperl_array_push", arrayPtr, valuePtr)
    }

    func arrayPop(_ arrayPtr: Int32) throws -> Int32 {
        try callInt32("zeroperl_array_pop", arrayPtr)
    }

    func arrayGet(_ arrayPtr: Int32, _ index: Int32) throws -> Int32 {
        try callInt32("zeroperl_array_get", arrayPtr, index)
    }

    func arraySet(_ arrayPtr: Int32, _ index: Int32, _ valuePtr: Int32) throws -> Int32 {
        try callInt32("zeroperl_array_set", arrayPtr, index, valuePtr)
    }

    func arrayLength(_ arrayPtr: Int32) throws -> Int32 {
        try callInt32("zeroperl_array_length", arrayPtr)
    }

    func arrayClear(_ arrayPtr: Int32) throws {
        try callVoid("zeroperl_array_clear", arrayPtr)
    }

    func arrayToValue(_ arrayPtr: Int32) throws -> Int32 {
        try callInt32("zeroperl_array_to_value", arrayPtr)
    }

    func valueToArray(_ valuePtr: Int32) throws -> Int32 {
        try callInt32("zeroperl_value_to_array", valuePtr)
    }

    func arrayFree(_ arrayPtr: Int32) throws {
        try callVoid("zeroperl_array_free", arrayPtr)
    }

    // MARK: - Hash Operations

    func newHash() throws -> Int32 {
        try callInt32("zeroperl_new_hash")
    }

    func hashSet(_ hashPtr: Int32, _ keyPtr: Int32, _ valuePtr: Int32) throws -> Int32 {
        try callInt32("zeroperl_hash_set", hashPtr, keyPtr, valuePtr)
    }

    func hashGet(_ hashPtr: Int32, _ keyPtr: Int32) throws -> Int32 {
        try callInt32("zeroperl_hash_get", hashPtr, keyPtr)
    }

    func hashExists(_ hashPtr: Int32, _ keyPtr: Int32) throws -> Int32 {
        try callInt32("zeroperl_hash_exists", hashPtr, keyPtr)
    }

    func hashDelete(_ hashPtr: Int32, _ keyPtr: Int32) throws -> Int32 {
        try callInt32("zeroperl_hash_delete", hashPtr, keyPtr)
    }

    func hashClear(_ hashPtr: Int32) throws {
        try callVoid("zeroperl_hash_clear", hashPtr)
    }

    func hashIterNew(_ hashPtr: Int32) throws -> Int32 {
        try callInt32("zeroperl_hash_iter_new", hashPtr)
    }

    func hashIterNext(_ iterPtr: Int32, _ keyOutPtr: Int32, _ valueOutPtr: Int32) throws -> Int32 {
        try callInt32("zeroperl_hash_iter_next", iterPtr, keyOutPtr, valueOutPtr)
    }

    func hashIterFree(_ iterPtr: Int32) throws {
        try callVoid("zeroperl_hash_iter_free", iterPtr)
    }

    func hashToValue(_ hashPtr: Int32) throws -> Int32 {
        try callInt32("zeroperl_hash_to_value", hashPtr)
    }

    func valueToHash(_ valuePtr: Int32) throws -> Int32 {
        try callInt32("zeroperl_value_to_hash", valuePtr)
    }

    func hashFree(_ hashPtr: Int32) throws {
        try callVoid("zeroperl_hash_free", hashPtr)
    }

    // MARK: - Reference Operations

    func newRef(_ valuePtr: Int32) throws -> Int32 {
        try callInt32("zeroperl_new_ref", valuePtr)
    }

    func deref(_ refPtr: Int32) throws -> Int32 {
        try callInt32("zeroperl_deref", refPtr)
    }

    func isRef(_ valuePtr: Int32) throws -> Int32 {
        try callInt32("zeroperl_is_ref", valuePtr)
    }

    // MARK: - Variable Operations

    func getVar(_ namePtr: Int32) throws -> Int32 {
        try callInt32("zeroperl_get_var", namePtr)
    }

    func getArrayVar(_ namePtr: Int32) throws -> Int32 {
        try callInt32("zeroperl_get_array_var", namePtr)
    }

    func getHashVar(_ namePtr: Int32) throws -> Int32 {
        try callInt32("zeroperl_get_hash_var", namePtr)
    }

    func setVar(_ namePtr: Int32, _ valuePtr: Int32) throws -> Int32 {
        try callInt32("zeroperl_set_var", namePtr, valuePtr)
    }

    // MARK: - Function Registration

    func registerFunction(_ funcId: Int32, _ namePtr: Int32) throws {
        try callVoid("zeroperl_register_function", funcId, namePtr)
    }

    func registerMethod(_ funcId: Int32, _ packagePtr: Int32, _ methodPtr: Int32) throws {
        try callVoid("zeroperl_register_method", funcId, packagePtr, methodPtr)
    }

    // MARK: - Function Calling

    func call(_ namePtr: Int32, _ context: Int32, _ argc: Int32, _ argv: Int32) throws -> Int32 {
        try callInt32("zeroperl_call", namePtr, context, argc, argv)
    }

    func resultGet(_ resultPtr: Int32, _ index: Int32) throws -> Int32 {
        try callInt32("zeroperl_result_get", resultPtr, index)
    }

    func resultFree(_ resultPtr: Int32) throws {
        try callVoid("zeroperl_result_free", resultPtr)
    }

    // MARK: - Memory Access

    func readBytes(at offset: Int32, count: Int) -> [UInt8] {
        let start = Int(offset)
        guard start >= 0, start + count <= memory.data.count else { return [] }
        return Array(memory.data[start..<(start + count)])
    }

    func readCString(at offset: Int32) -> String {
        guard offset != 0 else { return "" }
        var length = 0
        let start = Int(offset)
        guard start >= 0, start < memory.data.count else { return "" }

        while start + length < memory.data.count && memory.data[start + length] != 0 {
            length += 1
        }
        guard length > 0 else { return "" }
        let bytes = Array(memory.data[start..<(start + length)])
        return String(decoding: bytes, as: UTF8.self)
    }

    func writeBytes(_ bytes: [UInt8]) throws -> Int32 {
        let ptr = try malloc(Int32(bytes.count))
        let start = Int(ptr)
        guard start >= 0, start + bytes.count <= memory.data.count else {
            throw PerlKitError.operationFailed("Invalid memory write")
        }
        memory.withUnsafeMutableBufferPointer(offset: UInt(start), count: bytes.count) { buffer in
            for (i, byte) in bytes.enumerated() {
                buffer[i] = byte
            }
        }
        return ptr
    }

    func writeCString(_ string: String) throws -> Int32 {
        var bytes = Array(string.utf8)
        bytes.append(0)
        return try writeBytes(bytes)
    }

    func writeInt32(at offset: Int32, value: Int32) {
        let start = Int(offset)
        guard start >= 0, start + 4 <= memory.data.count else { return }
        let bytes = withUnsafeBytes(of: value) { Array($0) }
        memory.withUnsafeMutableBufferPointer(offset: UInt(start), count: 4) { buffer in
            for (i, byte) in bytes.enumerated() {
                buffer[i] = byte
            }
        }
    }

    func readInt32(at offset: Int32) -> Int32 {
        let start = Int(offset)
        guard start >= 0, start + 4 <= memory.data.count else { return 0 }
        let bytes = Array(memory.data[start..<(start + 4)])
        return bytes.withUnsafeBytes { $0.load(as: Int32.self) }
    }

    func readUInt32(at offset: Int32) -> UInt32 {
        let start = Int(offset)
        guard start >= 0, start + 4 <= memory.data.count else { return 0 }
        let bytes = Array(memory.data[start..<(start + 4)])
        return bytes.withUnsafeBytes { $0.load(as: UInt32.self) }
    }

    func readDouble(at offset: Int32) -> Double {
        let start = Int(offset)
        guard start >= 0, start + 8 <= memory.data.count else { return 0 }
        let bytes = Array(memory.data[start..<(start + 8)])
        return bytes.withUnsafeBytes { $0.load(as: Double.self) }
    }

    // MARK: - Private Helpers

    private func callInt32(_ name: String, _ args: Int32...) throws -> Int32 {
        guard let function = instance.exports[function: name] else {
            throw PerlKitError.moduleLoadFailed("Function '\(name)' not found")
        }
        let values: [Value] = args.map { Value.i32(UInt32(bitPattern: $0)) }
        let results = try function(values)
        guard let first = results.first, case .i32(let result) = first else {
            throw PerlKitError.operationFailed("No return value from \(name)")
        }
        return Int32(bitPattern: result)
    }

    private func callVoid(_ name: String, _ args: Int32...) throws {
        guard let function = instance.exports[function: name] else {
            throw PerlKitError.moduleLoadFailed("Function '\(name)' not found")
        }
        let values: [Value] = args.map { Value.i32(UInt32(bitPattern: $0)) }
        _ = try function(values)
    }
}

// MARK: - Perl Value

/// Represents a Perl scalar value.
///
/// Provides conversion methods to Swift types and memory management.
/// Values should be explicitly disposed by calling `dispose()`.
public final class PerlValue {
    private let ptr: Int32
    private let exports: ZeroPerlExports
    private weak var perl: PerlKit?
    private var isDisposed = false

    fileprivate init(ptr: Int32, exports: ZeroPerlExports, perl: PerlKit? = nil) {
        self.ptr = ptr
        self.exports = exports
        self.perl = perl
    }

    internal var pointer: Int32 {
        get throws {
            try checkDisposed()
            return ptr
        }
    }

    // MARK: - Type Information

    /// Gets the type of this Perl value.
    public func type() throws -> PerlValueType {
        try checkDisposed()
        let typeCode = try exports.getType(ptr)
        guard let type = PerlValueType(rawValue: typeCode) else {
            throw PerlKitError.conversionFailed("Unknown type code: \(typeCode)")
        }
        return type
    }

    /// Checks if this value is undefined.
    public var isUndef: Bool {
        get throws {
            try checkDisposed()
            return try exports.isUndef(ptr) != 0
        }
    }

    /// Checks if this value is a reference.
    public var isRef: Bool {
        get throws {
            try checkDisposed()
            return try exports.isRef(ptr) != 0
        }
    }

    /// Checks if this value is an array reference.
    public var isArrayRef: Bool {
        get throws {
            try checkDisposed()
            let valueType = try type()
            return valueType == .array
        }
    }

    /// Checks if this value is a hash reference.
    public var isHashRef: Bool {
        get throws {
            try checkDisposed()
            let valueType = try type()
            return valueType == .hash
        }
    }

    /// Checks if this value is a code reference.
    public var isCodeRef: Bool {
        get throws {
            try checkDisposed()
            let valueType = try type()
            return valueType == .code
        }
    }

    // MARK: - Conversions

    /// Converts this value to a 32-bit integer.
    public func toInt() throws -> Int32 {
        try checkDisposed()
        let outPtr = try exports.malloc(4)
        defer { try? exports.free(outPtr) }
        let success = try exports.toInt(ptr, outPtr)
        guard success != 0 else {
            throw PerlKitError.conversionFailed("Failed to convert to Int")
        }
        return exports.readInt32(at: outPtr)
    }

    /// Converts this value to a 64-bit integer.
    public func toInt64() throws -> Int64 {
        Int64(try toInt())
    }

    /// Converts this value to a Swift Int.
    public func totInt() throws -> Int {
        Int(try toInt())
    }

    /// Converts this value to a double-precision float.
    public func toDouble() throws -> Double {
        try checkDisposed()
        let outPtr = try exports.malloc(8)
        defer { try? exports.free(outPtr) }
        let success = try exports.toDouble(ptr, outPtr)
        guard success != 0 else {
            throw PerlKitError.conversionFailed("Failed to convert to Double")
        }
        return exports.readDouble(at: outPtr)
    }

    /// Converts this value to a UTF-8 string.
    public func toString() throws -> String {
        try checkDisposed()
        let lenPtr = try exports.malloc(4)
        defer { try? exports.free(lenPtr) }
        let strPtr = try exports.toString(ptr, lenPtr)
        guard strPtr != 0 else { return "" }

        let length = Int(exports.readUInt32(at: lenPtr))
        let bytes = exports.readBytes(at: strPtr, count: length)
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Converts this value to a boolean using Perl's truth test.
    public func toBool() throws -> Bool {
        try checkDisposed()
        return try exports.toBool(ptr) != 0
    }

    /// Converts this value to a PerlArray if it is an array reference.
    ///
    /// - Parameter perl: The PerlKit instance to associate with the array.
    /// - Returns: A PerlArray if successful.
    /// - Throws: `PerlKitError.typeMismatch` if the value is not an array reference.
    public func toArray(using perl: PerlKit) throws -> PerlArray {
        try checkDisposed()
        let valueType = try type()
        guard valueType == .array else {
            throw PerlKitError.typeMismatch(expected: .array, actual: valueType)
        }
        let arrayPtr = try exports.valueToArray(ptr)
        guard arrayPtr != 0 else {
            throw PerlKitError.conversionFailed("Failed to convert value to array")
        }
        return PerlArray(ptr: arrayPtr, exports: exports, perl: perl)
    }

    /// Converts this value to a PerlHash if it is a hash reference.
    ///
    /// - Parameter perl: The PerlKit instance to associate with the hash.
    /// - Returns: A PerlHash if successful.
    /// - Throws: `PerlKitError.typeMismatch` if the value is not a hash reference.
    public func toHash(using perl: PerlKit) throws -> PerlHash {
        try checkDisposed()
        let valueType = try type()
        guard valueType == .hash else {
            throw PerlKitError.typeMismatch(expected: .hash, actual: valueType)
        }
        let hashPtr = try exports.valueToHash(ptr)
        guard hashPtr != 0 else {
            throw PerlKitError.conversionFailed("Failed to convert value to hash")
        }
        return PerlHash(ptr: hashPtr, exports: exports, perl: perl)
    }

    /// Converts this value to a Swift array of PerlValues if it is an array reference.
    ///
    /// - Parameter perl: The PerlKit instance to use for conversion.
    /// - Returns: An array of PerlValues.
    public func project(using perl: PerlKit) throws -> [PerlValue] {
        let perlArray = try toArray(using: perl)
        defer { try? perlArray.dispose() }

        var result: [PerlValue] = []
        let count = try perlArray.count
        for i in 0..<count {
            if let value = try perlArray.get(i) {
                result.append(value)
            }
        }
        return result
    }

    /// Converts this value to a Swift dictionary if it is a hash reference.
    ///
    /// - Parameter perl: The PerlKit instance to use for conversion.
    /// - Returns: A dictionary mapping string keys to PerlValues.
    public func project(using perl: PerlKit) throws -> [String: PerlValue] {
        let perlHash = try toHash(using: perl)
        defer { try? perlHash.dispose() }

        var result: [String: PerlValue] = [:]
        for (key, value) in try perlHash.entries() {
            result[key] = value
        }
        return result
    }

    // MARK: - Reference Operations

    /// Creates a reference to this value.
    public func createRef() throws -> PerlValue {
        try checkDisposed()
        let refPtr = try exports.newRef(ptr)
        guard refPtr != 0 else {
            throw PerlKitError.operationFailed("Failed to create reference")
        }
        return PerlValue(ptr: refPtr, exports: exports, perl: perl)
    }

    /// Dereferences this value.
    public func deref() throws -> PerlValue {
        try checkDisposed()
        let derefPtr = try exports.deref(ptr)
        guard derefPtr != 0 else {
            throw PerlKitError.operationFailed("Failed to dereference (not a reference?)")
        }
        return PerlValue(ptr: derefPtr, exports: exports, perl: perl)
    }

    // MARK: - Reference Counting

    /// Increments the reference count.
    public func incref() throws {
        try checkDisposed()
        try exports.incref(ptr)
    }

    /// Decrements the reference count.
    public func decref() throws {
        try checkDisposed()
        try exports.decref(ptr)
    }

    // MARK: - Memory Management

    /// Frees this value's memory.
    public func dispose() throws {
        guard !isDisposed else { return }
        try exports.valueFree(ptr)
        isDisposed = true
    }

    private func checkDisposed() throws {
        guard !isDisposed else {
            throw PerlKitError.disposed("PerlValue")
        }
    }
}

// MARK: - Perl Array

/// Represents a Perl array with Swift collection semantics.
///
/// Provides array manipulation methods.
/// Arrays should be explicitly disposed by calling `dispose()`.
public final class PerlArray {
    private let ptr: Int32
    private let exports: ZeroPerlExports
    private let perl: PerlKit
    private var isDisposed = false

    fileprivate init(ptr: Int32, exports: ZeroPerlExports, perl: PerlKit) {
        self.ptr = ptr
        self.exports = exports
        self.perl = perl
    }

    internal var pointer: Int32 {
        get throws {
            try checkDisposed()
            return ptr
        }
    }

    // MARK: - Array Operations

    /// Pushes a value onto the end of the array.
    public func push<T: PerlConvertible>(_ value: T) throws {
        try checkDisposed()
        let perlValue = try perl.toPerlValue(value)
        try exports.arrayPush(ptr, try perlValue.pointer)
        if !(value is PerlValue) {
            try perlValue.dispose()
        }
    }

    /// Pops a value from the end of the array.
    ///
    /// - Returns: The popped value, or nil if the array is empty.
    public func pop() throws -> PerlValue? {
        try checkDisposed()
        let valuePtr = try exports.arrayPop(ptr)
        guard valuePtr != 0 else { return nil }
        return PerlValue(ptr: valuePtr, exports: exports, perl: perl)
    }

    /// Gets a value at the specified index.
    ///
    /// - Parameter index: The index to retrieve.
    /// - Returns: The value at the index, or nil if out of bounds.
    public func get(_ index: Int) throws -> PerlValue? {
        try checkDisposed()
        let valuePtr = try exports.arrayGet(ptr, Int32(index))
        guard valuePtr != 0 else { return nil }
        return PerlValue(ptr: valuePtr, exports: exports, perl: perl)
    }

    /// Sets a value at the specified index.
    ///
    /// - Parameters:
    ///   - index: The index to set.
    ///   - value: The value to store.
    public func set<T: PerlConvertible>(_ index: Int, value: T) throws {
        try checkDisposed()
        let perlValue = try perl.toPerlValue(value)
        let success = try exports.arraySet(ptr, Int32(index), try perlValue.pointer)
        if !(value is PerlValue) {
            try perlValue.dispose()
        }
        guard success != 0 else {
            throw PerlKitError.operationFailed("Failed to set array element at index \(index)")
        }
    }

    /// The number of elements in the array.
    public var count: Int {
        get throws {
            try checkDisposed()
            return Int(try exports.arrayLength(ptr))
        }
    }

    /// Whether the array is empty.
    public var isEmpty: Bool {
        get throws {
            try count == 0
        }
    }

    /// Clears all elements from the array.
    public func removeAll() throws {
        try checkDisposed()
        try exports.arrayClear(ptr)
    }

    /// Converts this array to a PerlValue (array reference).
    public func ref() throws -> PerlValue {
        try checkDisposed()
        let valuePtr = try exports.arrayToValue(ptr)
        guard valuePtr != 0 else {
            throw PerlKitError.operationFailed("Failed to convert array to value")
        }
        return PerlValue(ptr: valuePtr, exports: exports, perl: perl)
    }

    /// Converts this array to a Swift array of PerlValues.
    public func project() throws -> [PerlValue] {
        try checkDisposed()
        var result: [PerlValue] = []
        let length = try count
        for i in 0..<length {
            if let value = try get(i) {
                result.append(value)
            }
        }
        return result
    }

    // MARK: - Subscript

    /// Accesses the element at the specified index.
    public subscript(index: Int) -> PerlValue? {
        get {
            try? get(index)
        }
    }

    // MARK: - Memory Management

    /// Frees this array's memory.
    public func dispose() throws {
        guard !isDisposed else { return }
        try exports.arrayFree(ptr)
        isDisposed = true
    }

    private func checkDisposed() throws {
        guard !isDisposed else {
            throw PerlKitError.disposed("PerlArray")
        }
    }
}

// MARK: - PerlArray + Sequence

extension PerlArray: Sequence {
    public struct Iterator: IteratorProtocol {
        private let array: PerlArray
        private var index: Int = 0
        private let length: Int

        init(_ array: PerlArray) {
            self.array = array
            self.length = (try? array.count) ?? 0
        }

        public mutating func next() -> PerlValue? {
            guard index < length else { return nil }
            let value = try? array.get(index)
            index += 1
            return value
        }
    }

    public func makeIterator() -> Iterator {
        Iterator(self)
    }
}

// MARK: - Perl Hash

/// Represents a Perl hash with Swift dictionary semantics.
///
/// Provides key-value operations.
/// Hashes should be explicitly disposed by calling `dispose()`.
public final class PerlHash {
    private let ptr: Int32
    private let exports: ZeroPerlExports
    private let perl: PerlKit
    private var isDisposed = false

    fileprivate init(ptr: Int32, exports: ZeroPerlExports, perl: PerlKit) {
        self.ptr = ptr
        self.exports = exports
        self.perl = perl
    }

    internal var pointer: Int32 {
        get throws {
            try checkDisposed()
            return ptr
        }
    }

    // MARK: - Hash Operations

    /// Sets a key-value pair in the hash.
    ///
    /// - Parameters:
    ///   - key: The key to set.
    ///   - value: The value to store.
    public func set<T: PerlConvertible>(key: String, value: T) throws {
        try checkDisposed()
        let perlValue = try perl.toPerlValue(value)
        let keyPtr = try exports.writeCString(key)
        defer { try? exports.free(keyPtr) }
        let success = try exports.hashSet(ptr, keyPtr, try perlValue.pointer)
        if !(value is PerlValue) {
            try perlValue.dispose()
        }
        guard success != 0 else {
            throw PerlKitError.operationFailed("Failed to set hash key '\(key)'")
        }
    }

    /// Gets a value by key.
    ///
    /// - Parameter key: The key to look up.
    /// - Returns: The value for the key, or nil if not found.
    public func get(key: String) throws -> PerlValue? {
        try checkDisposed()
        let keyPtr = try exports.writeCString(key)
        defer { try? exports.free(keyPtr) }
        let valuePtr = try exports.hashGet(ptr, keyPtr)
        guard valuePtr != 0 else { return nil }
        return PerlValue(ptr: valuePtr, exports: exports, perl: perl)
    }

    /// Checks if a key exists in the hash.
    ///
    /// - Parameter key: The key to check.
    /// - Returns: True if the key exists.
    public func contains(key: String) throws -> Bool {
        try checkDisposed()
        let keyPtr = try exports.writeCString(key)
        defer { try? exports.free(keyPtr) }
        return try exports.hashExists(ptr, keyPtr) != 0
    }

    /// Removes a key from the hash.
    ///
    /// - Parameter key: The key to remove.
    /// - Returns: True if the key was removed, false if it didn't exist.
    @discardableResult
    public func remove(key: String) throws -> Bool {
        try checkDisposed()
        let keyPtr = try exports.writeCString(key)
        defer { try? exports.free(keyPtr) }
        return try exports.hashDelete(ptr, keyPtr) != 0
    }

    /// Clears all entries from the hash.
    public func removeAll() throws {
        try checkDisposed()
        try exports.hashClear(ptr)
    }

    /// Converts this hash to a PerlValue (hash reference).
    public func ref() throws -> PerlValue {
        try checkDisposed()
        let valuePtr = try exports.hashToValue(ptr)
        guard valuePtr != 0 else {
            throw PerlKitError.operationFailed("Failed to convert hash to value")
        }
        return PerlValue(ptr: valuePtr, exports: exports, perl: perl)
    }

    // MARK: - Iteration

    /// Gets all key-value pairs.
    ///
    /// - Returns: An array of key-value tuples.
    public func entries() throws -> [(key: String, value: PerlValue)] {
        try checkDisposed()

        let iterPtr = try exports.hashIterNew(ptr)
        let keyOutPtr = try exports.malloc(4)
        let valueOutPtr = try exports.malloc(4)

        defer {
            try? exports.free(keyOutPtr)
            try? exports.free(valueOutPtr)
            try? exports.hashIterFree(iterPtr)
        }

        var results: [(key: String, value: PerlValue)] = []

        while try exports.hashIterNext(iterPtr, keyOutPtr, valueOutPtr) != 0 {
            let keyPtr = exports.readUInt32(at: keyOutPtr)
            let valuePtr = exports.readUInt32(at: valueOutPtr)

            let key = exports.readCString(at: Int32(bitPattern: keyPtr))
            let value = PerlValue(ptr: Int32(bitPattern: valuePtr), exports: exports, perl: perl)

            results.append((key, value))
        }

        return results
    }

    /// Gets all keys in the hash.
    ///
    /// - Returns: An array of keys.
    public func keys() throws -> [String] {
        try entries().map { $0.key }
    }

    /// Gets all values in the hash.
    ///
    /// - Returns: An array of values.
    public func values() throws -> [PerlValue] {
        try entries().map { $0.value }
    }

    /// Converts this hash to a Swift dictionary.
    ///
    /// - Returns: A dictionary mapping string keys to PerlValues.
    public func project() throws -> [String: PerlValue] {
        try checkDisposed()
        var result: [String: PerlValue] = [:]
        for (key, value) in try entries() {
            result[key] = value
        }
        return result
    }

    // MARK: - Subscript

    /// Accesses the value for the specified key.
    public subscript(key: String) -> PerlValue? {
        get {
            try? get(key: key)
        }
    }

    // MARK: - Memory Management

    /// Frees this hash's memory.
    public func dispose() throws {
        guard !isDisposed else { return }
        try exports.hashFree(ptr)
        isDisposed = true
    }

    private func checkDisposed() throws {
        guard !isDisposed else {
            throw PerlKitError.disposed("PerlHash")
        }
    }
}

// MARK: - PerlHash + Sequence

extension PerlHash: Sequence {
    public typealias Element = (key: String, value: PerlValue)

    public struct Iterator: IteratorProtocol {
        private var entries: [(key: String, value: PerlValue)]
        private var index: Int = 0

        init(_ hash: PerlHash) {
            self.entries = (try? hash.entries()) ?? []
        }

        public mutating func next() -> Element? {
            guard index < entries.count else { return nil }
            let entry = entries[index]
            index += 1
            return entry
        }
    }

    public func makeIterator() -> Iterator {
        Iterator(self)
    }
}

// MARK: - Perl Convertible Protocol

/// Types that can be converted to Perl values.
public protocol PerlConvertible {
    func toPerlValue(using perl: PerlKit) throws -> PerlValue
}

extension PerlValue: PerlConvertible {
    public func toPerlValue(using perl: PerlKit) throws -> PerlValue {
        self
    }
}

extension String: PerlConvertible {
    public func toPerlValue(using perl: PerlKit) throws -> PerlValue {
        try perl.createString(self)
    }
}

extension Int: PerlConvertible {
    public func toPerlValue(using perl: PerlKit) throws -> PerlValue {
        try perl.createInt(Int32(clamping: self))
    }
}

extension Int32: PerlConvertible {
    public func toPerlValue(using perl: PerlKit) throws -> PerlValue {
        try perl.createInt(self)
    }
}

extension Int64: PerlConvertible {
    public func toPerlValue(using perl: PerlKit) throws -> PerlValue {
        try perl.createInt(Int32(clamping: self))
    }
}

extension UInt: PerlConvertible {
    public func toPerlValue(using perl: PerlKit) throws -> PerlValue {
        try perl.createUInt(UInt32(clamping: self))
    }
}

extension UInt32: PerlConvertible {
    public func toPerlValue(using perl: PerlKit) throws -> PerlValue {
        try perl.createUInt(self)
    }
}

extension Double: PerlConvertible {
    public func toPerlValue(using perl: PerlKit) throws -> PerlValue {
        try perl.createDouble(self)
    }
}

extension Float: PerlConvertible {
    public func toPerlValue(using perl: PerlKit) throws -> PerlValue {
        try perl.createDouble(Double(self))
    }
}

extension Bool: PerlConvertible {
    public func toPerlValue(using perl: PerlKit) throws -> PerlValue {
        try perl.createBool(self)
    }
}

extension Optional: PerlConvertible where Wrapped: PerlConvertible {
    public func toPerlValue(using perl: PerlKit) throws -> PerlValue {
        switch self {
        case .some(let value):
            return try value.toPerlValue(using: perl)
        case .none:
            return try perl.createUndef()
        }
    }
}

extension Array: PerlConvertible where Element: PerlConvertible {
    public func toPerlValue(using perl: PerlKit) throws -> PerlValue {
        let array = try perl.createArray()
        for element in self {
            try array.push(element)
        }
        let value = try array.ref()
        try array.dispose()
        return value
    }
}

extension Dictionary: PerlConvertible where Key == String, Value: PerlConvertible {
    public func toPerlValue(using perl: PerlKit) throws -> PerlValue {
        let hash = try perl.createHash()
        for (key, value) in self {
            try hash.set(key: key, value: value)
        }
        let result = try hash.ref()
        try hash.dispose()
        return result
    }
}

// MARK: - Host Function

/// A function that can be registered and called from Perl.
public typealias PerlHostFunction = ([PerlValue]) throws -> PerlValue?

// MARK: - PerlKit Main Class

/// The main Perl interpreter interface.
///
/// Supports evaluating Perl code, creating and manipulating Perl values,
/// and bidirectional function calls between Swift and Perl.
///
/// Example:
/// ```swift
/// let perl = try PerlKit.create()
///
/// // Stream output line-by-line
/// Task {
///     for await line in perl.stdout {
///         print("Perl output:", line)
///     }
/// }
///
/// try perl.eval("print 'Hello, World!\\n'")
///
/// // Or get all accumulated output
/// let output = try await perl.getStdout()
///
/// try perl.dispose()
/// ```
public final class PerlKit {
    private let exports: ZeroPerlExports
    private let store: Store
    private var isDisposed = false

    private var hostFunctions: [Int32: PerlHostFunction] = [:]
    private var nextFunctionID: Int32 = 1

    private let stdoutPipe: Pipe?
    private let stderrPipe: Pipe?

    /// Async byte stream of stdout output.
    public var stdout: AsyncBytes? {
        stdoutPipe?.asyncBytes
    }

    /// Async byte stream of stderr output.
    public var stderr: AsyncBytes? {
        stderrPipe?.asyncBytes
    }

    private init(
        exports: ZeroPerlExports,
        store: Store,
        stdoutPipe: Pipe?,
        stderrPipe: Pipe?
    ) {
        self.exports = exports
        self.store = store
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
    }

    deinit {
        guard !isDisposed else { return }
        try? exports.freeInterpreter()
        stdoutPipe?.fileHandleForWriting.closeFile()
        stderrPipe?.fileHandleForWriting.closeFile()
        hostFunctions.removeAll()
    }

    // MARK: - Factory Methods

    /// Creates a new PerlKit instance with default options.
    public static func create(options: PerlKitOptions = PerlKitOptions()) throws -> PerlKit {
        let wasmBytes = try loadZeroPerlWasm()
        var config = EngineConfiguration()
        config.threadingModel = .direct
        config.compilationMode = .lazy
        config.stackSize = 8_388_608

        let engine = Engine(configuration: config)
        let store = Store(engine: engine)

        let stdoutPipe = options.captureStdout ? Pipe() : nil
        let stderrPipe = options.captureStderr ? Pipe() : nil

        let stdoutFd = stdoutPipe.map { FileDescriptor(rawValue: $0.fileHandleForWriting.fileDescriptor) } ?? .standardOutput
        let stderrFd = stderrPipe.map { FileDescriptor(rawValue: $0.fileHandleForWriting.fileDescriptor) } ?? .standardError

        let wasi = try WASIBridgeToHost(
            args: ["zeroperl"],
            environment: options.environment,
            fileSystemProvider: options.fileSystem?.underlying,
            stdout: stdoutFd,
            stderr: stderrFd
        )

        let module = try parseWasm(bytes: wasmBytes)

        final class PerlReference {
            weak var perl: PerlKit?
        }
        let perlRef = PerlReference()

        var imports = Imports()

        for (moduleName, hostModule) in wasi.wasiHostModules {
            for (name, wasiFunction) in hostModule.functions {
                let function = Function(store: store, type: wasiFunction.type) { caller, args in
                    guard case .memory(let memory) = caller.instance?.export("memory") else {
                        throw PerlKitError.operationFailed("Missing required \"memory\" export")
                    }
                    return try wasiFunction.implementation(memory, args)
                }
                imports.define(module: moduleName, name: name, function)
            }
        }

        let hostFunc = Function(store: store, parameters: [.i32, .i32, .i32], results: [.i32]) {
            _, args -> [Value] in
            guard let perl = perlRef.perl else { return [.i32(0)] }

            guard case .i32(let funcIdValue) = args[0],
                  case .i32(let argcValue) = args[1],
                  case .i32(let argvPtrValue) = args[2]
            else { return [.i32(0)] }

            let funcId = Int32(bitPattern: funcIdValue)
            let argc = Int32(bitPattern: argcValue)
            let argvPtr = Int32(bitPattern: argvPtrValue)

            let result = perl.handleHostCall(funcId: funcId, argc: argc, argvPtr: argvPtr)
            return [Value.i32(UInt32(bitPattern: result))]
        }

        imports.define(module: "env", name: "call_host_function", hostFunc)

        let instance = try module.instantiate(store: store, imports: imports)
        try wasi.initialize(instance)

        let zeroPerlExports = try ZeroPerlExports(instance: instance)

        let perl = PerlKit(
            exports: zeroPerlExports,
            store: store,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe
        )

        perlRef.perl = perl

        let result = try perl.exports.initialize()
        guard result == 0 else {
            let error = try? perl.lastError()
            throw PerlKitError.initializationFailed(exitCode: result, perlError: error)
        }

        return perl
    }

    /// Creates a new PerlKit instance with command-line arguments.
    ///
    /// - Parameters:
    ///   - args: Command-line arguments to pass to Perl.
    ///   - options: Configuration options.
    /// - Returns: A configured PerlKit instance.
    public static func create(
        withArgs args: [String],
        options: PerlKitOptions = PerlKitOptions()
    ) throws -> PerlKit {
        let wasmBytes = try loadZeroPerlWasm()
        var config = EngineConfiguration()
        config.threadingModel = .direct
        config.compilationMode = .lazy
        config.stackSize = 8_388_608

        let engine = Engine(configuration: config)
        let store = Store(engine: engine)

        let stdoutPipe = options.captureStdout ? Pipe() : nil
        let stderrPipe = options.captureStderr ? Pipe() : nil

        let stdoutFd = stdoutPipe.map { FileDescriptor(rawValue: $0.fileHandleForWriting.fileDescriptor) } ?? .standardOutput
        let stderrFd = stderrPipe.map { FileDescriptor(rawValue: $0.fileHandleForWriting.fileDescriptor) } ?? .standardError

        let wasi = try WASIBridgeToHost(
            args: ["zeroperl"] + args,
            environment: options.environment,
            fileSystemProvider: options.fileSystem?.underlying,
            stdout: stdoutFd,
            stderr: stderrFd
        )

        let module = try parseWasm(bytes: wasmBytes)

        final class PerlReference {
            weak var perl: PerlKit?
        }
        let perlRef = PerlReference()

        var imports = Imports()

        for (moduleName, hostModule) in wasi.wasiHostModules {
            for (name, wasiFunction) in hostModule.functions {
                let function = Function(store: store, type: wasiFunction.type) { caller, args in
                    guard case .memory(let memory) = caller.instance?.export("memory") else {
                        throw PerlKitError.operationFailed("Missing required \"memory\" export")
                    }
                    return try wasiFunction.implementation(memory, args)
                }
                imports.define(module: moduleName, name: name, function)
            }
        }

        let hostFunc = Function(store: store, parameters: [.i32, .i32, .i32], results: [.i32]) {
            _, args -> [Value] in
            guard let perl = perlRef.perl else { return [.i32(0)] }

            guard case .i32(let funcIdValue) = args[0],
                  case .i32(let argcValue) = args[1],
                  case .i32(let argvPtrValue) = args[2]
            else { return [.i32(0)] }

            let funcId = Int32(bitPattern: funcIdValue)
            let argc = Int32(bitPattern: argcValue)
            let argvPtr = Int32(bitPattern: argvPtrValue)

            let result = perl.handleHostCall(funcId: funcId, argc: argc, argvPtr: argvPtr)
            return [Value.i32(UInt32(bitPattern: result))]
        }

        imports.define(module: "env", name: "call_host_function", hostFunc)

        let instance = try module.instantiate(store: store, imports: imports)
        try wasi.initialize(instance)

        let zeroPerlExports = try ZeroPerlExports(instance: instance)

        let perl = PerlKit(
            exports: zeroPerlExports,
            store: store,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe
        )

        perlRef.perl = perl

        // Build argv for init_with_args
        var argvPtrs: [Int32] = []
        for arg in args {
            let ptr = try zeroPerlExports.writeCString(arg)
            argvPtrs.append(ptr)
        }

        let argvArrayPtr: Int32
        if !argvPtrs.isEmpty {
            argvArrayPtr = try zeroPerlExports.malloc(Int32(argvPtrs.count * 4))
            for (i, ptr) in argvPtrs.enumerated() {
                zeroPerlExports.writeInt32(at: argvArrayPtr + Int32(i * 4), value: ptr)
            }
        } else {
            argvArrayPtr = 0
        }

        let result = try zeroPerlExports.initializeWithArgs(Int32(args.count), argvArrayPtr)

        // Clean up
        for ptr in argvPtrs {
            try? zeroPerlExports.free(ptr)
        }
        if argvArrayPtr != 0 {
            try? zeroPerlExports.free(argvArrayPtr)
        }

        guard result == 0 else {
            let error = try? perl.lastError()
            throw PerlKitError.initializationFailed(exitCode: result, perlError: error)
        }

        return perl
    }

    // MARK: - Output Access

    /// Gets all stdout output captured so far.
    ///
    /// Automatically flushes Perl output buffers to ensure all output is included.
    public func readStdout() throws -> String {
         try flush()
        guard let fd = stdoutPipe?.fileHandleForReading.fileDescriptor else { return "" }
        return Self.readNonBlocking(fd: fd)
    }

     private static func readNonBlocking(fd: Int32) -> String {
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        defer { _ = fcntl(fd, F_SETFL, flags) }
        
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n > 0 {
                result.append(contentsOf: buffer.prefix(n))
            } else {
                break
            }
        }
        
        return String(decoding: result, as: UTF8.self)
    }


    /// Gets all stderr output captured so far.
    ///
    /// Automatically flushes Perl output buffers to ensure all output is included.
    public func readStderr() throws -> String {
        try flush()
        guard let fd = stderrPipe?.fileHandleForReading.fileDescriptor else { return "" }
        return Self.readNonBlocking(fd: fd)
    }

    // MARK: - Host Function Handling

    private func handleHostCall(funcId: Int32, argc: Int32, argvPtr: Int32) -> Int32 {
        guard let function = hostFunctions[funcId] else {
            setHostError("Host function \(funcId) not found")
            return 0
        }

        do {
            let args = buildArguments(argc: argc, argvPtr: argvPtr)
            let result = try function(args)
            return try result?.pointer ?? exports.newUndef()
        } catch {
            setHostError(error)
            return 0
        }
    }

    private func buildArguments(argc: Int32, argvPtr: Int32) -> [PerlValue] {
        guard argc > 0 else { return [] }

        return (0..<argc).compactMap { i in
            let valPtr = exports.readInt32(at: argvPtr + (i * 4))
            return valPtr != 0 ? PerlValue(ptr: valPtr, exports: exports, perl: self) : nil
        }
    }

    private func setHostError(_ error: Error) {
        let message = (error as? PerlKitError)?.description ?? String(describing: error)
        setHostError(message)
    }

    private func setHostError(_ message: String) {
        do {
            let errorPtr = try exports.writeCString(message)
            defer { try? exports.free(errorPtr) }
            try exports.setHostError(errorPtr)
        } catch {
            // Silently fail if we can't set the error
        }
    }

    // MARK: - Value Creation

    /// Creates a Perl integer value.
    public func createInt(_ value: Int32) throws -> PerlValue {
        try checkDisposed()
        let ptr = try exports.newInt(value)
        guard ptr != 0 else {
            throw PerlKitError.operationFailed("Failed to create integer")
        }
        return PerlValue(ptr: ptr, exports: exports, perl: self)
    }

    /// Creates a Perl integer value from a Swift Int.
    public func createInt(_ value: Int) throws -> PerlValue {
        try createInt(Int32(clamping: value))
    }

    /// Creates a Perl unsigned integer value.
    public func createUInt(_ value: UInt32) throws -> PerlValue {
        try checkDisposed()
        let ptr = try exports.newUInt(value)
        guard ptr != 0 else {
            throw PerlKitError.operationFailed("Failed to create unsigned integer")
        }
        return PerlValue(ptr: ptr, exports: exports, perl: self)
    }

    /// Creates a Perl double value.
    public func createDouble(_ value: Double) throws -> PerlValue {
        try checkDisposed()
        let ptr = try exports.newDouble(value)
        guard ptr != 0 else {
            throw PerlKitError.operationFailed("Failed to create double")
        }
        return PerlValue(ptr: ptr, exports: exports, perl: self)
    }

    /// Creates a Perl string value.
    public func createString(_ value: String) throws -> PerlValue {
        try checkDisposed()
        let bytes = Array(value.utf8)
        let strPtr = try exports.writeBytes(bytes)
        defer { try? exports.free(strPtr) }
        let valuePtr = try exports.newString(strPtr, Int32(bytes.count))
        guard valuePtr != 0 else {
            throw PerlKitError.operationFailed("Failed to create string")
        }
        return PerlValue(ptr: valuePtr, exports: exports, perl: self)
    }

    /// Creates a Perl boolean value.
    public func createBool(_ value: Bool) throws -> PerlValue {
        try checkDisposed()
        let ptr = try exports.newBool(value ? 1 : 0)
        guard ptr != 0 else {
            throw PerlKitError.operationFailed("Failed to create boolean")
        }
        return PerlValue(ptr: ptr, exports: exports, perl: self)
    }

    /// Creates a Perl undefined value.
    public func createUndef() throws -> PerlValue {
        try checkDisposed()
        let ptr = try exports.newUndef()
        guard ptr != 0 else {
            throw PerlKitError.operationFailed("Failed to create undef")
        }
        return PerlValue(ptr: ptr, exports: exports, perl: self)
    }

    /// Creates a Perl array.
    public func createArray() throws -> PerlArray {
        try checkDisposed()
        let ptr = try exports.newArray()
        guard ptr != 0 else {
            throw PerlKitError.operationFailed("Failed to create array")
        }
        return PerlArray(ptr: ptr, exports: exports, perl: self)
    }

    /// Creates a Perl array from a Swift array.
    ///
    /// - Parameter values: The values to populate the array with.
    /// - Returns: A new PerlArray containing the values.
    public func createArray<T: PerlConvertible>(from values: [T]) throws -> PerlArray {
        let array = try createArray()
        for value in values {
            try array.push(value)
        }
        return array
    }

    /// Creates a Perl hash.
    public func createHash() throws -> PerlHash {
        try checkDisposed()
        let ptr = try exports.newHash()
        guard ptr != 0 else {
            throw PerlKitError.operationFailed("Failed to create hash")
        }
        return PerlHash(ptr: ptr, exports: exports, perl: self)
    }

    /// Creates a Perl hash from a Swift dictionary.
    ///
    /// - Parameter values: The key-value pairs to populate the hash with.
    /// - Returns: A new PerlHash containing the values.
    public func createHash<T: PerlConvertible>(from values: [String: T]) throws -> PerlHash {
        let hash = try createHash()
        for (key, value) in values {
            try hash.set(key: key, value: value)
        }
        return hash
    }

    /// Converts a Swift value to a Perl value.
    public func toPerlValue<T: PerlConvertible>(_ value: T) throws -> PerlValue {
        try value.toPerlValue(using: self)
    }

    // MARK: - Variables

    /// Gets a global scalar variable.
    ///
    /// - Parameter name: The variable name (without the $ sigil).
    /// - Returns: The value of the variable, or nil if not found.
    public func getVariable(_ name: String) throws -> PerlValue? {
        try checkDisposed()
        let namePtr = try exports.writeCString(name)
        defer { try? exports.free(namePtr) }
        let valuePtr = try exports.getVar(namePtr)
        guard valuePtr != 0 else { return nil }
        return PerlValue(ptr: valuePtr, exports: exports, perl: self)
    }

    /// Gets a global array variable.
    ///
    /// - Parameter name: The variable name (without the @ sigil).
    /// - Returns: The array, or nil if not found.
    public func getArrayVariable(_ name: String) throws -> PerlArray? {
        try checkDisposed()
        let namePtr = try exports.writeCString(name)
        defer { try? exports.free(namePtr) }
        let arrayPtr = try exports.getArrayVar(namePtr)
        guard arrayPtr != 0 else { return nil }
        return PerlArray(ptr: arrayPtr, exports: exports, perl: self)
    }

    /// Gets a global hash variable.
    ///
    /// - Parameter name: The variable name (without the % sigil).
    /// - Returns: The hash, or nil if not found.
    public func getHashVariable(_ name: String) throws -> PerlHash? {
        try checkDisposed()
        let namePtr = try exports.writeCString(name)
        defer { try? exports.free(namePtr) }
        let hashPtr = try exports.getHashVar(namePtr)
        guard hashPtr != 0 else { return nil }
        return PerlHash(ptr: hashPtr, exports: exports, perl: self)
    }

    /// Sets a global scalar variable.
    ///
    /// - Parameters:
    ///   - name: The variable name (without the $ sigil).
    ///   - value: The value to set.
    public func setVariable<T: PerlConvertible>(_ name: String, value: T) throws {
        try checkDisposed()
        let perlValue = try toPerlValue(value)
        let namePtr = try exports.writeCString(name)
        defer { try? exports.free(namePtr) }
        let success = try exports.setVar(namePtr, try perlValue.pointer)
        if !(value is PerlValue) {
            try perlValue.dispose()
        }
        guard success != 0 else {
            throw PerlKitError.operationFailed("Failed to set variable '\(name)'")
        }
    }

    /// Sets a global scalar variable with a dictionary value.
    ///
    /// - Parameters:
    ///   - name: The variable name (without the $ sigil).
    ///   - value: The dictionary to set as a hash reference.
    public func setVariable(_ name: String, value: [String: any PerlConvertible]) throws {
        try checkDisposed()

        let hash = try createHash()
        for (key, val) in value {
            let perlValue = try val.toPerlValue(using: self)
            try hash.set(key: key, value: perlValue)
            try perlValue.dispose()
        }

        let hashValue = try hash.ref()
        let namePtr = try exports.writeCString(name)
        let success = try exports.setVar(namePtr, try hashValue.pointer)
        try exports.free(namePtr)

        try hash.dispose()
        try hashValue.dispose()

        guard success != 0 else {
            throw PerlKitError.operationFailed("Failed to set variable '\(name)'")
        }
    }

    // MARK: - Function Registration

    /// Registers a Swift function that can be called from Perl.
    ///
    /// - Parameters:
    ///   - name: The name of the function in Perl.
    ///   - function: The Swift function to call.
    public func registerFunction(_ name: String, function: @escaping PerlHostFunction) throws {
        try checkDisposed()
        let functionID = nextFunctionID
        nextFunctionID += 1

        hostFunctions[functionID] = function

        let namePtr = try exports.writeCString(name)
        defer { try? exports.free(namePtr) }
        try exports.registerFunction(functionID, namePtr)
    }

    /// Registers a Swift method that can be called from Perl.
    ///
    /// - Parameters:
    ///   - package: The Perl package name.
    ///   - method: The method name.
    ///   - function: The Swift function to call.
    public func registerMethod(
        package: String,
        method: String,
        function: @escaping PerlHostFunction
    ) throws {
        try checkDisposed()
        let functionID = nextFunctionID
        nextFunctionID += 1

        hostFunctions[functionID] = function

        let packagePtr = try exports.writeCString(package)
        let methodPtr = try exports.writeCString(method)
        defer {
            try? exports.free(packagePtr)
            try? exports.free(methodPtr)
        }
        try exports.registerMethod(functionID, packagePtr, methodPtr)
    }

    // MARK: - Function Calling

    /// Calls a Perl subroutine.
    ///
    /// - Parameters:
    ///   - name: The name of the subroutine to call.
    ///   - arguments: Arguments to pass to the subroutine.
    ///   - context: The calling context.
    /// - Returns: An array of return values.
    public func call(
        _ name: String,
        arguments: [PerlValue] = [],
        context: PerlContext = .scalar
    ) throws -> [PerlValue] {
        try checkDisposed()

        let namePtr = try exports.writeCString(name)
        defer { try? exports.free(namePtr) }

        var argvPtr: Int32 = 0
        if !arguments.isEmpty {
            argvPtr = try exports.malloc(Int32(arguments.count * 4))
            for (i, arg) in arguments.enumerated() {
                let ptr = try arg.pointer
                exports.writeInt32(at: argvPtr + Int32(i * 4), value: ptr)
            }
        }
        defer {
            if argvPtr != 0 {
                try? exports.free(argvPtr)
            }
        }

        let resultPtr = try exports.call(namePtr, context.rawValue, Int32(arguments.count), argvPtr)

        guard resultPtr != 0 else { return [] }

        defer {
            let valuesArrayPtr = exports.readUInt32(at: resultPtr + 4)
            if valuesArrayPtr != 0 {
                try? exports.free(Int32(valuesArrayPtr))
            }
            try? exports.free(resultPtr)
        }

        let count = Int(exports.readInt32(at: resultPtr))
        var results: [PerlValue] = []

        for i in 0..<count {
            let valuePtr = try exports.resultGet(resultPtr, Int32(i))
            if valuePtr != 0 {
                results.append(PerlValue(ptr: valuePtr, exports: exports, perl: self))
            }
        }

        return results
    }

    /// Calls a Perl subroutine with PerlConvertible arguments.
    ///
    /// - Parameters:
    ///   - name: The name of the subroutine to call.
    ///   - arguments: Arguments to pass to the subroutine.
    ///   - context: The calling context.
    /// - Returns: An array of return values.
    public func call<T: PerlConvertible>(
        _ name: String,
        arguments: [T],
        context: PerlContext = .scalar
    ) throws -> [PerlValue] {
        let perlArgs = try arguments.map { try toPerlValue($0) }
        defer {
            for arg in perlArgs {
                try? arg.dispose()
            }
        }
        return try call(name, arguments: perlArgs, context: context)
    }

    // MARK: - Evaluation

    /// Evaluates a string of Perl code.
    ///
    /// - Parameters:
    ///   - code: The Perl code to evaluate.
    ///   - arguments: Arguments to make available in @ARGV.
    /// - Returns: A result indicating success or failure.
    @discardableResult
    public func eval(_ code: String, arguments: [String] = []) throws -> PerlResult {
        try checkDisposed()

        let codePtr = try exports.writeCString(code)
        defer { try? exports.free(codePtr) }

        var argv: Int32 = 0
        var buffers: [Int32] = []

        if !arguments.isEmpty {
            argv = try exports.malloc(Int32(arguments.count * 4))
            for (i, arg) in arguments.enumerated() {
                let strPtr = try exports.writeCString(arg)
                buffers.append(strPtr)
                exports.writeInt32(at: argv + Int32(i * 4), value: strPtr)
            }
        }

        defer {
            for buffer in buffers {
                try? exports.free(buffer)
            }
            if argv != 0 {
                try? exports.free(argv)
            }
        }

        let exitCode = try exports.eval(
            codePtr: codePtr,
            context: PerlContext.scalar.rawValue,
            argc: Int32(arguments.count),
            argv: argv
        )

        if exitCode != 0 {
            let error = try? lastError()
            return PerlResult(success: false, error: error, exitCode: exitCode)
        }

        return PerlResult(success: true, error: nil, exitCode: 0)
    }

    /// Runs a Perl script file.
    ///
    /// - Parameters:
    ///   - path: The path to the script file.
    ///   - arguments: Arguments to make available in @ARGV.
    /// - Returns: A result indicating success or failure.
    @discardableResult
    public func runFile(_ path: String, arguments: [String] = []) throws -> PerlResult {
        try checkDisposed()

        let pathPtr = try exports.writeCString(path)
        defer { try? exports.free(pathPtr) }

        var argv: Int32 = 0
        var buffers: [Int32] = []

        if !arguments.isEmpty {
            argv = try exports.malloc(Int32(arguments.count * 4))
            for (i, arg) in arguments.enumerated() {
                let strPtr = try exports.writeCString(arg)
                buffers.append(strPtr)
                exports.writeInt32(at: argv + Int32(i * 4), value: strPtr)
            }
        }

        defer {
            for buffer in buffers {
                try? exports.free(buffer)
            }
            if argv != 0 {
                try? exports.free(argv)
            }
        }

        let exitCode = try exports.runFile(
            pathPtr: pathPtr,
            argc: Int32(arguments.count),
            argv: argv
        )

        if exitCode != 0 {
            let error = try? lastError()
            return PerlResult(success: false, error: error, exitCode: exitCode)
        }

        return PerlResult(success: true, error: nil, exitCode: 0)
    }

    // MARK: - State Management

    /// Resets the interpreter to a clean state.
    public func reset() throws {
        try checkDisposed()
        let result = try exports.reset()
        guard result == 0 else {
            let error = try? lastError()
            throw PerlKitError.initializationFailed(exitCode: result, perlError: error)
        }
    }

    /// Flushes STDOUT and STDERR buffers.
    public func flush() throws {
        try checkDisposed()
        let result = try exports.flush()
        guard result == 0 else {
            throw PerlKitError.operationFailed("Failed to flush output buffers")
        }
    }

    /// Gets the last error message from Perl ($@).
    public func lastError() throws -> String {
        try checkDisposed()
        let errorPtr = try exports.lastError()
        return exports.readCString(at: errorPtr)
    }

    /// Clears the error state ($@).
    public func clearError() throws {
        try checkDisposed()
        try exports.clearError()
    }

    /// Gets the last host error message.
    public func getHostError() throws -> String {
        try checkDisposed()
        let errorPtr = try exports.getHostError()
        return exports.readCString(at: errorPtr)
    }

    /// Clears the host error state.
    public func clearHostError() throws {
        try checkDisposed()
        try exports.clearHostError()
    }

    /// Checks if the interpreter is initialized.
    public var isInitialized: Bool {
        get throws {
            try checkDisposed()
            return try exports.isInitialized() != 0
        }
    }

    /// Checks if the interpreter is ready to evaluate code.
    public var canEvaluate: Bool {
        get throws {
            try checkDisposed()
            return try exports.canEvaluate() != 0
        }
    }

    // MARK: - Memory Management

    /// Frees the Perl interpreter's memory.
    public func dispose() throws {
        guard !isDisposed else { return }
        try exports.freeInterpreter()
        stdoutPipe?.fileHandleForWriting.closeFile()
        stderrPipe?.fileHandleForWriting.closeFile()
        isDisposed = true
        hostFunctions.removeAll()
    }

    /// Shuts down the Perl system completely.
    ///
    /// This should only be called once at program exit.
    public func shutdown() throws {
        guard !isDisposed else { return }
        try exports.shutdown()
        stdoutPipe?.fileHandleForWriting.closeFile()
        stderrPipe?.fileHandleForWriting.closeFile()
        isDisposed = true
        hostFunctions.removeAll()
    }
    
    private func checkDisposed() throws {
        guard !isDisposed else {
            throw PerlKitError.disposed("PerlKit")
        }
    }
}

// MARK: - Module Loading

private func loadZeroPerlWasm() throws -> [UInt8] {
    guard let wasmURL = Bundle.module.url(forResource: "zeroperl", withExtension: "wasm") else {
        throw PerlKitError.fileNotFound("zeroperl.wasm")
    }
    let data = try Data(contentsOf: wasmURL)
    return Array(data)
}
