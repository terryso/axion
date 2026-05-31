import Foundation

struct TGCommandDef: Sendable {
    let name: String
    let description: String
    let helpText: String
    let menuPriority: Int
    let handler: @Sendable (Int64) async -> String
}

struct TGCommandRegistry: Sendable {
    private let commands: [String: TGCommandDef]
    private let ordered: [TGCommandDef]

    init(commands: [TGCommandDef] = []) {
        var map: [String: TGCommandDef] = [:]
        for cmd in commands {
            if map[cmd.name] != nil {
                fputs("[axion] TGCommandRegistry: duplicate command name '\(cmd.name)' — last wins\n", stderr)
            }
            map[cmd.name] = cmd
        }
        self.commands = map
        self.ordered = commands.sorted { $0.menuPriority < $1.menuPriority }
    }

    func register(_ def: TGCommandDef) -> TGCommandRegistry {
        var defs = ordered
        defs.append(def)
        return TGCommandRegistry(commands: defs)
    }

    func resolve(_ raw: String) -> TGCommandDef? {
        let normalized = Self.normalize(raw)
        return commands[normalized]
    }

    func allCommands() -> [TGCommandDef] {
        ordered
    }

    func menuCommands(limit: Int = 100) -> [(name: String, description: String)] {
        ordered
            .filter { $0.menuPriority > 0 }
            .prefix(limit)
            .map { (name: $0.name, description: $0.description) }
    }

    static func normalize(_ raw: String) -> String {
        var s = raw
        if s.hasPrefix("/") { s.removeFirst() }
        if let atIdx = s.firstIndex(of: "@") {
            s = String(s[..<atIdx])
        }
        s = s.lowercased()
        s = s.replacingOccurrences(of: "-", with: "_")
        return s
    }
}
