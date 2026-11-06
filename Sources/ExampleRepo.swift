import Foundation

enum ExampleRepo {
    static func load() -> ExampleLibrary {
        guard let url = AppPaths.resourceURL(name: "examples", extension: "json"),
              let data = try? Data(contentsOf: url),
              let library = try? JSONDecoder().decode(ExampleLibrary.self, from: data) else {
            return ExampleLibrary(version: 1, examples: [])
        }
        return library
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
