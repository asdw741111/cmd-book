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
}
