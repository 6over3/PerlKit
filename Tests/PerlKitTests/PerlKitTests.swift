import Foundation
import Testing

@testable import PerlKit

// MARK: - Basic Operations

@Suite(.serialized)
class BasicOperationsTests {
    let perl: PerlKit

    init() throws {
        perl = try PerlKit.create()
    }

    deinit {
        try? perl.dispose()
    }

    @Test func createAndDisposeZeroPerlInstance() throws {
        #expect(try perl.isInitialized == true)
        #expect(try perl.canEvaluate == true)
    }

    @Test func evaluateBasicPerlCode() throws {
        let result = try perl.eval("$x = 42")
        #expect(result.success == true)
        #expect(result.exitCode == 0)
    }

    @Test func handleErrorsGracefully() throws {
        let result = try perl.eval("die \"test error\"")
        #expect(result.success == false)
        #expect(result.error?.contains("test error") == true)
    }

    @Test func getAndClearLastError() async throws {
        _ = try perl.eval("die \"custom error\"")

        let error = try perl.lastError()
        #expect(error.contains("custom error"))

        try perl.clearError()
        let clearedError = try perl.lastError()
        #expect(clearedError.isEmpty)
    }

    @Test func resetToCleanState() throws {
        try perl.setVariable("x", value: 42)
        var value = try perl.getVariable("x")
        #expect(try value?.toInt() == 42)
        try value?.dispose()

        try perl.reset()

        value = try perl.getVariable("x")
        #expect(value == nil)
    }

    @Test func flushOutputBuffers() async throws {
        _ = try perl.eval("print \"test\"")

        let outputAfterFlush = try perl.readStdout()
        #expect(outputAfterFlush == "test")
    }
}

@Suite(.serialized)
class ShutdownTests {
    @Test func shutdownCompletely() throws {
        let perl = try PerlKit.create()
        _ = try perl.eval("$x = 42")
        try perl.shutdown()

        do {
            _ = try perl.eval("$y = 10")
            Issue.record("Should have thrown disposed error")
        } catch let error as PerlKitError {
            #expect(error.description.contains("disposed"))
        }
    }

    @Test func throwErrorWhenUsingDisposedInstance() throws {
        let perl = try PerlKit.create()
        try perl.dispose()

        do {
            _ = try perl.eval("$x = 1")
            Issue.record("Should have thrown disposed error")
        } catch let error as PerlKitError {
            #expect(error.description.contains("disposed"))
        }
    }
}

// MARK: - Value Creation

@Suite(.serialized)
class ValueCreationTests {
    let perl: PerlKit

    init() throws {
        perl = try PerlKit.create()
    }

    deinit {
        try? perl.dispose()
    }

    @Test func createIntegerValues() throws {
        let val = try perl.createInt(42)

        #expect(try val.type() == .int)
        #expect(try val.toInt() == 42)

        try val.dispose()
    }

    @Test func createUnsignedIntegerValues() throws {
        let val = try perl.createUInt(100)

        #expect(try val.toInt() == 100)

        try val.dispose()
    }

    @Test func createDoubleValues() throws {
        let val = try perl.createDouble(Double.pi)

        #expect(try val.type() == .double)
        let result = try val.toDouble()
        #expect(abs(result - Double.pi) < 0.0001)

        try val.dispose()
    }

    @Test func createStringValues() throws {
        let val = try perl.createString("hello world")

        #expect(try val.type() == .string)
        #expect(try val.toString() == "hello world")

        try val.dispose()
    }

    @Test func createBooleanValues() throws {
        let valTrue = try perl.createBool(true)
        let valFalse = try perl.createBool(false)

        #expect(try valTrue.toBool() == true)
        #expect(try valFalse.toBool() == false)

        try valTrue.dispose()
        try valFalse.dispose()
    }

    @Test func createUndefValues() throws {
        let val = try perl.createUndef()

        #expect(try val.isUndef == true)

        try val.dispose()
    }

    @Test func convertSwiftPrimitivesToPerl() throws {
        let num = try perl.toPerlValue(42)
        #expect(try num.toInt() == 42)

        let str = try perl.toPerlValue("test")
        #expect(try str.toString() == "test")

        let bool = try perl.toPerlValue(true)
        #expect(try bool.toBool() == true)

        let optional: Int? = nil
        let undef = try perl.toPerlValue(optional)
        #expect(try undef.isUndef == true)

        try num.dispose()
        try str.dispose()
        try bool.dispose()
        try undef.dispose()
    }

    @Test func convertSwiftArraysToPerl() throws {
        let arrVal = try perl.toPerlValue([1, 2, 3])
        #expect(try arrVal.isRef == true)

        try arrVal.dispose()
    }

    @Test func convertSwiftDictionariesToPerl() throws {
        let objVal = try perl.toPerlValue(["a": 1, "b": 2])
        #expect(try objVal.isRef == true)

        try objVal.dispose()
    }

    @Test func convertNestedSwiftStructuresToPerl() throws {
        let hash = try perl.createHash()
        try hash.set(key: "name", value: "Alice")

        let scores = try perl.createArray()
        try scores.push(95)
        try scores.push(87)
        try scores.push(92)
        let scoresVal = try scores.ref()
        try hash.set(key: "scores", value: scoresVal)
        try scores.dispose()
        try scoresVal.dispose()

        try hash.set(key: "active", value: true)

        let hashVal = try hash.ref()
        #expect(try hashVal.isRef == true)

        try hashVal.dispose()
        try hash.dispose()
    }
}

// MARK: - PerlValue Operations

@Suite(.serialized)
class PerlValueOperationsTests {
    let perl: PerlKit

    init() throws {
        perl = try PerlKit.create()
    }

    deinit {
        try? perl.dispose()
    }

    @Test func convertValuesToDifferentTypes() throws {
        let val = try perl.createInt(42)

        #expect(try val.toInt() == 42)
        #expect(try val.toDouble() == 42.0)
        #expect(try val.toString() == "42")
        #expect(try val.toBool() == true)

        try val.dispose()
    }

    @Test func checkValueTypes() throws {
        let intVal = try perl.createInt(42)
        #expect(try intVal.type() == .int)

        let strVal = try perl.createString("hello")
        #expect(try strVal.type() == .string)

        let undefVal = try perl.createUndef()
        #expect(try undefVal.isUndef == true)

        try intVal.dispose()
        try strVal.dispose()
        try undefVal.dispose()
    }

    @Test func createAndDereferenceReferences() throws {
        let val = try perl.createInt(42)

        let ref = try val.createRef()
        #expect(try ref.isRef == true)

        let deref = try ref.deref()
        #expect(try deref.toInt() == 42)

        try val.dispose()
        try ref.dispose()
        try deref.dispose()
    }

    @Test func handleReferenceCounting() throws {
        let val = try perl.createInt(42)

        try val.incref()
        try val.decref()

        #expect(try val.toInt() == 42)

        try val.dispose()
    }

    @Test func throwErrorWhenUsingDisposedPerlValue() throws {
        let val = try perl.createInt(42)
        try val.dispose()

        do {
            _ = try val.toInt()
            Issue.record("Should have thrown disposed error")
        } catch let error as PerlKitError {
            #expect(error.description.contains("disposed"))
        }
    }
}

// MARK: - Arrays

@Suite(.serialized)
class ArrayTests {
    let perl: PerlKit

    init() throws {
        perl = try PerlKit.create()
    }

    deinit {
        try? perl.dispose()
    }

    @Test func createEmptyArrays() throws {
        let arr = try perl.createArray()

        #expect(try arr.count == 0)

        try arr.dispose()
    }

    @Test func pushAndPopValues() throws {
        let arr = try perl.createArray()

        try arr.push(42)
        try arr.push("hello")
        try arr.push(true)

        #expect(try arr.count == 3)

        let val = try arr.pop()
        #expect(try val?.toBool() == true)

        #expect(try arr.count == 2)

        try val?.dispose()
        try arr.dispose()
    }

    @Test func getAndSetValuesByIndex() throws {
        let arr = try perl.createArray()

        try arr.push(1)
        try arr.push(2)
        try arr.push(3)

        let val = try arr.get(1)
        #expect(try val?.toInt() == 2)

        try arr.set(1, value: 99)
        let newVal = try arr.get(1)
        #expect(try newVal?.toInt() == 99)

        try val?.dispose()
        try newVal?.dispose()
        try arr.dispose()
    }

    @Test func clearArrays() throws {
        let arr = try perl.createArray()

        try arr.push(1)
        try arr.push(2)
        try arr.push(3)

        #expect(try arr.count == 3)

        try arr.removeAll()
        #expect(try arr.count == 0)

        try arr.dispose()
    }

    @Test func iterateOverArrayValues() throws {
        let arr = try perl.createArray()

        try arr.push(1)
        try arr.push(2)
        try arr.push(3)

        var values: [Int32] = []
        let count = try arr.count
        for i in 0..<count {
            if let val = try arr.get(i) {
                values.append(try val.toInt())
                try val.dispose()
            }
        }

        #expect(values == [1, 2, 3])

        try arr.dispose()
    }

    @Test func convertArrayToPerlValue() throws {
        let arr = try perl.createArray()

        try arr.push(1)
        try arr.push(2)

        let val = try arr.ref()
        #expect(try val.isRef == true)

        try val.dispose()
        try arr.dispose()
    }

    @Test func throwErrorWhenUsingDisposedPerlArray() throws {
        let arr = try perl.createArray()
        try arr.dispose()

        do {
            _ = try arr.count
            Issue.record("Should have thrown disposed error")
        } catch let error as PerlKitError {
            #expect(error.description.contains("disposed"))
        }
    }
}

// MARK: - Hashes

@Suite(.serialized)
class HashTests {
    let perl: PerlKit

    init() throws {
        perl = try PerlKit.create()
    }

    deinit {
        try? perl.dispose()
    }

    @Test func createEmptyHashes() throws {
        let hash = try perl.createHash()

        #expect(try hash.contains(key: "key") == false)

        try hash.dispose()
    }

    @Test func setAndGetValues() throws {
        let hash = try perl.createHash()

        try hash.set(key: "name", value: "Alice")
        try hash.set(key: "age", value: 30)

        let name = try hash.get(key: "name")
        #expect(try name?.toString() == "Alice")

        let age = try hash.get(key: "age")
        #expect(try age?.toInt() == 30)

        try name?.dispose()
        try age?.dispose()
        try hash.dispose()
    }

    @Test func checkIfKeysExist() throws {
        let hash = try perl.createHash()

        try hash.set(key: "key1", value: "value1")

        #expect(try hash.contains(key: "key1") == true)
        #expect(try hash.contains(key: "key2") == false)

        try hash.dispose()
    }

    @Test func deleteKeys() throws {
        let hash = try perl.createHash()

        try hash.set(key: "key", value: "value")
        #expect(try hash.contains(key: "key") == true)

        let deleted = try hash.remove(key: "key")
        #expect(deleted == true)
        #expect(try hash.contains(key: "key") == false)

        let notDeleted = try hash.remove(key: "nonexistent")
        #expect(notDeleted == false)

        try hash.dispose()
    }

    @Test func clearHashes() throws {
        let hash = try perl.createHash()

        try hash.set(key: "key1", value: "value1")
        try hash.set(key: "key2", value: "value2")

        try hash.removeAll()

        #expect(try hash.contains(key: "key1") == false)
        #expect(try hash.contains(key: "key2") == false)

        try hash.dispose()
    }

    @Test func iterateOverEntries() throws {
        let hash = try perl.createHash()

        try hash.set(key: "a", value: 1)
        try hash.set(key: "b", value: 2)
        try hash.set(key: "c", value: 3)

        var entries: [String: Int32] = [:]
        for (key, val) in hash {
            entries[key] = try val.toInt()
            try val.dispose()
        }

        #expect(entries == ["a": 1, "b": 2, "c": 3])

        try hash.dispose()
    }

    @Test func convertHashToPerlValue() throws {
        let hash = try perl.createHash()

        try hash.set(key: "key", value: "value")

        let val = try hash.ref()
        #expect(try val.isRef == true)

        try val.dispose()
        try hash.dispose()
    }

    @Test func throwErrorWhenUsingDisposedPerlHash() throws {
        let hash = try perl.createHash()
        try hash.dispose()

        do {
            _ = try hash.contains(key: "key")
            Issue.record("Should have thrown disposed error")
        } catch let error as PerlKitError {
            #expect(error.description.contains("disposed"))
        }
    }
}

// MARK: - Variables

@Suite(.serialized)
class VariableTests {
    let perl: PerlKit

    init() throws {
        perl = try PerlKit.create()
    }

    deinit {
        try? perl.dispose()
    }

    @Test func setAndGetScalarVariablesWithPrimitives() throws {
        try perl.setVariable("name", value: "Alice")
        try perl.setVariable("age", value: 30)
        try perl.setVariable("active", value: true)

        let name = try perl.getVariable("name")
        #expect(try name?.toString() == "Alice")

        let age = try perl.getVariable("age")
        #expect(try age?.toInt() == 30)

        let active = try perl.getVariable("active")
        #expect(try active?.toBool() == true)

        try name?.dispose()
        try age?.dispose()
        try active?.dispose()
    }

    @Test func setVariablesWithPerlValue() throws {
        let val = try perl.createString("test")
        try perl.setVariable("myvar", value: val)

        let retrieved = try perl.getVariable("myvar")
        #expect(try retrieved?.toString() == "test")

        try val.dispose()
        try retrieved?.dispose()
    }

    @Test func setVariablesWithArrays() throws {
        try perl.setVariable("numbers", value: [1, 2, 3, 4, 5])

        let val = try perl.getVariable("numbers")
        #expect(try val?.isRef == true)

        try val?.dispose()
    }

    @Test func setVariablesWithDictionaries() throws {
        let user: [String: PerlConvertible] = ["name": "Alice", "age": 30]
        try perl.setVariable("user", value: user)

        let val = try perl.getVariable("user")
        #expect(try val?.isRef == true)

        try val?.dispose()
    }

    @Test func returnNilForNonExistentVariables() throws {
        let value = try perl.getVariable("nonexistent")
        #expect(value == nil)
    }

    @Test func getAndSetArrayVariables() throws {
        _ = try perl.eval("@myarray = (1, 2, 3)")

        let arr = try perl.getArrayVariable("myarray")
        #expect(try arr?.count == 3)

        try arr?.dispose()
    }

    @Test func getAndSetHashVariables() throws {
        _ = try perl.eval("%myhash = (a => 1, b => 2)")

        let hash = try perl.getHashVariable("myhash")
        #expect(try hash?.contains(key: "a") == true)
        #expect(try hash?.contains(key: "b") == true)

        try hash?.dispose()
    }

    @Test func overwriteExistingVariables() throws {
        try perl.setVariable("var", value: "first")
        var val = try perl.getVariable("var")
        #expect(try val?.toString() == "first")
        try val?.dispose()

        try perl.setVariable("var", value: "second")
        val = try perl.getVariable("var")
        #expect(try val?.toString() == "second")

        try val?.dispose()
    }
}

// MARK: - Host Functions

@Suite(.serialized)
class HostFunctionTests {
    let perl: PerlKit

    init() throws {
        perl = try PerlKit.create()
    }

    deinit {
        try? perl.dispose()
    }

    @Test func registerAndCallHostFunctions() async throws {
        try perl.registerFunction("double") { [perl] args in
            guard let arg = args.first else { return nil }
            let num = try arg.toInt()
            return try perl.createInt(num * 2)
        }

        _ = try perl.eval("print double(21)")

        let output = try perl.readStdout()
        #expect(output == "42")
    }

    @Test func registerHostMethods() throws {
        try perl.registerMethod(package: "Math", method: "square") { [perl] args in
            guard let arg = args.first else { return nil }
            let num = try arg.toInt()
            return try perl.createInt(num * num)
        }

        _ = try perl.eval("$result = Math::square(7)")
        let result = try perl.getVariable("result")
        #expect(try result?.toInt() == 49)

        try result?.dispose()
    }

    @Test func handleHostFunctionsWithMultipleArguments() throws {
        try perl.registerFunction("add") { [perl] args in
            guard args.count >= 2 else { return nil }
            let x = try args[0].toInt()
            let y = try args[1].toInt()
            return try perl.createInt(x + y)
        }

        _ = try perl.eval("$sum = add(10, 32)")
        let sum = try perl.getVariable("sum")
        #expect(try sum?.toInt() == 42)

        try sum?.dispose()
    }

    @Test func handleHostFunctionsReturningDifferentTypes() async throws {
        try perl.registerFunction("get_string") { [perl] _ in
            return try perl.createString("hello")
        }

        try perl.registerFunction("get_array") { [perl] _ in
            let arr = try perl.createArray()
            try arr.push(1)
            try arr.push(2)
            let val = try arr.ref()
            try arr.dispose()
            return val
        }

        // Test string function
        _ = try perl.eval("$str = get_string()")
        let str = try perl.getVariable("str")
        #expect(try str?.toString() == "hello")
        try str?.dispose()

        // Test array function
        _ = try perl.eval("$arr = get_array()")
        let arrRef = try perl.getVariable("arr")
        #expect(arrRef != nil)
        let arrayType = try arrRef?.type()
        #expect(arrayType == .array)

        let arr = try arrRef?.toArray(using: perl)
        #expect(try arr?.count == 2)
        let firstElem = try arr?.get(0)
        #expect(try firstElem?.toInt() == 1)

        try arrRef?.dispose()
        try arr?.dispose()

        _ = try perl.eval("$len = scalar(@$arr)")
        let len = try perl.getVariable("len")
        #expect(try len?.toInt() == 2)
        try len?.dispose()
    }

    @Test func handleVoidHostFunctions() throws {
        var called = false

        try perl.registerFunction("set_flag") { _ in
            called = true
            return nil
        }

        _ = try perl.eval("set_flag()")
        #expect(called == true)
    }

    @Test func handleHostFunctionErrors() async throws {
        try perl.registerFunction("divide") { [perl] args in
            guard args.count >= 2 else { return nil }
            let x = try args[0].toInt()
            let y = try args[1].toInt()
            if y == 0 {
                throw PerlKitError.operationFailed("Division by zero")
            }
            return try perl.createInt(x / y)
        }

        let result = try perl.eval(
            """
                eval { $result = divide(10, 0) };
                $error = $@;
            """)

        print(result)

        #expect(result.success == true)

        let error = try perl.getVariable("error")

        #expect(try error?.toString().contains("Division by zero") == true)

        try error?.dispose()
    }
}

// MARK: - Calling Perl from Swift

@Suite(.serialized)
class CallPerlTests {
    let perl: PerlKit

    init() throws {
        perl = try PerlKit.create()
    }

    deinit {
        try? perl.dispose()
    }

    @Test func callPerlSubroutinesInScalarContext() throws {
        _ = try perl.eval("sub greet { my ($name) = @_; return \"Hello, $name!\"; }")

        let arg = try perl.createString("Alice")
        let results = try perl.call("greet", arguments: [arg], context: .scalar)

        #expect(results.count == 1)
        #expect(try results[0].toString() == "Hello, Alice!")

        try arg.dispose()
        try results[0].dispose()
    }

    @Test func callPerlSubroutinesWithDefaultScalarContext() throws {
        _ = try perl.eval("sub greet { my ($name) = @_; return \"Hello, $name!\"; }")

        let arg = try perl.createString("Alice")
        let results = try perl.call("greet", arguments: [arg])

        #expect(results.count == 1)
        #expect(try results[0].toString() == "Hello, Alice!")

        try arg.dispose()
        try results[0].dispose()
    }

    @Test func callPerlSubroutinesWithMultipleArguments() throws {
        _ = try perl.eval("sub add { my ($a, $b) = @_; return $a + $b; }")

        let arg1 = try perl.createInt(10)
        let arg2 = try perl.createInt(32)
        let results = try perl.call("add", arguments: [arg1, arg2], context: .scalar)

        #expect(results.count == 1)
        #expect(try results[0].toInt() == 42)

        try arg1.dispose()
        try arg2.dispose()
        try results[0].dispose()
    }

    @Test func callPerlSubroutinesInListContext() throws {
        _ = try perl.eval("sub get_values { return (1, 2, 3); }")

        let results = try perl.call("get_values", arguments: [], context: .list)

        #expect(results.count == 3)
        #expect(try results[0].toInt() == 1)
        #expect(try results[1].toInt() == 2)
        #expect(try results[2].toInt() == 3)

        for result in results {
            try result.dispose()
        }
    }

    @Test func callPerlSubroutinesInVoidContext() throws {
        _ = try perl.eval("sub set_global { $::global = 42; }")

        let results = try perl.call("set_global", arguments: [], context: .void)

        #expect(results.isEmpty)

        let global = try perl.getVariable("global")
        #expect(try global?.toInt() == 42)

        try global?.dispose()
    }

    @Test func callPerlSubroutinesWithoutArguments() throws {
        _ = try perl.eval("sub get_pi { return 3.14159; }")

        let results = try perl.call("get_pi")

        #expect(results.count == 1)
        let result = try results[0].toDouble()
        print("Result: \(result)")
        #expect(abs(result - Double.pi) < 0.01)

        try results[0].dispose()
    }
}

// MARK: - File System

@Suite(.serialized)
class FileSystemTests {
    @Test func runScriptFiles() async throws {
        let scriptPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("perlkit-test-\(UUID().uuidString).pl").path
        try "print \"Hello from file!\"".write(toFile: scriptPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: scriptPath) }

        let perl = try PerlKit.create()
        defer { try? perl.dispose() }

        let result = try perl.runFile(scriptPath)

        #expect(result.success == true)

        let output = try perl.readStdout()
        #expect(output == "Hello from file!")
    }

    @Test func runScriptFilesWithArguments() async throws {
        let scriptPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("perlkit-test-\(UUID().uuidString).pl").path
        try "print \"Args: @ARGV\"".write(toFile: scriptPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: scriptPath) }

        let perl = try PerlKit.create()
        defer { try? perl.dispose() }

        _ = try perl.runFile(scriptPath, arguments: ["one", "two"])

        let output = try perl.readStdout()
        #expect(output == "Args: one two")
    }

    @Test func readDataFiles() async throws {
        let dataPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("perlkit-test-\(UUID().uuidString).txt").path
        try "Hello from file system!".write(toFile: dataPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: dataPath) }

        let perl = try PerlKit.create()
        defer { try? perl.dispose() }

        _ = try perl.eval(
            """
                open my $fh, '<', '\(dataPath)' or die $!;
                my $content = <$fh>;
                print $content;
                close $fh;
            """)

        let output = try perl.readStdout()
        #expect(output == "Hello from file system!")
    }

    @Test func handleFileNotFoundErrors() throws {
        let perl = try PerlKit.create()
        defer { try? perl.dispose() }

        let result = try perl.runFile("/tmp/perlkit-nonexistent-\(UUID().uuidString).pl")
        #expect(result.success == false)
        #expect(result.error?.contains("No such file or directory") == true)
    }
}

// MARK: - Output Handling

@Suite(.serialized)
class OutputHandlingTests {
    let perl: PerlKit

    init() throws {
        perl = try PerlKit.create()
    }

    deinit {
        try? perl.dispose()
    }

    @Test func captureStdout() async throws {
        _ = try perl.eval("print \"hello\"")

        let output = try perl.readStdout()
        #expect(output == "hello")
    }

    @Test func streamStdoutAsyncBytes() async throws {
        let perl = try PerlKit.create()
        defer { try? perl.dispose() }

        _ = try perl.eval("print \"hello\"")
        try perl.flush()

        guard let bytes = perl.stdout else {
            Issue.record("stdout stream is nil")
            return
        }

        var result = Data()
        for await byte in bytes {
            result.append(byte)
            if result.count >= 5 { break }
        }

        #expect(String(decoding: result, as: UTF8.self) == "hello")
    }

    @Test func captureStderrSeparately() async throws {
        _ = try perl.eval("print \"to stdout\"; warn \"to stderr\"")

        let stdout = try perl.readStdout()
        let stderr = try perl.readStderr()

        #expect(stdout == "to stdout")
        #expect(stderr.contains("to stderr"))
    }

    @Test func handleMultipleEvalCallsWithOutput() async throws {
        _ = try perl.eval("print \"first \"")
        _ = try perl.eval("print \"second\"")

        let output = try perl.readStdout()
        #expect(output == "first second")
    }

    @Test func clearOutput() async throws {
        _ = try perl.eval("print \"test\"")

        var output = try perl.readStdout()
        #expect(output == "test")

        output = try perl.readStdout()
        #expect(output.isEmpty)
    }
}

// MARK: - Environment

@Suite(.serialized)
class EnvironmentTests {
    @Test func passEnvironmentVariables() async throws {
        let options = PerlKitOptions(
            environment: ["MY_VAR": "test_value", "ANOTHER": "value2"]
        )
        let perl = try PerlKit.create(options: options)
        defer { try? perl.dispose() }

        _ = try perl.eval("print $ENV{MY_VAR} . \" \" . $ENV{ANOTHER}")

        let output = try perl.readStdout()
        #expect(output == "test_value value2")
    }

    @Test func handleMissingEnvironmentVariables() async throws {
        let options = PerlKitOptions(environment: [:])
        let perl = try PerlKit.create(options: options)
        defer { try? perl.dispose() }

        _ = try perl.eval("print defined($ENV{NONEXISTENT}) ? \"defined\" : \"undefined\"")

        let output = try perl.readStdout()
        #expect(output == "undefined")
    }
}

// MARK: - Complex Scenarios

@Suite(.serialized)
class ComplexScenarioTests {
    let perl: PerlKit

    init() throws {
        perl = try PerlKit.create()
    }

    deinit {
        try? perl.dispose()
    }

    @Test func maintainStateAcrossOperations() throws {
        _ = try perl.eval("$counter = 0")
        _ = try perl.eval("$counter++")
        _ = try perl.eval("$counter++")

        let counter = try perl.getVariable("counter")
        #expect(try counter?.toInt() == 2)

        try counter?.dispose()
    }

    @Test func handleErrorsWithoutLosingState() throws {
        try perl.setVariable("x", value: 42)

        _ = try perl.eval("die \"error\"")

        let x = try perl.getVariable("x")
        #expect(try x?.toInt() == 42)

        try x?.dispose()
    }

    @Test func handleLoopsAndComplexLogic() throws {
        _ = try perl.eval(
            """
                @array = (1, 2, 3, 4, 5);
                $sum = 0;
                foreach my $num (@array) {
                    $sum += $num;
                }
            """)

        let sum = try perl.getVariable("sum")
        #expect(try sum?.toInt() == 15)

        try sum?.dispose()
    }

    @Test func workWithSwiftDataInPerlCode() async throws {
        let hash = try perl.createHash()
        try hash.set(key: "name", value: "Alice")
        try hash.set(key: "age", value: 30)

        let scores = try perl.createArray()
        try scores.push(95)
        try scores.push(87)
        try scores.push(92)
        let scoresVal = try scores.ref()
        try hash.set(key: "scores", value: scoresVal)
        try scores.dispose()
        try scoresVal.dispose()

        let hashVal = try hash.ref()
        try perl.setVariable("user", value: hashVal)
        try hash.dispose()
        try hashVal.dispose()

        _ = try perl.eval("print \"$user->{name} is $user->{age} years old\"")

        let output = try perl.readStdout()
        #expect(output == "Alice is 30 years old")
    }

    @Test func handleLargeDataStructures() throws {
        let largeArray = Array(0..<1000)
        try perl.setVariable("numbers", value: largeArray)

        _ = try perl.eval(
            """
                $sum = 0;
                foreach my $num (@$numbers) {
                    $sum += $num;
                }
            """)

        let sum = try perl.getVariable("sum")
        #expect(try sum?.toInt() == 499500)  // Sum of 0 to 999

        try sum?.dispose()
    }
}

// MARK: - Edge Cases

@Suite(.serialized)
class EdgeCaseTests {
    let perl: PerlKit

    init() throws {
        perl = try PerlKit.create()
    }

    deinit {
        try? perl.dispose()
    }

    @Test func handleEmptyStrings() throws {
        let val = try perl.createString("")

        #expect(try val.toString() == "")

        try val.dispose()
    }

    @Test func handleSpecialCharactersInStrings() throws {
        let special = "Hello\nWorld\t!"
        let val = try perl.createString(special)

        #expect(try val.toString() == special)

        try val.dispose()
    }

    @Test func handleUnicodeStrings() throws {
        let unicode = "Hello 世界 🌍"
        let val = try perl.createString(unicode)

        #expect(try val.toString() == unicode)

        try val.dispose()
    }

    @Test func handleZeroValues() throws {
        let zero = try perl.createInt(0)

        #expect(try zero.toInt() == 0)
        #expect(try zero.toBool() == false)

        try zero.dispose()
    }

    @Test func handleNegativeNumbers() throws {
        let neg = try perl.createInt(-42)

        #expect(try neg.toInt() == -42)

        try neg.dispose()
    }

    @Test func handleVeryLargeNumbers() throws {
        let large = try perl.createDouble(Double(Int.max))

        let result = try large.toDouble()
        #expect(abs(result - Double(Int.max)) < 1.0)

        try large.dispose()
    }

    @Test func handleEmptyArrays() throws {
        let arr = try perl.createArray()

        #expect(try arr.count == 0)

        try arr.dispose()
    }

    @Test func handleEmptyHashes() throws {
        let hash = try perl.createHash()

        let entries = try hash.entries()
        #expect(entries.isEmpty == true)

        try hash.dispose()
    }
}

// MARK: - Error Handling

@Suite(.serialized)
class ErrorHandlingTests {
    let perl: PerlKit

    init() throws {
        perl = try PerlKit.create()
    }

    deinit {
        try? perl.dispose()
    }

    @Test func handleSyntaxErrors() throws {
        let result = try perl.eval("$x = ;")

        #expect(result.success == false)
        #expect(result.error != nil)
    }

    @Test func handleRuntimeErrors() throws {
        let result = try perl.eval("$x = 1 / 0")

        #expect(result.success == false)
        #expect(result.error?.contains("division by zero") == true)
    }

    @Test func recoverFromErrors() throws {
        _ = try perl.eval("die \"error\"")
        try perl.clearError()

        let result = try perl.eval("$x = 42")
        #expect(result.success == true)
    }
}

// MARK: - Creation Options

@Suite(.serialized)
class CreationOptionsTests {
    @Test func createWithCustomEnvironment() async throws {
        let options = PerlKitOptions(environment: ["CUSTOM": "value"])
        let perl = try PerlKit.create(options: options)
        defer { try? perl.dispose() }

        _ = try perl.eval("print $ENV{CUSTOM}")

        let output = try perl.readStdout()
        #expect(output == "value")
    }

    @Test func createWithHostFileSystem() async throws {
        let filePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("perlkit-test-\(UUID().uuidString).txt").path
        try "content".write(toFile: filePath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: filePath) }

        let perl = try PerlKit.create()
        defer { try? perl.dispose() }

        let d = try perl.eval(
            """
                open my $fh, '<', '\(filePath)';
                print <$fh>;
                close $fh;
            """)
        print("\(d)")

        let output = try perl.readStdout()
        #expect(output == "content")
    }

    @Test func createWithCaptureOptionsDisabled() async throws {
        let options = PerlKitOptions(captureStdout: false, captureStderr: false)
        let perl = try PerlKit.create(options: options)
        defer { try? perl.dispose() }

        _ = try perl.eval("print \"test\"")

        let output = try perl.readStdout()
        #expect(output.isEmpty)  // Nothing captured
    }
}

// MARK: - Swift-Specific Type Tests

@Suite(.serialized)
class SwiftTypeTests {
    let perl: PerlKit

    init() throws {
        perl = try PerlKit.create()
    }

    deinit {
        try? perl.dispose()
    }

    @Test func testInt64Conversion() throws {
        let val = try perl.toPerlValue(Int64(12345))
        #expect(try val.toInt64() == 12345)

        try val.dispose()
    }

    @Test func testFloatConversion() throws {
        let val = try perl.toPerlValue(Float(3.14))
        let result = try val.toDouble()
        #expect(abs(result - 3.14) < 0.01)

        try val.dispose()
    }

    @Test func testOptionalConversion() throws {
        let someValue: Int? = 42
        let someVal = try perl.toPerlValue(someValue)
        #expect(try someVal.toInt() == 42)

        let noneValue: Int? = nil
        let noneVal = try perl.toPerlValue(noneValue)
        #expect(try noneVal.isUndef == true)

        try someVal.dispose()
        try noneVal.dispose()
    }
}

// MARK: - Memory Management Tests

@Suite(.serialized)
class MemoryManagementTests {
    let perl: PerlKit

    init() throws {
        perl = try PerlKit.create()
    }

    deinit {
        try? perl.dispose()
    }

    @Test func testValueDisposalDoesNotAffectPerl() throws {
        let val1 = try perl.createInt(42)
        try val1.dispose()

        // Should still be able to create new values
        let val2 = try perl.createInt(99)
        #expect(try val2.toInt() == 99)

        try val2.dispose()
    }

    @Test func testArrayDisposalDoesNotAffectPerl() throws {
        let arr1 = try perl.createArray()
        try arr1.push(1)
        try arr1.dispose()

        // Should still be able to create new arrays
        let arr2 = try perl.createArray()
        try arr2.push(2)
        #expect(try arr2.count == 1)

        try arr2.dispose()
    }

    @Test func testHashDisposalDoesNotAffectPerl() throws {
        let hash1 = try perl.createHash()
        try hash1.set(key: "x", value: 1)
        try hash1.dispose()

        // Should still be able to create new hashes
        let hash2 = try perl.createHash()
        try hash2.set(key: "y", value: 2)
        #expect(try hash2.contains(key: "y") == true)

        try hash2.dispose()
    }
}
