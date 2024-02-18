# zai - a Zig AI Library!

## Installation

1. Declare zai as a project dependency with `zig fetch`:

    ```sh
    # latest version
    zig fetch --save git+https://github.com/AdjectiveAllison/zai.git#main

    # specific commit
    zig fetch --save git+https://github.com/AdjectiveAllison/zai.git#COMMIT
    ```

2. Expose zai as a module in your project's `build.zig`:

    ```zig
    pub fn build(b: *std.Build) void {
        const target = b.standardTargetOptions(.{});
        const optimize = b.standardOptimizeOption(.{});

        const opts = .{ .target = target, .optimize = optimize };   // 👈
        const zai = b.dependency("zai", opts).module("zai"); // 👈

        const exe = b.addExecutable(.{
            .name = "my-project",
            .root_source_file = .{ .path = "src/main.zig" },
            .target = target,
            .optimize = optimize,
        });

        exe.root_module.addImport("zai", zai); // 👈

        // ...
    }
    ```

3. Import Zig AI into your code:

    ```zig
    const zai = @import("zai");
    ```

## Examples located in [examples directory](examples/)

1. [Chat Completion](examples/chat_completion.zig)
