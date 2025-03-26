const std = @import("std");
const zai = @import("zai");
const config_path = @import("config_path.zig");

pub const ShellType = enum {
    fish,
    bash,
    zsh,

    pub fn fromString(str: []const u8) !ShellType {
        if (std.mem.eql(u8, str, "fish")) return .fish;
        if (std.mem.eql(u8, str, "bash")) return .bash;
        if (std.mem.eql(u8, str, "zsh")) return .zsh;
        return error.InvalidShellType;
    }
};

pub const CompletionOptions = struct {
    shell: ShellType,
    install: bool = false,
    list_providers: bool = false,
    list_models: bool = false,
    list_prompts: bool = false,
    provider_filter: ?[]const u8 = null,
};

/// Parses arguments specifically for the completions command
pub fn parseCompletionArgs(allocator: std.mem.Allocator, args: []const []const u8) !CompletionOptions {
    if (args.len < 3) {
        return error.MissingShellType;
    }

    var options = CompletionOptions{
        .shell = try ShellType.fromString(args[2]),
        .install = false,
        .list_providers = false,
        .list_models = false,
        .list_prompts = false,
        .provider_filter = null,
    };

    var i: usize = 3;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--install")) {
            options.install = true;
        } else if (std.mem.eql(u8, arg, "--list-providers")) {
            options.list_providers = true;
        } else if (std.mem.eql(u8, arg, "--list-models")) {
            options.list_models = true;
            // Check for provider filter
            if (i + 1 < args.len and !std.mem.startsWith(u8, args[i + 1], "--")) {
                options.provider_filter = try allocator.dupe(u8, args[i + 1]);
                i += 1;
            }
        } else if (std.mem.eql(u8, arg, "--list-prompts")) {
            options.list_prompts = true;
        } else {
            return error.InvalidOption;
        }
    }

    return options;
}

/// Get the default installation path for completion files
fn getDefaultInstallPath(allocator: std.mem.Allocator, shell: ShellType) ![]const u8 {
    // Get user's home directory
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch |err| {
        std.debug.print("Error getting HOME environment variable: {}\n", .{err});
        return error.HomeNotFound;
    };
    defer allocator.free(home);

    return switch (shell) {
        .fish => try std.fmt.allocPrint(allocator, "{s}/.config/fish/completions/zai.fish", .{home}),
        .bash => try std.fmt.allocPrint(allocator, "{s}/.local/share/bash-completion/completions/zai", .{home}),
        .zsh => try std.fmt.allocPrint(allocator, "{s}/.zsh/completions/_zai", .{home}),
    };
}

/// List providers for completion
fn listProviders(allocator: std.mem.Allocator) !void {
    const config_file = try config_path.getConfigPath(allocator);
    defer allocator.free(config_file);

    var registry = try zai.Registry.loadFromFile(allocator, config_file);
    defer registry.deinit();

    const stdout = std.io.getStdOut().writer();
    for (registry.providers.items) |provider| {
        try stdout.print("{s}\n", .{provider.name});
    }
}

/// List models for completion
fn listModels(allocator: std.mem.Allocator, provider_filter: ?[]const u8) !void {
    const config_file = try config_path.getConfigPath(allocator);
    defer allocator.free(config_file);

    var registry = try zai.Registry.loadFromFile(allocator, config_file);
    defer registry.deinit();

    const stdout = std.io.getStdOut().writer();
    for (registry.providers.items) |provider| {
        if (provider_filter) |filter| {
            if (!std.mem.eql(u8, provider.name, filter)) {
                continue;
            }
        }

        for (provider.models) |model| {
            try stdout.print("{s}\n", .{model.name});
        }
    }
}

/// List prompts for completion
fn listPrompts(allocator: std.mem.Allocator) !void {
    const config_file = try config_path.getConfigPath(allocator);
    defer allocator.free(config_file);

    var registry = try zai.Registry.loadFromFile(allocator, config_file);
    defer registry.deinit();

    const stdout = std.io.getStdOut().writer();
    for (registry.prompts.items) |prompt| {
        try stdout.print("{s}\n", .{prompt.name});
    }
}

/// Generate fish shell completion script
fn generateFishCompletions(allocator: std.mem.Allocator) ![]const u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    
    const writer = buffer.writer();
    
    try writer.writeAll(
        \\# zai fish completion script
        \\
        \\# Define the main command completions
        \\complete -c zai -f
        \\
        \\# Main commands
        \\complete -c zai -n "__fish_use_subcommand" -a "chat" -d "Start a chat with the AI"
        \\complete -c zai -n "__fish_use_subcommand" -a "completion" -d "Get a completion from the AI"
        \\complete -c zai -n "__fish_use_subcommand" -a "embedding" -d "Get embeddings for text"
        \\complete -c zai -n "__fish_use_subcommand" -a "provider" -d "Manage AI providers"
        \\complete -c zai -n "__fish_use_subcommand" -a "models" -d "Manage provider models"
        \\complete -c zai -n "__fish_use_subcommand" -a "prompt" -d "Manage system and user prompts"
        \\complete -c zai -n "__fish_use_subcommand" -a "completions" -d "Generate shell completion scripts"
        \\
        \\# completions subcommand
        \\complete -c zai -n "__fish_seen_subcommand_from completions" -a "fish" -d "Generate fish shell completions"
        \\complete -c zai -n "__fish_seen_subcommand_from completions" -a "bash" -d "Generate bash shell completions"
        \\complete -c zai -n "__fish_seen_subcommand_from completions" -a "zsh" -d "Generate zsh shell completions"
        \\complete -c zai -n "__fish_seen_subcommand_from completions" -l install -d "Install completions to default location"
        \\
        \\# chat command options
        \\complete -c zai -n "__fish_seen_subcommand_from chat" -l provider -a "(zai completions fish --list-providers)" -d "Select AI provider"
        \\complete -c zai -n "__fish_seen_subcommand_from chat" -l model -a "(zai completions fish --list-models)" -d "Select specific model"
        \\complete -c zai -n "__fish_seen_subcommand_from chat" -l system-message -d "Set system message for chat"
        \\complete -c zai -n "__fish_seen_subcommand_from chat" -l stream -a "true false" -d "Enable/disable streaming"
        \\
        \\# completion command options
        \\complete -c zai -n "__fish_seen_subcommand_from completion" -l provider -a "(zai completions fish --list-providers)" -d "Select AI provider"
        \\complete -c zai -n "__fish_seen_subcommand_from completion" -l model -a "(zai completions fish --list-models)" -d "Select specific model"
        \\complete -c zai -n "__fish_seen_subcommand_from completion" -l stream -a "true false" -d "Enable/disable streaming"
        \\
        \\# embedding command options
        \\complete -c zai -n "__fish_seen_subcommand_from embedding" -l provider -a "(zai completions fish --list-providers)" -d "Select AI provider"
        \\complete -c zai -n "__fish_seen_subcommand_from embedding" -l model -a "(zai completions fish --list-models)" -d "Select specific model"
        \\
        \\# provider subcommands
        \\complete -c zai -n "__fish_seen_subcommand_from provider; and not __fish_seen_subcommand_from list add remove set-default" -a "list" -d "List all configured providers"
        \\complete -c zai -n "__fish_seen_subcommand_from provider; and not __fish_seen_subcommand_from list add remove set-default" -a "add" -d "Add a new provider"
        \\complete -c zai -n "__fish_seen_subcommand_from provider; and not __fish_seen_subcommand_from list add remove set-default" -a "remove" -d "Remove a provider"
        \\complete -c zai -n "__fish_seen_subcommand_from provider; and not __fish_seen_subcommand_from list add remove set-default" -a "set-default" -d "Set the default provider"
        \\
        \\# provider remove/set-default completions
        \\complete -c zai -n "__fish_seen_subcommand_from provider; and __fish_seen_subcommand_from remove" -a "(zai completions fish --list-providers)" -d "Provider to remove"
        \\complete -c zai -n "__fish_seen_subcommand_from provider; and __fish_seen_subcommand_from set-default" -a "(zai completions fish --list-providers)" -d "Provider to set as default"
        \\
        \\# models subcommands
        \\complete -c zai -n "__fish_seen_subcommand_from models; and not __fish_seen_subcommand_from list add set-prompt clear-prompt" -a "list" -d "List all models from all providers"
        \\complete -c zai -n "__fish_seen_subcommand_from models; and not __fish_seen_subcommand_from list add set-prompt clear-prompt" -a "add" -d "Add a model to a provider"
        \\complete -c zai -n "__fish_seen_subcommand_from models; and not __fish_seen_subcommand_from list add set-prompt clear-prompt" -a "set-prompt" -d "Set default prompt for a model"
        \\complete -c zai -n "__fish_seen_subcommand_from models; and not __fish_seen_subcommand_from list add set-prompt clear-prompt" -a "clear-prompt" -d "Clear default prompt for a model"
        \\
        \\# models add provider completion
        \\complete -c zai -n "__fish_seen_subcommand_from models; and __fish_seen_subcommand_from add; and __fish_is_nth_token 3" -a "(zai completions fish --list-providers)" -d "Provider to add model to"
        \\
        \\# models set-prompt/clear-prompt provider completion
        \\complete -c zai -n "__fish_seen_subcommand_from models; and __fish_seen_subcommand_from set-prompt; and __fish_is_nth_token 3" -a "(zai completions fish --list-providers)" -d "Provider for model"
        \\complete -c zai -n "__fish_seen_subcommand_from models; and __fish_seen_subcommand_from clear-prompt; and __fish_is_nth_token 3" -a "(zai completions fish --list-providers)" -d "Provider for model"
        \\
        \\# models set-prompt/clear-prompt model completion
        \\complete -c zai -n "__fish_seen_subcommand_from models; and __fish_seen_subcommand_from set-prompt; and __fish_is_nth_token 4" -a '(set -l cmd (commandline -poc); zai completions fish --list-models "$cmd[3]")' -d "Model name"
        \\complete -c zai -n "__fish_seen_subcommand_from models; and __fish_seen_subcommand_from clear-prompt; and __fish_is_nth_token 4" -a '(set -l cmd (commandline -poc); zai completions fish --list-models "$cmd[3]")' -d "Model name"
        \\
        \\# models set-prompt prompt completion
        \\complete -c zai -n "__fish_seen_subcommand_from models; and __fish_seen_subcommand_from set-prompt; and __fish_is_nth_token 5" -a "(zai completions fish --list-prompts)" -d "Prompt name"
        \\
        \\# prompt subcommands
        \\complete -c zai -n "__fish_seen_subcommand_from prompt; and not __fish_seen_subcommand_from list get add update remove import" -a "list" -d "List all prompts"
        \\complete -c zai -n "__fish_seen_subcommand_from prompt; and not __fish_seen_subcommand_from list get add update remove import" -a "get" -d "Show content of a specific prompt"
        \\complete -c zai -n "__fish_seen_subcommand_from prompt; and not __fish_seen_subcommand_from list get add update remove import" -a "add" -d "Add a new prompt"
        \\complete -c zai -n "__fish_seen_subcommand_from prompt; and not __fish_seen_subcommand_from list get add update remove import" -a "update" -d "Update an existing prompt"
        \\complete -c zai -n "__fish_seen_subcommand_from prompt; and not __fish_seen_subcommand_from list get add update remove import" -a "remove" -d "Remove a prompt"
        \\complete -c zai -n "__fish_seen_subcommand_from prompt; and not __fish_seen_subcommand_from list get add update remove import" -a "import" -d "Import prompt content from a file"
        \\
        \\# prompt get/update/remove/import prompt completion
        \\complete -c zai -n "__fish_seen_subcommand_from prompt; and __fish_seen_subcommand_from get" -a "(zai completions fish --list-prompts)" -d "Prompt name"
        \\complete -c zai -n "__fish_seen_subcommand_from prompt; and __fish_seen_subcommand_from update" -a "(zai completions fish --list-prompts)" -d "Prompt name"
        \\complete -c zai -n "__fish_seen_subcommand_from prompt; and __fish_seen_subcommand_from remove" -a "(zai completions fish --list-prompts)" -d "Prompt name"
        \\complete -c zai -n "__fish_seen_subcommand_from prompt; and __fish_seen_subcommand_from import" -a "(zai completions fish --list-prompts)" -d "Prompt name"
        \\
        \\# prompt add/update/import options
        \\complete -c zai -n "__fish_seen_subcommand_from prompt; and __fish_contains_opt -s type" -a "system user" -d "Prompt type"
        \\
    );

    return try buffer.toOwnedSlice();
}

/// Generate bash shell completion script
fn generateBashCompletions(allocator: std.mem.Allocator) ![]const u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    
    const writer = buffer.writer();
    
    try writer.writeAll(
        \\# zai bash completion script
        \\
        \\_zai() {
        \\    local cur prev words cword split
        \\    _init_completion -s || return
        \\
        \\    local commands="chat completion embedding provider models prompt completions"
        \\    local provider_cmds="list add remove set-default"
        \\    local models_cmds="list add set-prompt clear-prompt"
        \\    local prompt_cmds="list get add update remove import"
        \\    local completions_cmds="fish bash zsh"
        \\
        \\    # Handle main commands
        \\    if [[ $cword -eq 1 ]]; then
        \\        COMPREPLY=($(compgen -W "$commands" -- "$cur"))
        \\        return
        \\    fi
        \\
        \\    # Handle subcommands and options based on the main command
        \\    case "${words[1]}" in
        \\        chat)
        \\            case "$prev" in
        \\                --provider)
        \\                    COMPREPLY=($(compgen -W "$(zai completions bash --list-providers)" -- "$cur"))
        \\                    return
        \\                    ;;
        \\                --model)
        \\                    COMPREPLY=($(compgen -W "$(zai completions bash --list-models)" -- "$cur"))
        \\                    return
        \\                    ;;
        \\                --stream)
        \\                    COMPREPLY=($(compgen -W "true false" -- "$cur"))
        \\                    return
        \\                    ;;
        \\            esac
        \\
        \\            if [[ "$cur" == -* ]]; then
        \\                COMPREPLY=($(compgen -W "--provider --model --system-message --stream" -- "$cur"))
        \\                return
        \\            fi
        \\            ;;
        \\
        \\        completion)
        \\            case "$prev" in
        \\                --provider)
        \\                    COMPREPLY=($(compgen -W "$(zai completions bash --list-providers)" -- "$cur"))
        \\                    return
        \\                    ;;
        \\                --model)
        \\                    COMPREPLY=($(compgen -W "$(zai completions bash --list-models)" -- "$cur"))
        \\                    return
        \\                    ;;
        \\                --stream)
        \\                    COMPREPLY=($(compgen -W "true false" -- "$cur"))
        \\                    return
        \\                    ;;
        \\            esac
        \\
        \\            if [[ "$cur" == -* ]]; then
        \\                COMPREPLY=($(compgen -W "--provider --model --stream" -- "$cur"))
        \\                return
        \\            fi
        \\            ;;
        \\
        \\        embedding)
        \\            case "$prev" in
        \\                --provider)
        \\                    COMPREPLY=($(compgen -W "$(zai completions bash --list-providers)" -- "$cur"))
        \\                    return
        \\                    ;;
        \\                --model)
        \\                    COMPREPLY=($(compgen -W "$(zai completions bash --list-models)" -- "$cur"))
        \\                    return
        \\                    ;;
        \\            esac
        \\
        \\            if [[ "$cur" == -* ]]; then
        \\                COMPREPLY=($(compgen -W "--provider --model" -- "$cur"))
        \\                return
        \\            fi
        \\            ;;
        \\
        \\        provider)
        \\            if [[ $cword -eq 2 ]]; then
        \\                COMPREPLY=($(compgen -W "$provider_cmds" -- "$cur"))
        \\                return
        \\            fi
        \\
        \\            case "${words[2]}" in
        \\                remove|set-default)
        \\                    if [[ $cword -eq 3 ]]; then
        \\                        COMPREPLY=($(compgen -W "$(zai completions bash --list-providers)" -- "$cur"))
        \\                        return
        \\                    fi
        \\                    ;;
        \\            esac
        \\            ;;
        \\
        \\        models)
        \\            if [[ $cword -eq 2 ]]; then
        \\                COMPREPLY=($(compgen -W "$models_cmds" -- "$cur"))
        \\                return
        \\            fi
        \\
        \\            case "${words[2]}" in
        \\                add|set-prompt|clear-prompt)
        \\                    if [[ $cword -eq 3 ]]; then
        \\                        COMPREPLY=($(compgen -W "$(zai completions bash --list-providers)" -- "$cur"))
        \\                        return
        \\                    fi
        \\                    if [[ $cword -eq 4 && "${words[2]}" != "add" ]]; then
        \\                        COMPREPLY=($(compgen -W "$(zai completions bash --list-models ${words[3]})" -- "$cur"))
        \\                        return
        \\                    fi
        \\                    if [[ $cword -eq 5 && "${words[2]}" == "set-prompt" ]]; then
        \\                        COMPREPLY=($(compgen -W "$(zai completions bash --list-prompts)" -- "$cur"))
        \\                        return
        \\                    fi
        \\                    ;;
        \\            esac
        \\            ;;
        \\
        \\        prompt)
        \\            if [[ $cword -eq 2 ]]; then
        \\                COMPREPLY=($(compgen -W "$prompt_cmds" -- "$cur"))
        \\                return
        \\            fi
        \\
        \\            case "${words[2]}" in
        \\                get|update|remove|import)
        \\                    if [[ $cword -eq 3 ]]; then
        \\                        COMPREPLY=($(compgen -W "$(zai completions bash --list-prompts)" -- "$cur"))
        \\                        return
        \\                    fi
        \\                    ;;
        \\            esac
        \\
        \\            if [[ "$prev" == "--type" ]]; then
        \\                COMPREPLY=($(compgen -W "system user" -- "$cur"))
        \\                return
        \\            fi
        \\            ;;
        \\
        \\        completions)
        \\            if [[ $cword -eq 2 ]]; then
        \\                COMPREPLY=($(compgen -W "$completions_cmds" -- "$cur"))
        \\                return
        \\            fi
        \\
        \\            if [[ "$cur" == -* ]]; then
        \\                COMPREPLY=($(compgen -W "--install" -- "$cur"))
        \\                return
        \\            fi
        \\            ;;
        \\    esac
        \\
        \\    return 0
        \\}
        \\
        \\complete -F _zai zai
        \\
    );

    return try buffer.toOwnedSlice();
}

/// Generate zsh shell completion script
fn generateZshCompletions(allocator: std.mem.Allocator) ![]const u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    
    const writer = buffer.writer();
    
    try writer.writeAll(
        \\#compdef zai
        \\
        \\_zai() {
        \\  local -a commands
        \\  local -a provider_cmds
        \\  local -a models_cmds
        \\  local -a prompt_cmds
        \\  local -a completions_cmds
        \\
        \\  commands=(
        \\    'chat:Start a chat with the AI'
        \\    'completion:Get a completion from the AI'
        \\    'embedding:Get embeddings for text'
        \\    'provider:Manage AI providers'
        \\    'models:Manage provider models'
        \\    'prompt:Manage system and user prompts'
        \\    'completions:Generate shell completion scripts'
        \\  )
        \\
        \\  provider_cmds=(
        \\    'list:List all configured providers'
        \\    'add:Add a new provider'
        \\    'remove:Remove a provider'
        \\    'set-default:Set the default provider'
        \\  )
        \\
        \\  models_cmds=(
        \\    'list:List all models from all providers'
        \\    'add:Add a model to a provider'
        \\    'set-prompt:Set default prompt for a model'
        \\    'clear-prompt:Clear default prompt for a model'
        \\  )
        \\
        \\  prompt_cmds=(
        \\    'list:List all prompts'
        \\    'get:Show content of a specific prompt'
        \\    'add:Add a new prompt'
        \\    'update:Update an existing prompt'
        \\    'remove:Remove a prompt'
        \\    'import:Import prompt content from a file'
        \\  )
        \\
        \\  completions_cmds=(
        \\    'fish:Generate fish shell completions'
        \\    'bash:Generate bash shell completions'
        \\    'zsh:Generate zsh shell completions'
        \\  )
        \\
        \\  _arguments -C \
        \\    '1: :->command' \
        \\    '*:: :->args'
        \\
        \\  case $state in
        \\    (command)
        \\      _describe -t commands 'zai commands' commands
        \\      ;;
        \\    (args)
        \\      case $words[1] in
        \\        (chat)
        \\          _arguments \
        \\            '--provider=[Select AI provider]:provider:_zai_providers' \
        \\            '--model=[Select specific model]:model:_zai_models' \
        \\            '--system-message=[Set system message for chat]:message:' \
        \\            '--stream=[Enable/disable streaming]:boolean:(true false)'
        \\          ;;
        \\
        \\        (completion)
        \\          _arguments \
        \\            '--provider=[Select AI provider]:provider:_zai_providers' \
        \\            '--model=[Select specific model]:model:_zai_models' \
        \\            '--stream=[Enable/disable streaming]:boolean:(true false)'
        \\          ;;
        \\
        \\        (embedding)
        \\          _arguments \
        \\            '--provider=[Select AI provider]:provider:_zai_providers' \
        \\            '--model=[Select specific model]:model:_zai_models'
        \\          ;;
        \\
        \\        (provider)
        \\          if (( CURRENT == 2 )); then
        \\            _describe -t commands 'provider commands' provider_cmds
        \\          else
        \\            case $words[2] in
        \\              (remove|set-default)
        \\                _zai_providers
        \\                ;;
        \\            esac
        \\          fi
        \\          ;;
        \\
        \\        (models)
        \\          if (( CURRENT == 2 )); then
        \\            _describe -t commands 'models commands' models_cmds
        \\          else
        \\            case $words[2] in
        \\              (add|set-prompt|clear-prompt)
        \\                if (( CURRENT == 3 )); then
        \\                  _zai_providers
        \\                elif (( CURRENT == 4 )) && [[ $words[2] != "add" ]]; then
        \\                  _zai_models $words[3]
        \\                elif (( CURRENT == 5 )) && [[ $words[2] == "set-prompt" ]]; then
        \\                  _zai_prompts
        \\                fi
        \\                ;;
        \\            esac
        \\          fi
        \\          ;;
        \\
        \\        (prompt)
        \\          if (( CURRENT == 2 )); then
        \\            _describe -t commands 'prompt commands' prompt_cmds
        \\          else
        \\            case $words[2] in
        \\              (get|update|remove|import)
        \\                if (( CURRENT == 3 )); then
        \\                  _zai_prompts
        \\                fi
        \\                ;;
        \\            esac
        \\            
        \\            if [[ $words[(CURRENT-1)] == "--type" ]]; then
        \\              _values 'type' 'system' 'user'
        \\            fi
        \\          fi
        \\          ;;
        \\
        \\        (completions)
        \\          if (( CURRENT == 2 )); then
        \\            _describe -t commands 'completions commands' completions_cmds
        \\          else
        \\            _arguments '--install[Install completions to default location]'
        \\          fi
        \\          ;;
        \\      esac
        \\      ;;
        \\  esac
        \\}
        \\
        \\# Provider completion function
        \\_zai_providers() {
        \\  local -a providers
        \\  providers=(${(f)"$(zai completions zsh --list-providers 2>/dev/null)"})
        \\  _values 'providers' $providers
        \\}
        \\
        \\# Model completion function
        \\_zai_models() {
        \\  local -a models
        \\  if [[ -n "$1" ]]; then
        \\    models=(${(f)"$(zai completions zsh --list-models "$1" 2>/dev/null)"})
        \\  else
        \\    models=(${(f)"$(zai completions zsh --list-models 2>/dev/null)"})
        \\  fi
        \\  _values 'models' $models
        \\}
        \\
        \\# Prompt completion function
        \\_zai_prompts() {
        \\  local -a prompts
        \\  prompts=(${(f)"$(zai completions zsh --list-prompts 2>/dev/null)"})
        \\  _values 'prompts' $prompts
        \\}
        \\
        \\_zai
        \\
    );

    return try buffer.toOwnedSlice();
}

/// Handle the completions command
pub fn handleCompletions(allocator: std.mem.Allocator, cli_args: []const []const u8) !void {
    const stderr = std.io.getStdErr().writer();
    const stdout = std.io.getStdOut().writer();

    const options = parseCompletionArgs(allocator, cli_args) catch |err| {
        switch (err) {
            error.MissingShellType => {
                try stderr.writeAll("Missing shell type\n");
                try stderr.writeAll("Usage: zai completions <shell> [options]\n");
                try stderr.writeAll("\nSupported shells:\n");
                try stderr.writeAll("  fish    Fish shell\n");
                try stderr.writeAll("  bash    Bash shell\n");
                try stderr.writeAll("  zsh     Zsh shell\n");
                try stderr.writeAll("\nOptions:\n");
                try stderr.writeAll("  --install                Install completions to default location\n");
                try stderr.writeAll("  --list-providers         List available providers\n");
                try stderr.writeAll("  --list-models [provider] List available models\n");
                try stderr.writeAll("  --list-prompts           List available prompts\n");
                return;
            },
            error.InvalidShellType => {
                try stderr.writeAll("Invalid shell type\n");
                try stderr.writeAll("Supported shells: fish, bash, zsh\n");
                return err;
            },
            error.InvalidOption => {
                try stderr.writeAll("Invalid option\n");
                return err;
            },
            else => return err,
        }
    };
    defer if (options.provider_filter) |filter| allocator.free(filter);

    // Handle special flags for dynamic completions
    if (options.list_providers) {
        return try listProviders(allocator);
    }

    if (options.list_models) {
        return try listModels(allocator, options.provider_filter);
    }

    if (options.list_prompts) {
        return try listPrompts(allocator);
    }

    // Generate completions for the selected shell
    var completion_script: []const u8 = undefined;
    switch (options.shell) {
        .fish => completion_script = try generateFishCompletions(allocator),
        .bash => completion_script = try generateBashCompletions(allocator),
        .zsh => completion_script = try generateZshCompletions(allocator),
    }
    defer allocator.free(completion_script);

    // Install or output the completions
    if (options.install) {
        const install_path = try getDefaultInstallPath(allocator, options.shell);
        defer allocator.free(install_path);

        // Create the directory if it doesn't exist
        const dir_path = std.fs.path.dirname(install_path) orelse {
            try stderr.print("Invalid installation path: {s}\n", .{install_path});
            return error.InvalidPath;
        };

        std.fs.makeDirAbsolute(dir_path) catch |err| {
            if (err != error.PathAlreadyExists) {
                try stderr.print("Failed to create directory {s}: {s}\n", .{ dir_path, @errorName(err) });
                return err;
            }
        };

        // Write the file
        var file = try std.fs.createFileAbsolute(install_path, .{});
        defer file.close();
        try file.writeAll(completion_script);
        try stdout.print("Installed completion script to {s}\n", .{install_path});
    } else {
        // Just output to stdout
        try stdout.writeAll(completion_script);
    }
}

/// Print help text for the completions command
pub fn printCompletionsHelp() !void {
    const stderr = std.io.getStdErr().writer();
    try stderr.writeAll(
        \\Usage: zai completions <shell> [options]
        \\
        \\Generate shell completion scripts for zai.
        \\
        \\Supported shells:
        \\  fish    Fish shell
        \\  bash    Bash shell
        \\  zsh     Zsh shell
        \\
        \\Options:
        \\  --install            Install completions to default location
        \\
        \\Hidden options (used by completion scripts):
        \\  --list-providers     List available providers
        \\  --list-models        List available models
        \\  --list-prompts       List available prompts
        \\
        \\Examples:
        \\  # Generate fish completions and print to stdout
        \\  zai completions fish
        \\
        \\  # Install bash completions to default location
        \\  zai completions bash --install
        \\
        \\  # Generate zsh completions and save to a file
        \\  zai completions zsh > ~/.zsh/completions/_zai
        \\
    );
}