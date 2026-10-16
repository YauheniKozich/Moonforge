# SwiftLint Setup for Moonforge

## Overview

This project uses [SwiftLint](https://github.com/realm/SwiftLint) to enforce Swift style and conventions.

## Installation

### Homebrew (Recommended)

```bash
brew install swiftlint
```

### Mint

```bash
mint install realm/SwiftLint
```

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/realm/SwiftLint.git", from: "0.53.0")
]
```

## Usage

### Manual

```bash
# Lint all files
swiftlint lint

# Lint with auto-fix
swiftlint lint --fix

# Lint specific file
swiftlint lint path/to/file.swift

# Show all rules
swiftlint rules
```

### Xcode Integration

### Build Phase (Recommended)

SwiftLint build phase уже добавлен в проект. Для активации:

1. В Xcode выберите проект Moonforge
2. Перейдите в "Build Phases"
3. Найдите "SwiftLint" phase
4. Убедитесь, что он стоит перед "Compile Sources"

**Важно:** В Xcode 26+ может потребоваться отключить sandbox для Run Script phases:

```bash
# Временно отключить sandbox для тестирования
defaults write com.apple.dt.Xcode IDEBuildOperationMaxNumberOfConcurrentCompileTasks -int 1
```

### Альтернатива: Ручной запуск

```bash
# В терминале из папки проекта
swiftlint lint

# С авто-исправлением
swiftlint --fix
```

### Swift Package Plugin

Add to your `Package.swift`:

```swift
plugins: [
    .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLint")
]
```

## Configuration

See `.swiftlint.yml` for project-specific rules.

### Key Rules

- **Line Length**: Warning at 150 chars, Error at 200 chars
- **File Length**: Warning at 600 lines, Error at 1000 lines
- **Function Length**: Warning at 60 lines, Error at 120 lines
- **Identifier Names**: Min 1 char, Max 70 chars
- **Trailing Whitespace**: Warning (ignored in empty lines)
- **Vertical Whitespace**: Max 3 empty lines

### Disabled Rules

- `todo` - Allow TODO comments
- `force_try` - Sometimes necessary
- `force_cast` - Sometimes necessary with checks
- `implicitly_unwrapped_optional` - Needed for testing

### Custom Rules

- **No Print Statements**: Use Logger protocol instead of `print()` in production code

## IDE Integration

### VS Code

Install the [SwiftLint extension](https://marketplace.visualstudio.com/items?itemName=vknabel.vscode-swiftlint)

### AppCode

Built-in support:
1. Go to Preferences → Editor → Inspections
2. Enable SwiftLint

### Xcode

See "Build Phase" section above for real-time feedback.

## CI/CD Integration

### GitHub Actions

```yaml
- name: SwiftLint
  run: swiftlint lint --strict
```

### Bitrise

```yaml
- swiftlint:
    config_file: .swiftlint.yml
    fail_on_warnings: true
```

## Suppressing Violations

### Single Line

```swift
// swiftlint:disable:next line_length
let longLine = "This is a very long line that exceeds the limit but is intentionally disabled"
```

### Multiple Lines

```swift
// swiftlint:disable:next force_try
let result = try! fetchData()
```

### File-wide

```swift
// swiftlint:disable force_cast
// File content with force casts
// swiftlint:enable force_cast
```

## Rules Reference

Full list of rules: https://realm.github.io/SwiftLint/rule-directory.html

### Correctness Rules (Enabled)
- `empty_count`
- `first_where`
- `joined_default_parameter`

### Style Rules (Enabled)
- `colon`
- `comma`
- `control_statement`
- `trailing_whitespace`
- `trailing_newline`
- `trailing_comma`
- `vertical_whitespace`

### Performance Rules (Enabled)
- `legacy_random`
- `reduce_into`

### Readability Rules (Enabled)
- `redundant_nil_coalescing`
- `redundant_type_annotation`
- `static_operator`
- `unneeded_parentheses_in_closure_argument`

## Troubleshooting

### "Command PhaseScriptExecution failed"

Make sure SwiftLint is installed:
```bash
brew install swiftlint
```

### Too many violations

Run with auto-fix:
```bash
swiftlint lint --fix
```

### Rule not working

Check if it's in `disabled_rules` in `.swiftlint.yml`

## Version

SwiftLint version: 0.53.0+
Configuration version: 1.0

## License

This configuration is part of the Moonforge project.
