# Usage

zai is a unified Zig library for interacting with various AI provider APIs. It provides a consistent interface for chat completions, text completions, embeddings, and more across multiple providers.

## Basic Usage

The library requires three basic components to operate:

1. A provider configuration
2. An instance of a Provider
3. Request options specific to the operation you want to perform (chat, completion, embeddings)

### Provider Initialization

All interactions with AI models begin with initializing a provider:

```zig
const std = @import("std");
const zai = @import("zai");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create provider configuration
    const provider_config = zai.ProviderConfig{ .OpenAI = .{
        .api_key = "your-api-key",
        .base_url = "https://api.openai.com/v1",
        .organization = null, // Optional field for OpenAI
    }};

    // Initialize provider
    var provider = try zai.init(allocator, provider_config);
    defer provider.deinit();

    // Now you can use the provider to make requests
    // ...
}
```

### Chat Completions

To generate a chat completion:

```zig
const std = @import("std");
const zai = @import("zai");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize provider (OpenAI in this example)
    const provider_config = zai.ProviderConfig{ .OpenAI = .{
        .api_key = "your-api-key",
        .base_url = "https://api.openai.com/v1",
    }};
    var provider = try zai.init(allocator, provider_config);
    defer provider.deinit();

    // Define messages
    const messages = [_]zai.Message{
        .{
            .role = "system",
            .content = "You are a helpful assistant that provides concise answers.",
        },
        .{
            .role = "user",
            .content = "What is the capital of France?",
        },
    };

    // Create chat request options
    const chat_options = zai.ChatRequestOptions{
        .model = "gpt-4",
        .messages = &messages,
        .temperature = 0.7,
        .stream = false, // Set to false for non-streaming response
    };

    // Get chat completion
    const response = try provider.chat(chat_options);
    defer allocator.free(response);
    
    std.debug.print("Response: {s}\n", .{response});
}
```

### Streaming Chat Completions

For streaming responses (receiving tokens as they're generated):

```zig
const std = @import("std");
const zai = @import("zai");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize provider
    const provider_config = zai.ProviderConfig{ .OpenAI = .{
        .api_key = "your-api-key",
        .base_url = "https://api.openai.com/v1",
    }};
    var provider = try zai.init(allocator, provider_config);
    defer provider.deinit();

    // Define messages
    const messages = [_]zai.Message{
        .{
            .role = "system",
            .content = "You are a helpful assistant.",
        },
        .{
            .role = "user",
            .content = "Write a short poem about programming.",
        },
    };

    // Create chat request options with streaming enabled
    const chat_options = zai.ChatRequestOptions{
        .model = "gpt-4",
        .messages = &messages,
        .temperature = 0.7,
        .stream = true, // Enable streaming
    };

    // Use standard output as the writer
    const stdout = std.io.getStdOut().writer();
    
    // Stream the response
    try provider.chatStream(chat_options, stdout);
    try stdout.writeAll("\n"); // Add a newline at the end
}
```

### Text Completions

For traditional text completions:

```zig
const std = @import("std");
const zai = @import("zai");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize provider (using an OpenAI-compatible API like Together.ai)
    const provider_config = zai.ProviderConfig{ .OpenAI = .{
        .api_key = "your-api-key",
        .base_url = "https://api.together.xyz/v1",
    }};
    var provider = try zai.init(allocator, provider_config);
    defer provider.deinit();

    // Create completion request options
    const completion_options = zai.CompletionRequestOptions{
        .model = "mistralai/Mixtral-8x7B-v0.1",
        .prompt = "Once upon a time in a land of code,",
        .temperature = 0.7,
        .max_tokens = 100,
        .stream = false,
    };

    // Get completion
    const response = try provider.completion(completion_options);
    defer allocator.free(response);
    
    std.debug.print("Completion: {s}\n", .{response});
}
```

### Generating Embeddings

To generate embeddings for text:

```zig
const std = @import("std");
const zai = @import("zai");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize provider
    const provider_config = zai.ProviderConfig{ .OpenAI = .{
        .api_key = "your-api-key",
        .base_url = "https://api.together.xyz/v1", // Together.ai example
    }};
    var provider = try zai.init(allocator, provider_config);
    defer provider.deinit();

    // Input text to embed
    const input_text = "Zig is a general-purpose programming language and toolchain.";

    // Create embedding request options
    const embedding_options = zai.EmbeddingRequestOptions{
        .model = "BAAI/bge-large-en-v1.5",
        .input = input_text,
    };

    // Get embeddings
    const embedding = try provider.createEmbedding(embedding_options);
    defer allocator.free(embedding);
    
    // Print first few dimensions
    std.debug.print("Embedding dimensions: {d}\n", .{embedding.len});
    std.debug.print("First 5 values: ", .{});
    for (embedding[0..@min(5, embedding.len)]) |value| {
        std.debug.print("{d:.5} ", .{value});
    }
    std.debug.print("...\n", .{});
}
```

## Provider-Specific Configurations

### OpenAI and Compatible APIs

The OpenAI provider configuration works with OpenAI-compatible APIs like OpenAI, Together.ai, and OpenRouter.

```zig
// OpenAI
const openai_config = zai.ProviderConfig{ .OpenAI = .{
    .api_key = "your-openai-api-key",
    .base_url = "https://api.openai.com/v1",
    .organization = "your-org-id", // Optional
}};

// Together.ai
const together_config = zai.ProviderConfig{ .OpenAI = .{
    .api_key = "your-together-api-key",
    .base_url = "https://api.together.xyz/v1",
}};

// OpenRouter
const openrouter_config = zai.ProviderConfig{ .OpenAI = .{
    .api_key = "your-openrouter-api-key",
    .base_url = "https://openrouter.ai/api/v1",
}};
```

### Amazon Bedrock

Amazon Bedrock requires AWS credentials:

```zig
const bedrock_config = zai.ProviderConfig{ .AmazonBedrock = .{
    .access_key_id = "your-aws-access-key",
    .secret_access_key = "your-aws-secret-key",
    .region = "us-west-2", // AWS region where Bedrock is available
}};
```

### Anthropic

Anthropic provider configuration:

```zig
const anthropic_config = zai.ProviderConfig{ .Anthropic = .{
    .api_key = "your-anthropic-api-key",
    .default_max_tokens = 8000, // Default token limit
}};
```

## Registry System

The Registry system allows you to manage multiple providers and models in one place. This is particularly useful for applications that need to switch between different providers or maintain a catalog of available models.

### Creating and Managing a Registry

```zig
const std = @import("std");
const zai = @import("zai");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize a new registry
    var registry = zai.Registry.init(allocator);
    defer registry.deinit();

    // Create provider configuration
    const amazon_config = zai.ProviderConfig{ .AmazonBedrock = .{
        .region = "us-west-2",
        .access_key_id = "your-access-key",
        .secret_access_key = "your-secret-key",
    }};

    // Define models for the provider
    const models = [_]zai.ModelSpec{
        .{
            .id = "anthropic.claude-3-5-sonnet-20241022-v2:0",
            .name = "claude-3.5-sonnet",
            .capabilities = std.EnumSet(zai.registry.Capability).init(.{
                .chat = true,
            }),
        },
        .{
            .id = "anthropic.claude-3-opus-20240229:0",
            .name = "claude-3-opus",
            .capabilities = std.EnumSet(zai.registry.Capability).init(.{
                .chat = true,
            }),
        },
    };

    // Add provider with models to registry
    try registry.createProvider("aws", amazon_config, &models);

    // Save registry to file
    try registry.saveToFile("my_registry.json");
}
```

### Loading a Registry from File

```zig
const std = @import("std");
const zai = @import("zai");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Load registry from file
    var registry = try zai.Registry.loadFromFile(allocator, "my_registry.json");
    defer registry.deinit();

    // Initialize a specific provider
    try registry.initProvider("aws");

    // Get the provider
    const aws_provider = registry.getProvider("aws") orelse {
        std.debug.print("AWS provider not found\n", .{});
        return;
    };

    // Use the provider if it's initialized
    if (aws_provider.instance) |provider| {
        const messages = [_]zai.Message{
            .{ .role = "user", .content = "Tell me a joke" },
        };

        const chat_options = zai.ChatRequestOptions{
            .model = "anthropic.claude-3-5-sonnet-20241022-v2:0",
            .messages = &messages,
            .temperature = 0.7,
            .stream = false,
        };

        const response = try provider.chat(chat_options);
        defer allocator.free(response);
        std.debug.print("Response: {s}\n", .{response});
    }
}
```

## Prompt Management

zai includes a robust system for managing and reusing prompts across different models.

### Creating and Managing Prompts

```zig
const std = @import("std");
const zai = @import("zai");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Load registry
    var registry = try zai.Registry.loadFromFile(allocator, "config.json");
    defer registry.deinit();

    // Create a system prompt
    try registry.createPrompt(
        "helpful-assistant", 
        .system,
        "You are a helpful, accurate, and concise assistant. Provide clear explanations using examples when appropriate."
    );

    // Add a user prompt template
    try registry.createPrompt(
        "code-review", 
        .user,
        "Please review the following code and suggest improvements:\n\n```\n{CODE}\n```"
    );

    // Assign a default prompt to a model
    try registry.setModelDefaultPrompt("openai", "gpt-4", "helpful-assistant");

    // Save the updated registry
    try registry.saveToFile("config.json");
}
```

### Using Default Prompts in Chat

Once you've set a default prompt for a model, it will be used automatically in chat requests when no explicit system message is provided:

```zig
// This will use the model's default system prompt
const messages = [_]zai.Message{
    .{
        .role = "user",
        .content = "What is the capital of France?",
    },
};

// Or you can override it for a specific request
const messages_with_override = [_]zai.Message{
    .{
        .role = "system", 
        .content = "You are a travel guide who loves to share interesting facts.",
    },
    .{
        .role = "user",
        .content = "What is the capital of France?",
    },
};
```

## CLI Usage

The zai library includes a command-line interface for interacting with AI providers. Here are some common usage patterns:

### Managing Providers

```sh
# Add a new provider
zai provider add openai --api-key "your-api-key" --base-url "https://api.openai.com/v1"

# Add Amazon Bedrock provider
zai provider add amazon_bedrock --access-key-id "your-access-key" --secret-access-key "your-secret-key" --region "us-west-2"

# Add Anthropic provider
zai provider add anthropic --api-key "your-api-key" --default-max-tokens 8000

# List configured providers
zai provider list

# Remove a provider
zai provider remove openai

# Set default provider
zai provider set-default aws
```

### Managing Models

```sh
# List all available models across all providers
zai models list

# Add a model to a provider
zai models add aws claude-3-sonnet --id anthropic.claude-3-5-sonnet-20241022-v2:0 --chat

# Add a GPT model to OpenAI provider with multiple capabilities
zai models add openai gpt-4 --id gpt-4-turbo-preview --chat --completion

# Set default prompt for a model
zai models set-prompt anthropic claude-3-sonnet system-prompt-name

# Clear default prompt for a model
zai models clear-prompt anthropic claude-3-sonnet
```

### Managing Prompts

```sh
# List all prompts
zai prompt list

# View a specific prompt
zai prompt get my-system-prompt

# Add a new system prompt
zai prompt add my-system-prompt --type system --content "You are a helpful assistant that provides accurate information."

# Update an existing prompt
zai prompt update my-system-prompt --content "You are an expert assistant that specializes in providing detailed technical explanations."

# Import a prompt from a file
zai prompt import expert-prompt --type system --file ./prompts/expert.txt

# Remove a prompt
zai prompt remove outdated-prompt
```

### Chat and Completion

```sh
# Chat with default provider and model
zai chat "Tell me a joke about programming"

# Chat with specific provider and model
zai chat --provider openai --model gpt-4 "Explain quantum computing"

# Chat with a system message (overrides any default prompt)
zai chat --system-message "You are a helpful coding assistant" "How do I implement binary search in Zig?"

# Chat with a model that has a default system prompt
zai chat --model claude-3-sonnet "How do I implement binary search in Zig?"
# The model will automatically use its default system prompt if one has been set with 'models set-prompt'

# Get completion (not streaming)
zai completion --stream false "The best thing about Zig is"
```

### Shell Completions

The zai CLI provides shell completion scripts for fish, bash, and zsh:

```sh
# Generate completions for fish shell
zai completions fish > ~/.config/fish/completions/zai.fish

# Generate completions for bash
zai completions bash > ~/.bash_completion.d/zai

# Generate completions for zsh 
zai completions zsh > ~/.zsh/completions/_zai

# Install completions directly (creates directories if needed)
zai completions fish --install
zai completions bash --install
zai completions zsh --install
```

After installing completions, you can use tab completion for:
- Main commands and subcommands
- Provider and model names
- Command options and flags

## Provider Feature Support Matrix

Different providers support different features. Here's the current support status:

| Provider       | Chat | Chat Stream | Completion | Completion Stream | Embeddings |
|----------------|------|-------------|------------|-------------------|------------|
| OpenAI-compatible | ✅   | ✅          | ✅         | ✅                | ✅         |
| Amazon Bedrock    | ✅   | ✅          | ❌         | ❌                | ❌         |
| Anthropic         | ✅   | ✅          | ❌         | ❌                | ❌         |
| Google Vertex*    | ❌   | ❌          | ❌         | ❌                | ❌         |
| Local (zml)*      | ❌   | ❌          | ❌         | ❌                | ❌         |

\* Coming soon

## Advanced Usage

### Creating Custom Writers for Streaming

You can create custom writers to handle streaming responses:

```zig
const std = @import("std");
const zai = @import("zai");

// A simple buffered writer that collects the output
pub const BufferedWriter = struct {
    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) BufferedWriter {
        return .{
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *BufferedWriter) void {
        self.buffer.deinit();
    }

    // Writer interface method
    pub fn write(self: *BufferedWriter, data: []const u8) !usize {
        try self.buffer.appendSlice(data);
        return data.len;
    }

    pub fn writer(self: *BufferedWriter) std.io.AnyWriter {
        return .{ .context = self, .writeAll = writeAll };
    }

    fn writeAll(ctx: *anyopaque, data: []const u8) !void {
        const self: *BufferedWriter = @ptrCast(@alignCast(ctx));
        _ = try self.write(data);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var provider = try zai.init(allocator, provider_config);
    defer provider.deinit();

    // Custom writer that collects output
    var buffered_writer = BufferedWriter.init(allocator);
    defer buffered_writer.deinit();

    const messages = [_]zai.Message{
        .{ .role = "user", .content = "Write a haiku" },
    };

    const chat_options = zai.ChatRequestOptions{
        .model = "gpt-3.5-turbo",
        .messages = &messages,
        .stream = true,
    };

    // Stream to our custom writer
    try provider.chatStream(chat_options, buffered_writer.writer());

    // Use the collected output
    std.debug.print("Collected response: {s}\n", .{buffered_writer.buffer.items});
}
```

### Error Handling

zai uses a unified error system that abstracts provider-specific errors:

```zig
const std = @import("std");
const zai = @import("zai");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize provider with potentially wrong API key
    const provider_config = zai.ProviderConfig{ .OpenAI = .{
        .api_key = "potentially-invalid-key",
        .base_url = "https://api.openai.com/v1",
    }};

    var provider = zai.init(allocator, provider_config) catch |err| {
        switch (err) {
            zai.ZaiError.OutOfMemory => {
                std.debug.print("Out of memory\n", .{});
                return err;
            },
            zai.ZaiError.ApiError => {
                std.debug.print("API Error (possibly invalid credentials)\n", .{});
                return err;
            },
            zai.ZaiError.NetworkError => {
                std.debug.print("Network error (check your connection)\n", .{});
                return err;
            },
            else => {
                std.debug.print("Unexpected error: {s}\n", .{@errorName(err)});
                return err;
            },
        }
    };
    defer provider.deinit();

    // Rest of your code...
}
```

### Environment Variables

For security, it's often better to get API keys from environment variables:

```zig
const std = @import("std");
const zai = @import("zai");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get API key from environment
    const api_key = try std.process.getEnvVarOwned(allocator, "OPENAI_API_KEY");
    defer allocator.free(api_key);

    // Initialize provider
    const provider_config = zai.ProviderConfig{ .OpenAI = .{
        .api_key = api_key,
        .base_url = "https://api.openai.com/v1",
    }};

    var provider = try zai.init(allocator, provider_config);
    defer provider.deinit();

    // Rest of your code...
}
```

## Memory Management

zai follows Zig's explicit memory management principles:

1. The allocator must be passed to all allocating functions
2. The caller owns the response and must free it
3. Use `defer` for cleanup to avoid leaks
4. Provider instances must be deinit'd to free resources
5. Registry objects must be deinit'd to free all contained providers and models

```zig
// Example of proper memory management
var provider = try zai.init(allocator, config);
defer provider.deinit(); // Clean up provider resources

const response = try provider.chat(options);
defer allocator.free(response); // Clean up response memory
```
