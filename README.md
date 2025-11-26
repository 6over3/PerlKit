# PerlKit

A Swift 6 wrapper around [zeroperl](https://github.com/6over3/zeroperl) for embedding Perl 5 in Swift applications. zeroperl runs Perl in a WebAssembly sandbox.

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/6over3/PerlKit.git", from: "1.0.0")
]
```

Or via command line:

```bash
swift package add-dependency https://github.com/6over3/PerlKit --up-to-next-minor-from 1.0.0
swift package add-target-dependency PerlKit <your-target> --package PerlKit
```

## Quick Start

```swift
import PerlKit

let perl = try PerlKit.create()

let result = try perl.eval("21 * 2")
print(result.success)  // true
print(result.exitCode) // 0

// Get the result via a variable
try perl.eval("$answer = 21 * 2")
let answer = try perl.getVariable("answer")
print(try answer?.toInt())  // 42

print(try perl.readStdout())
```

## Output Capture

stdout and stderr are captured by default:

```swift
let perl = try PerlKit.create()

try perl.eval("print 'Hello'; warn 'Warning';")

print(try perl.readStdout())  // "Hello"
print(try perl.readStderr())  // "Warning at -e line 1."
```

Disable capture to let output go to the console:

```swift
let options = PerlKitOptions(captureStdout: false, captureStderr: false)
let perl = try PerlKit.create(options: options)
```

## Evaluating Code

`eval` returns a `PerlResult` with `success`, `error`, and `exitCode`:

```swift
let result = try perl.eval("""
    my $x = 10;
    my $y = 20;
    print $x + $y;
    """)

if result.success {
    print(try perl.readStdout())  // "30"
} else {
    print(result.error ?? "Unknown error")
}
```

## Variables

### Setting Variables

```swift
try perl.setVariable("name", value: "Alice")
try perl.setVariable("age", value: 30)
try perl.setVariable("price", value: 19.99)
try perl.setVariable("active", value: true)

try perl.eval(#"print "$name is $age years old\n""#)
```

### Getting Variables

```swift
try perl.eval("$result = 'computed value'")
let value = try perl.getVariable("result")
print(try value?.toString())  // "computed value"
```

## Arrays

### Creating Arrays

```swift
let arr = try perl.createArray()
try arr.push("apple")
try arr.push("banana")
try arr.push("cherry")

print(try arr.count)  // 3
```

### Iterating (PerlArray conforms to Sequence)

```swift
for item in arr {
    print(try item.toString())
}
```

### Passing Arrays to Perl

```swift
let arrRef = try arr.ref()
try perl.setVariable("fruits", value: arrRef)

try perl.eval("""
    foreach my $fruit (@$fruits) {
        print "$fruit\\n";
    }
    """)
```

### Reading Arrays from Perl

```swift
try perl.eval("@numbers = (1, 2, 3, 4, 5)")
let numbers = try perl.getArrayVariable("numbers")

for num in numbers! {
    print(try num.toInt())
}
```

### Array Operations

```swift
let arr = try perl.createArray()
try arr.push("first")
try arr.push("second")

let item = try arr.get(0)        // Get by index
try arr.set(1, value: "changed") // Set by index
let last = try arr.pop()         // Pop last element
try arr.removeAll()              // Clear array
```

## Hashes

### Creating Hashes

```swift
let hash = try perl.createHash()
try hash.set(key: "name", value: "Bob")
try hash.set(key: "age", value: 25)
try hash.set(key: "city", value: "NYC")
```

### Iterating (PerlHash conforms to Sequence)

```swift
for (key, value) in hash {
    print("\(key): \(try value.toString())")
}
```

### Passing Hashes to Perl

```swift
let hashRef = try hash.ref()
try perl.setVariable("person", value: hashRef)

try perl.eval(#"print "$person->{name} is $person->{age}\n""#)
```

### Reading Hashes from Perl

```swift
try perl.eval("%config = (host => 'localhost', port => 8080)")
let config = try perl.getHashVariable("config")

let host = try config?.get(key: "host")
print(try host?.toString())  // "localhost"
```

### Hash Operations

```swift
let hash = try perl.createHash()
try hash.set(key: "foo", value: "bar")

let exists = try hash.contains(key: "foo")  // true
let val = try hash.get(key: "foo")          // Get value
try hash.remove(key: "foo")                 // Delete key
try hash.removeAll()                        // Clear hash

let allKeys = try hash.keys()               // [String]
let allEntries = try hash.entries()         // [(key: String, value: PerlValue)]
```

## Calling Perl Subroutines

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

## Registering Swift Functions

Call Swift code from Perl:

```swift
try perl.registerFunction("add") { args in
    let a = try args[0].toInt()
    let b = try args[1].toInt()
    return try perl.createInt(a + b)
}

try perl.eval(#"print add(10, 32), "\n""#)  // 42
```

### Registering Methods on Packages

```swift
try perl.registerMethod(package: "Calculator", method: "multiply") { args in
    let a = try args[0].toInt()
    let b = try args[1].toInt()
    return try perl.createInt(a * b)
}

try perl.eval(#"print Calculator->multiply(6, 7), "\n""#)  // 42
```

## Virtual Filesystem

### Adding Files

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

### Running Script Files

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

try perl.runFile("/script.pl")
print(try perl.readStdout())  // "Sum: 55\n"
```

### Command-Line Arguments

```swift
let script = """
    foreach my $arg (@ARGV) {
        print "Arg: $arg\\n";
    }
    """

let fs = try PerlFileSystem()
try fs.addFile(at: "/script.pl", content: script)

let options = PerlKitOptions(fileSystem: fs)
let perl = try PerlKit.create(options: options)

try perl.runFile("/script.pl", arguments: ["file.txt", "--verbose"])
print(try perl.readStdout())  // "Arg: file.txt\nArg: --verbose\n"
```

## Environment Variables

```swift
let env = [
    "APP_NAME": "MyApp",
    "APP_VERSION": "1.0.0"
]

let options = PerlKitOptions(environment: env)
let perl = try PerlKit.create(options: options)

try perl.eval(#"print "$ENV{APP_NAME} v$ENV{APP_VERSION}\n""#)
```

## State Management

### Resetting the Interpreter

```swift
try perl.eval("$x = 42")
print(try perl.getVariable("x")?.toInt())  // 42

try perl.reset()

print(try perl.getVariable("x"))  // nil
```

### Error Handling

```swift
let result = try perl.eval("die 'Something went wrong'")
if !result.success {
    print(result.error)  // "Something went wrong at -e line 1."
}

// Or check the last error directly
let lastErr = try perl.lastError()
try perl.clearError()
```

## Memory Management

PerlValue, PerlArray, and PerlHash should be disposed when no longer needed:

```swift
let value = try perl.createString("hello")
// use value...
try value.dispose()

let array = try perl.createArray()
// use array...
try array.dispose()
```

Dispose the interpreter when done:

```swift
try perl.dispose()
```

## API Reference

### PerlKit

| Method | Description |
|--------|-------------|
| `create(options:)` | Create a new interpreter |
| `create(withArgs:options:)` | Create with command-line args |
| `eval(_:arguments:)` | Evaluate Perl code |
| `runFile(_:arguments:)` | Run a script file |
| `call(_:arguments:context:)` | Call a Perl subroutine |
| `getVariable(_:)` | Get a scalar variable |
| `setVariable(_:value:)` | Set a scalar variable |
| `getArrayVariable(_:)` | Get an array variable |
| `getHashVariable(_:)` | Get a hash variable |
| `createInt(_:)` | Create an integer value |
| `createDouble(_:)` | Create a double value |
| `createString(_:)` | Create a string value |
| `createBool(_:)` | Create a boolean value |
| `createUndef()` | Create an undef value |
| `createArray()` | Create an empty array |
| `createHash()` | Create an empty hash |
| `registerFunction(_:function:)` | Register a Swift function |
| `registerMethod(package:method:function:)` | Register a Swift method |
| `readStdout()` | Get captured stdout |
| `readStderr()` | Get captured stderr |
| `flush()` | Flush output buffers |
| `reset()` | Reset interpreter state |
| `lastError()` | Get last Perl error |
| `clearError()` | Clear error state |
| `dispose()` | Free interpreter memory |

### PerlValue

| Method | Description |
|--------|-------------|
| `type()` | Get the value type |
| `isUndef` | Check if undefined |
| `isRef` | Check if a reference |
| `toInt()` | Convert to Int32 |
| `toDouble()` | Convert to Double |
| `toString()` | Convert to String |
| `toBool()` | Convert to Bool |
| `toArray(using:)` | Convert to PerlArray |
| `toHash(using:)` | Convert to PerlHash |
| `createRef()` | Create a reference to this value |
| `deref()` | Dereference |
| `dispose()` | Free memory |

### PerlArray

| Method | Description |
|--------|-------------|
| `count` | Number of elements |
| `isEmpty` | Check if empty |
| `get(_:)` | Get element by index |
| `set(_:value:)` | Set element by index |
| `push(_:)` | Append element |
| `pop()` | Remove and return last element |
| `removeAll()` | Clear the array |
| `ref()` | Get as a reference value |
| `dispose()` | Free memory |

### PerlHash

| Method | Description |
|--------|-------------|
| `get(key:)` | Get value by key |
| `set(key:value:)` | Set key-value pair |
| `contains(key:)` | Check if key exists |
| `remove(key:)` | Delete a key |
| `removeAll()` | Clear the hash |
| `keys()` | Get all keys |
| `entries()` | Get all key-value pairs |
| `ref()` | Get as a reference value |
| `dispose()` | Free memory |

### PerlFileSystem

| Method | Description |
|--------|-------------|
| `init()` | Create a new filesystem |
| `addFile(at:content:)` | Add a file (String or Data) |
| `addFile(at:handle:)` | Add a file from FileDescriptor |
| `getFile(at:)` | Read file content |
| `removeFile(at:)` | Delete a file |

### PerlKitOptions

```swift
PerlKitOptions(
    environment: [String: String] = [:],
    fileSystem: PerlFileSystem? = nil,
    captureStdout: Bool = true,
    captureStderr: Bool = true
)
```

### PerlResult

```swift
struct PerlResult {
    let success: Bool
    let error: String?
    let exitCode: Int32
}
```

### PerlConvertible

Types conforming to `PerlConvertible` can be passed directly to `setVariable` and array/hash methods:

- `String`
- `Int`, `Int32`, `Int64`
- `UInt`, `UInt32`
- `Double`, `Float`
- `Bool`
- `Optional<T>` where T: PerlConvertible
- `Array<T>` where T: PerlConvertible
- `Dictionary<String, T>` where T: PerlConvertible
- `PerlValue`

## Development

```bash
swift build
swift test
swift package --allow-writing-to-package-directory benchmark
```

## License

Apache License 2.0