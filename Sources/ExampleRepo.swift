import Foundation

enum ExampleRepo {
    /// User overlay, if present. Malformed files are ignored rather than
    /// silently wiping the bundled library.
    static func userPatch() -> UserExamplePatch? {
        let url = AppPaths.userResourceURL(name: "examples", extension: "json")
        guard let data = try? Data(contentsOf: url),
              let patch = try? JSONDecoder().decode(UserExamplePatch.self, from: data) else {
            return nil
        }
        return patch
    }

    /// Pure merge so it can be unit tested without touching the user's files.
    /// User entries win by id; `remove` disables a bundled example.
    static func merging(
        base: ExampleLibrary, patch: UserExamplePatch?
    ) -> ExampleLibrary {
        guard let patch = patch else { return base }
        var byID: [String: Example] = [:]
        for example in base.examples { byID[example.id] = example }
        for example in patch.examples ?? [] { byID[example.id] = example }
        for id in patch.remove ?? [] { byID.removeValue(forKey: id) }
        var merged = base
        merged.examples = byID.values.sorted { $0.id < $1.id }
        return merged
    }

    static func load() -> ExampleLibrary {
        let base: ExampleLibrary
        if let url = AppPaths.resourceURL(name: "examples", extension: "json"),
           let data = try? Data(contentsOf: url),
           let library = try? JSONDecoder().decode(ExampleLibrary.self, from: data) {
            base = library
        } else {
            base = ExampleLibrary(version: 1, examples: [])
        }
        return merging(base: base, patch: userPatch())
    }

    static func examples(for tool: String, in library: ExampleLibrary) -> [Example] {
        library.examples.filter { $0.tool == tool }
    }

    static func toolNames(in library: ExampleLibrary) -> Set<String> {
        Set(library.examples.map { $0.tool })
    }

    static func commandPreview(_ example: Example, values: [String: String]) -> String {
        let argv = (try? Runner.expandedArguments(example, values: values)) ?? example.argv
        return ([example.tool] + argv).joined(separator: " ")
    }

    /// Derives editable fields from `{{key}}` placeholders in argv elements, so
    /// users only have to type arguments, not a separate field schema.
    static func extractFields(_ argv: [String]) -> [ExampleField] {
        let pattern = try? NSRegularExpression(pattern: #"\{\{([A-Za-z0-9_]+)\}\}"#)
        var keys: [String] = []
        for argument in argv {
            guard let pattern = pattern else { break }
            let range = NSRange(argument.startIndex..., in: argument)
            for match in pattern.matches(in: argument, range: range) {
                guard let keyRange = Range(match.range(at: 1), in: argument) else { continue }
                let key = String(argument[keyRange])
                if !keys.contains(key) { keys.append(key) }
            }
        }
        return keys.map {
            ExampleField(key: $0, label: $0, value: "", hint: "运行时填写")
        }
    }

    /// Writes the user overlay. `to:` exists so tests can use a temp file.
    static func saveUserPatch(
        _ patch: UserExamplePatch,
        to url: URL = AppPaths.userResourceURL(name: "examples", extension: "json")
    ) throws {
        AppPaths.prepare()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(patch).write(to: url, options: [.atomic])
    }
}
