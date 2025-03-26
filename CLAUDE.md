# zai - Zig AI Library: Development Guidelines

## Build Commands
- Build all: `zig build`
- Build CLI: `zig build cli`
- Build specific example: `zig build chat-openai` or `zig build chat-bedrock`
- Install CLI: `zig build cli install -Doptimize=ReleaseFast --prefix ~/.local`

## Code Style Guidelines
- **Imports**: Group at top of file. Standard import: `const std = @import("std");`
- **Naming**: Types/Structs: PascalCase, Functions: camelCase, Variables/Constants: snake_case
- **Error Handling**: Use `try` for propagation, detailed error types with comprehensive switch statements
- **Memory**: Pass `allocator: std.mem.Allocator` explicitly, use `defer` for cleanup
- **Documentation**: Document public APIs and memory ownership

## Organization
- Provider-based architecture with vtables for unified interface
- Clear separation between core functionality and provider implementations
- Feature support varies by provider (see README feature matrix)

## Requirements
- Zig 0.13.0 required

## Reference Files
- **USAGE.md**: Contains detailed usage instructions and documentation for the zai library

## CLI Testing Workflow
- Build the CLI: `zig build cli`
- Run the CLI directly: `./zig-out/bin/zai <command> [options] [prompt]`
- Test with piped input: `cat file.txt | ./zig-out/bin/zai chat "Your prompt"`
- Important: Do NOT run via `zig build cli -- <args>` as that doesn't execute the binary correctly