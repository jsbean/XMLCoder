//
//  NestedEnumAssociatedValueTest.swift
//  XMLCoderTests
//
//  Created by James Bean on 7/11/19.
//

import XCTest
import XMLCoder

private struct Container: Decodable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case paragraphs = "p"
    }
    let paragraphs: [Paragraph]
}

private struct Paragraph: Decodable, Equatable {
    let entries: [Entry]

    init(entries: [Entry]) {
        self.entries = entries
    }
}

private enum Entry: Decodable, Equatable {
    case run(Run)
    case properties(Properties)
    case br(Break)

    private enum CodingKeys: String, CodingKey {
        case run, properties, br
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            self = .run(try container.decode(Run.self, forKey: .run))
        } catch DecodingError.keyNotFound {
            do {
                self = .properties(try container.decode(Properties.self, forKey: .properties))
            } catch DecodingError.keyNotFound {
                self = .br(try container.decode(Break.self, forKey: .br))
            }
        }
    }
}

private struct Run: Decodable, Equatable {
    let id: Int
    let text: String
}

private struct Properties: Decodable, Equatable {
    let id: Int
    let title: String
}

private struct Break: Decodable, Equatable { }

class NestedEnumAssociatedValueTest: XCTestCase {

    func testNestedEnums() throws {
        let xml = """
        <container>
            <p>
                <run>
                    <id>1518</id>
                    <text>I am answering it again.</text>
                </run>
                <properties>
                    <id>431</id>
                    <title>A Word About Wake Times</title>
                </properties>
                <br />
            </p>
            <p>
                <run>
                    <id>1519</id>
                    <text>I am answering it again.</text>
                </run>
            </p>
        </container>
        """
        let result = try XMLDecoder().decode(Container.self, from: xml.data(using: .utf8)!)
        let expected = Container(
            paragraphs: [
                Paragraph(
                    entries: [
                        .run(Run(id: 1518, text: "I am answering it again.")),
                        .properties(Properties(id: 431, title: "A Word About Wake Times")),
                        .br(Break())
                    ]
                ),
                Paragraph(
                    entries: [
                        .run(Run(id: 1519, text: "I am answering it again."))
                    ]
                )
            ]
        )
        XCTAssertEqual(result, expected)
    }
}
