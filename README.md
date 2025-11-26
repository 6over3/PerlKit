# PerlKit

A Swift 6 wrapper around [zeroperl](https://github.com/6over3/zeroperl) for embedding Perl 5 in Swift applications. zeroperl runs Perl in a WebAssembly sandbox.

## Installation

```bash
swift package add-dependency https://github.com/6over3/PerlKit --up-to-next-minor-from 1.0.0
swift package add-target-dependency PerlKit <your-package-target-name> --package PerlKit
```

Or add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/6over3/PerlKit.git", from: "1.0.0")
]
```

## Quick Start

```swift
import PerlKit

let perl = try PerlKit.create()

let result = try perl.eval("21 * 2")
print(try result.returnValue?.toInt())  // 42

let output = try perl.readStdout()
```

## Output Buffering

stdout and stderr are captured by default:

```swift
let perl = try PerlKit.create()

try perl.eval("print 'Hello'; warn 'Warning';")

print(try perl.readStdout())  // "Hello"
print(try perl.readStderr())  // "Warning at -e line 1."
```

Disable buffering:

```swift
let options = PerlKitOptions(captureStdout: false, captureStderr: false)
let perl = try PerlKit.create(options: options)
```

## Basic Usage

### Evaluating Code

```swift
let result = try perl.eval("""
    my $x = 10;
    my $y = 20;
    $x + $y
    """)

print(try result.returnValue?.toInt())  // 30
```

### Exchanging Data

```swift
try perl.setVariable("name", value: "Alice")
try perl.setVariable("age", value: 30)

try perl.eval("print \"$name is $age years old\\n\"")

try perl.eval("$result = 'computed value'")
let value = try perl.getVariable("result")
print(try value?.toString())
```

### Working with Arrays

```swift
let arr = try perl.createArray()
try arr.push("apple")
try arr.push("banana")
try arr.push("cherry")

// Arrays are Sequence - use Swift iteration
for item in arr {
    print(try item.toString())
}

// Or pass to Perl
let arrRef = try arr.ref()
try perl.setVariable("fruits", value: arrRef)

try perl.eval("""
    foreach my $fruit (@$fruits) {
        print "$fruit\\n";
    }
    """)
```

Reading arrays from Perl:

```swift
try perl.eval("@numbers = (1, 2, 3, 4, 5)")
let numbersRef = try perl.getVariable("numbers")
let array = try numbersRef?.deref() as PerlArray

for num in array {
    print(try num.toInt())
}
```

### Working with Hashes

```swift
let hash = try perl.createHash()
try hash.set(key: "name", value: "Bob")
try hash.set(key: "age", value: 25)
try hash.set(key: "city", value: "NYC")

// Hashes are Sequence - iterate over key-value pairs
for (key, value) in hash {
    print("\(key): \(try value.toString())")
}

// Or pass to Perl
let hashRef = try hash.ref()
try perl.setVariable("person", value: hashRef)

try perl.eval("print \"$person->{name} is $person->{age}\\n\"")
```

Reading hashes from Perl:

```swift
try perl.eval("%config = (host => 'localhost', port => 8080)")
let configRef = try perl.getVariable("config")
let configHash = try configRef?.deref() as PerlHash

let host = try configHash.get(key: "host")
print(try host?.toString())
```

### Command-Line Arguments

```swift
let args = try perl.createArray()
try args.push("file.txt")
try args.push("--verbose")

let argsRef = try args.ref()
try perl.setVariable("ARGV", value: argsRef)

try perl.eval("""
    foreach my $arg (@ARGV) {
        print "Arg: $arg\\n";
    }
    """)
```

## Working with Files

### Virtual Filesystem

```swift
let fs = try PerlFileSystem()
try fs.addFile(at: "/data.txt", content: "Line 1\nLine 2\nLine 3")

let options = PerlKitOptions(fileSystem: fs)
let perl = try PerlKit.create(options: options)

try perl.eval("""
    open my $fh, '<', '/data.txt' or die $!;
    while (my $line = <$fh>) {
        print $line;
    }
    close $fh;
    """)
```

### Running Scripts

```swift
let script = """
    my $sum = 0;
    $sum += $_ for 1..10;
    print "Sum: $sum\\n";
    """

let fs = try PerlFileSystem()
try fs.addFile(at: "/script.pl", content: script)

let options = PerlKitOptions(fileSystem: fs)
let perl = try PerlKit.create(options: options)

try perl.eval("do '/script.pl'")
print(try perl.readStdout())
```

### Reading and Writing Files

```swift
let fs = try PerlFileSystem()
try fs.addFile(at: "/input.txt", content: "Hello World")

let options = PerlKitOptions(fileSystem: fs)
let perl = try PerlKit.create(options: options)

try perl.eval("""
    open my $in, '<', '/input.txt' or die $!;
    my $content = <$in>;
    close $in;

    $content =~ s/World/Perl/;

    open my $out, '>', '/output.txt' or die $!;
    print $out $content;
    close $out;
    """)

try perl.eval("open my $fh, '<', '/output.txt'; $output = <$fh>; close $fh")
let result = try perl.getVariable("output")
print(try result?.toString())  // "Hello Perl"
```

## Advanced Usage

### Registering Swift Functions

```swift
try perl.registerFunction("add") { [perl] args in
    let a = try args[0].toInt()
    let b = try args[1].toInt()
    return try perl.createInt(a + b)
}

try perl.eval("print add(10, 32), \"\\n\"")  // 42
```

### Registering Swift Methods

```swift
class Calculator {
    func multiply(_ a: Int32, _ b: Int32) -> Int32 {
        a * b
    }
}

let calc = Calculator()

try perl.registerMethod("multiply") { [perl] args in
    let a = try args[0].toInt()
    let b = try args[1].toInt()
    return try perl.createInt(calc.multiply(a, b))
}

try perl.eval("print multiply(6, 7), \"\\n\"")  // 42
```

### Calling Perl Subroutines

```swift
try perl.eval("""
    sub greet {
        my ($name, $greeting) = @_;
        return "$greeting, $name!";
    }
    """)

let name = try perl.createString("Alice")
let greeting = try perl.createString("Hello")

let results = try perl.call("greet", arguments: [name, greeting])
print(try results[0].toString())  // "Hello, Alice!"
```

### Environment Variables

```swift
let env = [
    "APP_NAME": "MyApp",
    "APP_VERSION": "1.0.0"
]

let options = PerlKitOptions(environment: env)
let perl = try PerlKit.create(options: options)

try perl.eval("print \"$ENV{APP_NAME} v$ENV{APP_VERSION}\\n\"")
```

### Resetting State

```swift
try perl.eval("$x = 42")
print(try perl.getVariable("x")?.toInt())  // 42

try perl.reset()

print(try perl.getVariable("x") == nil)  // true
```

## API Reference

### PerlKit

```swift
static func create(options: PerlKitOptions? = nil) throws -> PerlKit
func dispose() throws
func eval(_ code: String) throws -> EvalResult
func call(_ name: String, arguments: [PerlValue]) throws -> [PerlValue]
func setVariable(_ name: String, value: some PerlConvertible) throws
func getVariable(_ name: String) throws -> PerlValue?
func createInt(_ value: Int32) throws -> PerlValue
func createDouble(_ value: Double) throws -> PerlValue
func createString(_ value: String) throws -> PerlValue
func createBool(_ value: Bool) throws -> PerlValue
func createArray() throws -> PerlArray
func createHash() throws -> PerlHash
func registerFunction(_ name: String, _ handler: @escaping ([PerlValue]) throws -> PerlValue?) throws
func registerMethod(_ name: String, _ handler: @escaping ([PerlValue]) throws -> PerlValue?) throws
func readStdout() throws -> String
func readStderr() throws -> String
func reset() throws
```

### PerlValue

```swift
func toInt() throws -> Int32
func toDouble() throws -> Double
func toString() throws -> String
func toBool() throws -> Bool
func deref() throws -> PerlArray
func deref() throws -> PerlHash
func dispose() throws
```

### PerlArray

```swift
var count: Int { get throws }
func get(_ index: Int) throws -> PerlValue?
func set(_ index: Int, value: some PerlConvertible) throws
func push(_ value: some PerlConvertible) throws
func pop() throws -> PerlValue?
func ref() throws -> PerlValue
func dispose() throws
```

Conforms to `Sequence` for Swift-style iteration.

### PerlHash

```swift
func get(key: String) throws -> PerlValue?
func set(key: String, value: some PerlConvertible) throws
func exists(key: String) throws -> Bool
func delete(key: String) throws
func keys() throws -> [String]
func ref() throws -> PerlValue
func dispose() throws
```

Conforms to `Sequence` for Swift-style iteration over `(key: String, value: PerlValue)` tuples.

### PerlFileSystem

```swift
init() throws
func addFile(at path: String, content: String) throws
func addFile(at path: String, data: Data) throws
```

### PerlKitOptions

```swift
struct PerlKitOptions {
    var environment: [String: String] = [:]
    var fileSystem: PerlFileSystem? = nil
    var captureStdout: Bool = true
    var captureStderr: Bool = true
}
```

### EvalResult

```swift
struct EvalResult {
    let success: Bool
    let returnValue: PerlValue?
    let error: String?
}
```

## Examples

See [Tests/PerlKitTests/PerlKitTests.swift](Tests/PerlKitTests/PerlKitTests.swift) for comprehensive examples.

See [Benchmarks/PerlKitBenchmarks/PerlKitBenchmarks.swift](Benchmarks/PerlKitBenchmarks/PerlKitBenchmarks.swift) for performance benchmarks.

## Development

```bash
swift build
swift test
swift package --allow-writing-to-package-directory benchmark
```

## License

Apache License 2.0
