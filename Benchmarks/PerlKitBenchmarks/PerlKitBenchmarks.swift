import Benchmark
import Foundation
import PerlKit

@MainActor
let benchmarks = {
    // Text processing
    Benchmark("LogParsing",
              configuration: .init(
                metrics: [.wallClock, .cpuTotal, .throughput, .peakMemoryResident],
                scalingFactor: .one
              )) { benchmark in
        let perl = try PerlKit.create()
        defer { try? perl.dispose() }

        let logData = """
        2024-01-15 10:23:45 INFO User login successful: user@example.com
        2024-01-15 10:24:12 ERROR Database connection failed: timeout
        2024-01-15 10:24:30 WARN High memory usage detected: 85%
        2024-01-15 10:25:01 INFO Request processed: /api/users (200ms)
        2024-01-15 10:25:15 ERROR Authentication failed: invalid token
        """

        try perl.setVariable("log_data", value: logData)

        let script = """
        my @lines = split /\\n/, $log_data;
        my %stats = (INFO => 0, ERROR => 0, WARN => 0);
        foreach my $line (@lines) {
            $stats{INFO}++ if $line =~ /INFO/;
            $stats{ERROR}++ if $line =~ /ERROR/;
            $stats{WARN}++ if $line =~ /WARN/;
        }
        $stats{ERROR};
        """

        benchmark.startMeasurement()

        for _ in benchmark.scaledIterations {
            let result = try perl.eval(script)
            precondition(result.success, "eval failed: \(result.error ?? "unknown error")")
            blackHole(result)
        }

        benchmark.stopMeasurement()
    }

    Benchmark("CSVProcessing",
              configuration: .init(
                metrics: [.wallClock, .cpuTotal, .throughput],
                scalingFactor: .one
              )) { benchmark in
        let perl = try PerlKit.create()
        defer { try? perl.dispose() }

        let csvData = """
        name,age,city,score
        Alice,30,NYC,95
        Bob,25,LA,87
        Charlie,35,Chicago,92
        Diana,28,Boston,88
        """

        try perl.setVariable("csv_data", value: csvData)

        let script = """
        my @lines = split /\\n/, $csv_data;
        shift @lines;
        my $total_score = 0;
        my $count = 0;
        foreach my $line (@lines) {
            next if $line =~ /^\\s*$/;
            my @fields = split /,/, $line;
            $total_score += $fields[3];
            $count++;
        }
        $count > 0 ? int($total_score / $count) : 0;
        """

        benchmark.startMeasurement()

        for _ in benchmark.scaledIterations {
            let result = try perl.eval(script)
            precondition(result.success, "eval failed: \(result.error ?? "unknown error")")
            blackHole(result)
        }

        benchmark.stopMeasurement()
    }

    Benchmark("RegexValidation",
              configuration: .init(
                metrics: [.wallClock, .cpuTotal, .throughput],
                scalingFactor: .kilo
              )) { benchmark in
        let perl = try PerlKit.create()
        defer { try? perl.dispose() }

        let script = """
        my @emails = (
            'user@example.com',
            'test.user@domain.co.uk',
            'invalid.email',
            'another@test.org'
        );
        my $valid_count = 0;
        foreach my $email (@emails) {
            $valid_count++ if $email =~ /^[\\w.+-]+\\@[\\w.-]+\\.[a-zA-Z]{2,}$/;
        }
        $valid_count;
        """

        benchmark.startMeasurement()

        for _ in benchmark.scaledIterations {
            let result = try perl.eval(script)
            precondition(result.success, "eval failed: \(result.error ?? "unknown error")")
            blackHole(result)
        }

        benchmark.stopMeasurement()
    }

    Benchmark("TemplateSubstitution",
              configuration: .init(
                metrics: [.wallClock, .cpuTotal, .throughput],
                scalingFactor: .one
              )) { benchmark in
        let perl = try PerlKit.create()
        defer { try? perl.dispose() }

        let template = "Hello {{name}}, your order #{{order_id}} totaling ${{amount}} has been shipped!"

        try perl.setVariable("template", value: template)

        let script = """
        my %data = (
            name => 'Alice Johnson',
            order_id => '12345',
            amount => '99.99'
        );
        my $result = $template;
        foreach my $key (keys %data) {
            my $value = $data{$key};
            $result =~ s/\\{\\{$key\\}\\}/$value/g;
        }
        $result;
        """

        benchmark.startMeasurement()

        for _ in benchmark.scaledIterations {
            let result = try perl.eval(script)
            precondition(result.success, "eval failed: \(result.error ?? "unknown error")")
            blackHole(result)
        }

        benchmark.stopMeasurement()
    }

    Benchmark("DataAggregation",
              configuration: .init(
                metrics: [.wallClock, .cpuTotal, .throughput],
                scalingFactor: .one
              )) { benchmark in
        let perl = try PerlKit.create()
        defer { try? perl.dispose() }

        let script = """
        my @transactions = (
            {amount => 100, category => 'food'},
            {amount => 50, category => 'transport'},
            {amount => 200, category => 'food'},
            {amount => 75, category => 'entertainment'},
            {amount => 150, category => 'food'},
            {amount => 30, category => 'transport'}
        );

        my %by_category;
        foreach my $tx (@transactions) {
            $by_category{$tx->{category}} += $tx->{amount};
        }

        my $max_amount = 0;
        foreach my $cat (keys %by_category) {
            $max_amount = $by_category{$cat} if $by_category{$cat} > $max_amount;
        }
        $max_amount;
        """

        benchmark.startMeasurement()

        for _ in benchmark.scaledIterations {
            let result = try perl.eval(script)
            precondition(result.success, "eval failed: \(result.error ?? "unknown error")")
            blackHole(result)
        }

        benchmark.stopMeasurement()
    }

    Benchmark("ConfigFileProcessing",
              configuration: .init(
                metrics: [.wallClock, .cpuTotal, .throughput, .syscalls],
                scalingFactor: .one
              )) { benchmark in
        benchmark.startMeasurement()

        for _ in benchmark.scaledIterations {
            let configContent = """
            app.name=MyApp
            app.version=1.0.0
            database.host=localhost
            database.port=5432
            """
            let configPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("perlkit-bench-config.txt").path
            try configContent.write(toFile: configPath, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(atPath: configPath) }

            let perl = try PerlKit.create()

            let script = """
            open my $fh, '<', '\(configPath)' or die $!;
            my %config;
            while (my $line = <$fh>) {
                next if $line =~ /^\\s*$/;
                if ($line =~ /^([^=]+)=(.+)$/) {
                    my ($key, $value) = ($1, $2);
                    $key =~ s/^\\s+|\\s+$//g;
                    $value =~ s/^\\s+|\\s+$//g;
                    $config{$key} = $value;
                }
            }
            close $fh;
            scalar(keys %config);
            """

            let result = try perl.eval(script)
            precondition(result.success, "eval failed: \(result.error ?? "unknown error")")
            blackHole(result)
            try perl.dispose()
        }

        benchmark.stopMeasurement()
    }

    Benchmark("WordFrequency",
              configuration: .init(
                metrics: [.wallClock, .cpuTotal, .throughput],
                scalingFactor: .one
              )) { benchmark in
        let perl = try PerlKit.create()
        defer { try? perl.dispose() }

        let text = "the quick brown fox jumps over the lazy dog the fox was quick"
        try perl.setVariable("text", value: text)

        let script = """
        my @words = split /\\s+/, lc($text);
        my %freq;
        foreach my $word (@words) {
            $freq{$word}++;
        }

        my $max_count = 0;
        foreach my $word (keys %freq) {
            $max_count = $freq{$word} if $freq{$word} > $max_count;
        }
        $max_count;
        """

        benchmark.startMeasurement()

        for _ in benchmark.scaledIterations {
            let result = try perl.eval(script)
            precondition(result.success, "eval failed: \(result.error ?? "unknown error")")
            blackHole(result)
        }

        benchmark.stopMeasurement()
    }

    Benchmark("SwiftToPerlDataTransfer",
              configuration: .init(
                metrics: [.wallClock, .cpuTotal, .throughput, .mallocCountTotal],
                scalingFactor: .one
              )) { benchmark in
        let perl = try PerlKit.create()
        defer { try? perl.dispose() }

        benchmark.startMeasurement()

        for _ in benchmark.scaledIterations {
            let temps = [72, 75, 68, 80, 77]

            let tempArray = try perl.createArray()
            for temp in temps {
                try tempArray.push(temp)
            }
            let tempRef = try tempArray.ref()
            try perl.setVariable("temperatures", value: tempRef)

            let result = try perl.eval("""
                my $sum = 0;
                foreach my $t (@$temperatures) { $sum += $t; }
                int($sum / scalar(@$temperatures));
                """)

            blackHole(result)

            try tempArray.dispose()
            try tempRef.dispose()
        }

        benchmark.stopMeasurement()
    }

    Benchmark("HostFunctionCallback",
              configuration: .init(
                metrics: [.wallClock, .cpuTotal, .throughput],
                scalingFactor: .kilo
              )) { benchmark in
        let perl = try PerlKit.create()
        defer { try? perl.dispose() }

        try perl.registerFunction("validate") { [perl] args in
            guard let arg = args.first else { return nil }
            let num = try arg.toInt()
            return try perl.createBool(num > 0 && num < 100)
        }

        let script = """
        my @numbers = (5, 150, 42, -10, 75);
        my @valid;
        foreach my $num (@numbers) {
            push @valid, $num if validate($num);
        }
        scalar(@valid);
        """

        benchmark.startMeasurement()

        for _ in benchmark.scaledIterations {
            let result = try perl.eval(script)
            precondition(result.success, "eval failed: \(result.error ?? "unknown error")")
            blackHole(result)
        }

        benchmark.stopMeasurement()
    }

    Benchmark("HashLookup",
              configuration: .init(
                metrics: [.wallClock, .cpuTotal, .throughput],
                scalingFactor: .kilo
              )) { benchmark in
        let perl = try PerlKit.create()
        defer { try? perl.dispose() }

        let hash = try perl.createHash()
        defer { try? hash.dispose() }

        for i in 0..<100 {
            try hash.set(key: "key\(i)", value: i)
        }

        benchmark.startMeasurement()

        for i in benchmark.scaledIterations {
            let key = "key\(Int(i) % 100)"
            let val = try hash.get(key: key)
            blackHole(val)
            try val?.dispose()
        }

        benchmark.stopMeasurement()
    }

    Benchmark("ArrayIteration",
              configuration: .init(
                metrics: [.wallClock, .cpuTotal, .throughput],
                scalingFactor: .kilo
              )) { benchmark in
        let perl = try PerlKit.create()
        defer { try? perl.dispose() }

        let arr = try perl.createArray()
        defer { try? arr.dispose() }

        for i in 0..<100 {
            try arr.push(i)
        }

        benchmark.startMeasurement()

        for _ in benchmark.scaledIterations {
            let count = try arr.count
            for i in 0..<count {
                let val = try arr.get(i)
                blackHole(val)
                try val?.dispose()
            }
        }

        benchmark.stopMeasurement()
    }

    Benchmark("VariableGetSet",
              configuration: .init(
                metrics: [.wallClock, .cpuTotal, .throughput, .mallocCountTotal],
                scalingFactor: .kilo
              )) { benchmark in
        let perl = try PerlKit.create()
        defer { try? perl.dispose() }

        benchmark.startMeasurement()

        for i in benchmark.scaledIterations {
            try perl.setVariable("x", value: Int32(i))
            let val = try perl.getVariable("x")
            blackHole(val)
            try val?.dispose()
        }

        benchmark.stopMeasurement()
    }

    Benchmark("SubroutineCall",
              configuration: .init(
                metrics: [.wallClock, .cpuTotal, .throughput],
                scalingFactor: .kilo
              )) { benchmark in
        let perl = try PerlKit.create()
        defer { try? perl.dispose() }

        let setupResult = try perl.eval("sub add { my ($a, $b) = @_; return $a + $b; }")
        precondition(setupResult.success, "eval failed: \(setupResult.error ?? "unknown error")")

        let arg1 = try perl.createInt(10)
        let arg2 = try perl.createInt(32)
        defer {
            try? arg1.dispose()
            try? arg2.dispose()
        }

        benchmark.startMeasurement()

        for _ in benchmark.scaledIterations {
            let results = try perl.call("add", arguments: [arg1, arg2])
            blackHole(results)
            for r in results {
                try r.dispose()
            }
        }

        benchmark.stopMeasurement()
    }

    Benchmark("RecursiveFibonacci",
              configuration: .init(
                metrics: [.wallClock, .cpuTotal, .throughput],
                scalingFactor: .kilo
              )) { benchmark in
        let perl = try PerlKit.create()
        defer { try? perl.dispose() }

        let script = """
        sub fib {
            my ($n) = @_;
            return $n if $n <= 1;
            return fib($n-1) + fib($n-2);
        }
        fib(10);
        """

        benchmark.startMeasurement()

        for _ in benchmark.scaledIterations {
            let result = try perl.eval(script)
            precondition(result.success, "eval failed: \(result.error ?? "unknown error")")
            blackHole(result)
        }

        benchmark.stopMeasurement()
    }
}
