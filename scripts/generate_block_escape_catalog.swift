// Build with:
// swiftc -O -D BLOCK_ESCAPE_CATALOG_TOOL \
//   wits/SeededRandomNumberGenerator.swift wits/BlockEscape.swift \
//   scripts/generate_block_escape_catalog.swift -o /tmp/generate-block-escape-catalog
//
// Then run:
// /tmp/generate-block-escape-catalog wits/BlockEscapeBoards.bin

import Foundation

private struct Recipe {
    let name: String
    let spec: KlotskiSpec
    let depths: ClosedRange<Int>
    let seed: UInt64
}

@main
private enum BlockEscapeCatalogGenerator {
    private static let boardsPerBand = 2_500
    private static let recipes = [
        Recipe(name: "easy",
               spec: KlotskiSpec(width: 4, height: 4,
                                 verticals: 1, horizontals: 1, singles: 2),
               depths: 4...10,
               seed: 0xE45A_1001),
        Recipe(name: "medium",
               spec: KlotskiSpec(width: 4, height: 5,
                                 verticals: 3, horizontals: 2, singles: 3),
               depths: 12...27,
               seed: 0xE45A_2002),
        Recipe(name: "hard",
               spec: KlotskiSpec(width: 4, height: 5,
                                 verticals: 3, horizontals: 2, singles: 3),
               depths: 28...48,
               seed: 0xE45A_3003),
        Recipe(name: "extra hard",
               spec: KlotskiSpec(width: 4, height: 5,
                                 verticals: 4, horizontals: 1, singles: 4),
               depths: 35...77,
               seed: 0xE45A_4004),
    ]

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw CatalogError.usage
        }

        var bytes = Array("WITSBE01".utf8)
        for recipe in recipes {
            let entries = KlotskiEngine.catalogEntries(spec: recipe.spec,
                                                        depths: recipe.depths,
                                                        count: boardsPerBand,
                                                        seed: recipe.seed)
            append(UInt32(entries.count), to: &bytes)
            for entry in entries {
                append(entry.key.a, to: &bytes)
                append(entry.key.b, to: &bytes)
                bytes.append(UInt8(entry.depth))
            }
            print("\(recipe.name): \(entries.count) boards, depth \(recipe.depths)")
        }

        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try Data(bytes).write(to: output, options: .atomic)
        print("wrote \(bytes.count) bytes to \(output.path)")
    }

    private static func append<T: FixedWidthInteger>(_ value: T,
                                                     to bytes: inout [UInt8]) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes.append(contentsOf: $0) }
    }

    private enum CatalogError: Error, CustomStringConvertible {
        case usage

        var description: String {
            "usage: generate-block-escape-catalog <output.bin>"
        }
    }
}
