# zai - a Zig AI Library

zai is a flexible Zig library for interacting with various AI providers' APIs, offering a unified interface for chat completions, embeddings, and more.


## Requirements

- Zig 0.13.0

## Features

- Multi-provider support:
  - OpenAI-compatible APIs (OpenAI, Together.ai, OpenRouter)
  - Amazon Bedrock
  - Anthropic
  - Support coming soon for Google Vertex AI and local models via zml
- Unified interface across providers
- Streaming support for real-time responses
- Provider and model registry for easy configuration
- Command-line interface (CLI) for quick interactions
- Supports chat completions, standard completions, and embeddings

## Installation

1. Add zai as a dependency using `zig fetch`:

```sh
# Latest version
zig fetch --save git+https://github.com/AdjectiveAllison/zai.git#main
```

2. Add zai as a module in your `build.zig`:

```zig
const zai_dep = b.dependency("zai", .{
    .target = target,
    .optimize = optimize,
});
const zai_mod = zai_dep.module("zai");

// Add to your executable
exe.root_module.addImport("zai", zai_mod);
```

## CLI Installation

To install the zai CLI tool:

```sh
zig build cli install -Doptimize=ReleaseFast --prefix ~/.local
```

## Usage

### Provider Configuration

First, create a provider configuration. You can do this programmatically or via the CLI:

```zig
const zai = @import("zai");

// OpenAI-compatible configuration
const provider_config = zai.ProviderConfig{ .OpenAI = .{
    .api_key = "your-api-key",
    .base_url = "https://api.together.xyz/v1",  // Together.ai example
}};

// Amazon Bedrock configuration
const bedrock_config = zai.ProviderConfig{ .AmazonBedrock = .{
    .access_key_id = "your-access-key",
    .secret_access_key = "your-secret-key",
    .region = "us-west-2",
}};

// Anthropic configuration
const anthropic_config = zai.ProviderConfig{ .Anthropic = .{
    .api_key = "your-anthropic-api-key",
}};
```

### Chat Example

```zig
const std = @import("std");
const zai = @import("zai");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize provider
    var provider = try zai.init(allocator, provider_config);
    defer provider.deinit();

    // Set up chat messages
    const messages = [_]zai.Message{
        .{
            .role = "system",
            .content = "You are a helpful assistant.",
        },
        .{
            .role = "user",
            .content = "Tell me a short joke.",
        },
    };

    // Configure chat options
    const chat_options = zai.ChatRequestOptions{
        .model = "mistralai/Mixtral-8x7B-v0.1",
        .messages = &messages,
        .temperature = 0.7,
        .stream = true,
    };

    // Stream the response
    try provider.chatStream(chat_options, std.io.getStdOut().writer());
}
```

### Provider Feature Matrix

| Provider       | Chat | Chat Stream | Completion | Completion Stream | Embeddings |
|---------------|------|-------------|------------|-------------------|------------|
| OpenAI-compatible | ✅   | ✅          | ✅         | ✅                | ✅         |
| Amazon Bedrock    | ✅   | ✅          | ❌         | ❌                | ❌         |
| Anthropic         | ✅   | ✅          | ❌         | ❌                | ❌         |
| Google Vertex*    | ❌   | ❌          | ❌         | ❌                | ❌         |
| Local (zml)*      | ❌   | ❌          | ❌         | ❌                | ❌         |

\* Coming soon

## CLI Usage

The zai CLI provides commands for managing providers, models, and making API calls:

```sh
# Add a provider (Idk if this works or not yet)
zai provider add openai --api-key "your-key" --base-url "https://api.openai.com/v1"

# Add a model to a provider
zai models add openai gpt-4 --id gpt-4-turbo-preview --chat

# Chat with a model (will use first provider and first model of provider by default)
zai chat --provider openai --model gpt-4 "Tell me a joke"
# same as this if openai and gpt-4 are your first provider and chat model in config.
zai chat "tell me a joke"
```

See more CLI examples and documentation by running:
```sh
zai --help
zai <command> --help
```

## Examples

Check out the `examples/` directory for more detailed examples:
- Chat using OpenAI-compatible APIs (`examples/chat_openai.zig`)
- Chat using Amazon Bedrock (`examples/chat_bedrock.zig`)
- Chat using Anthropic (`examples/chat_anthropic.zig`)
- Embeddings generation (`examples/embeddings.zig`)
- Provider registry management (`examples/registry.zig`)
- And more!

## Contributing

Contributions are welcome! Some areas that need work:
- Adding tests
- Improving CLI provider configuration workflow
- Implementing additional providers (Google Vertex AI)
- Local model support via zml integration
- Documentation improvements

## License

zai is released under the MIT License. See the [LICENSE](LICENSE) file for details.
