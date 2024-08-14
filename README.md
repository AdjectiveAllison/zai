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
            .root_source_file = b.path("src/main.zig"),
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

## Features

- Support for chat completions and embeddings
- Streaming capabilities for real-time responses
- Easy integration with Zig projects
- Configurable model selection
- Automatic provider-specific API handling (in the works)

## Usage

### Chat Completion

Here's a basic example of using zai for chat completion:

```zig
const std = @import("std");
const zai = @import("zai");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ai: zai.AI = undefined;
    try ai.init(allocator, zai.Provider.OctoAI);
    defer ai.deinit();

    var messages = [_]zai.Message{
        .{
            .role = "system",
            .content = "You are a helpful AI assistant.",
        },
        .{
            .role = "user",
            .content = "Write one sentence about how cool it would be to use zig to call language models.",
        },
    };

    const payload = zai.CompletionPayload{
        .model = "meta-llama-3.1-8b-instruct",
        .messages = &messages,
        .temperature = 0.1,
        .stream = true,
    };

    var chat_completion: zai.ChatCompletion = undefined;
    chat_completion.init(allocator);
    defer chat_completion.deinit();

    try chat_completion.streamAndPrint(&ai, payload);
}
```

### Embeddings

Here's how to use zai for generating embeddings:

```zig
const std = @import("std");
const zai = @import("zai");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ai: zai.AI = undefined;
    try ai.init(allocator, zai.Provider.OctoAI);
    defer ai.deinit();

    const input_text = "Zig is a general-purpose programming language and toolchain for maintaining robust, optimal, and reusable software.";

    const payload = zai.Embeddings.EmbeddingsPayload{
        .input = input_text,
        .model = "thenlper/gte-large",
    };

    var embeddings: zai.Embeddings = undefined;
    embeddings.init(allocator);
    defer embeddings.deinit();

    try embeddings.request(&ai, payload);

    std.debug.print("Embedding vector length: {d}\n", .{embeddings.embedding.len});
}
```

## Examples

You can find more detailed examples in the `examples/` directory:

1. [Chat Completion](examples/chat_completion.zig)
2. [Embeddings](examples/embeddings.zig)

To run an example, use:

```sh
zig build chat-completion
# or
zig build embeddings
```

## Configuration

zai uses environment variables for API keys (right now). Set the appropriate environment variable for your chosen provider:

- OpenAI: `OPENAI_API_KEY`
- OctoAI: `OCTOAI_TOKEN`
- TogetherAI: `TOGETHER_API_KEY`
- OpenRouter: `OPENROUTER_API_KEY`

## License

zai is released under the MIT License. See the [LICENSE](LICENSE) file for details.
