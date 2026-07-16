// Build with:
// swiftc -O -D BLOCK_ESCAPE_CATALOG_TOOL \
//   wits/SeededRandomNumberGenerator.swift wits/BlockEscape.swift \
//   scripts/audit_block_escape_catalog.swift -o /tmp/audit-block-escape-catalog
//
// Then run:
// /tmp/audit-block-escape-catalog wits/BlockEscapeBoards.bin

import Foundation

@main
private enum BlockEscapeCatalogAudit {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw AuditError.usage }
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let data = try Data(contentsOf: url)
        let catalog = try KlotskiEngine.catalog(from: data)

        precondition(catalog.count == KlotskiDifficultyBand.allCases.count)
        for band in KlotskiDifficultyBand.allCases {
            let entries = catalog[band.rawValue]
            precondition(entries.count == KlotskiEngine.boardsPerBand)
            precondition(Set(entries.map(\.key)).count == entries.count)
            precondition(entries.allSatisfy { band.catalogDepths.contains($0.depth) })

            let sampledKeys = Set((0..<1_000).map { seed -> KlotskiEngine.Key in
                var rng = SeededRandomNumberGenerator(seed: UInt64(seed))
                return entries[Int(rng.next() % UInt64(entries.count))].key
            })
            precondition(sampledKeys.count > 700)

            for entry in entries {
                let board = KlotskiEngine.decode(entry.key,
                                                  width: band.spec.width,
                                                  height: band.spec.height)
                precondition(!board.isSolved)
                precondition(KlotskiEngine.key(board) == entry.key)
            }

            let depths = entries.map(\.depth)
            print("\(band.title): \(entries.count) unique boards, depth \(depths.min()!)...\(depths.max()!)")
        }
        print("catalog audit passed (\(catalog.flatMap { $0 }.count) boards, \(data.count) bytes)")
    }

    private enum AuditError: Error, CustomStringConvertible {
        case usage

        var description: String {
            "usage: audit-block-escape-catalog <catalog.bin>"
        }
    }
}
