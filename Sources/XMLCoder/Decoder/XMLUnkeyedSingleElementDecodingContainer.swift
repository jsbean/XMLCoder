//
//  XMLUnkeyedSingleElementDecodingContainer.swift
//  XMLCoder
//
//  Created by James Bean on 7/19/19.
//

/// Container specialized for decoding an unkeyed container of XML single element boxes (which could either be a nested unkeyed
/// containers, or choice elements).
struct XMLUnkeyedSingleElementDecodingContainer: UnkeyedDecodingContainer {

    // MARK: Properties

    /// A reference to the decoder we're reading from.
    private let decoder: XMLDecoderImplementation

    /// A reference to the container we're reading from.
    private let container: SharedBox<[SingleElementBox]>

    /// The path of coding keys taken to get to this point in decoding.
    public private(set) var codingPath: [CodingKey]

    /// The index of the element we're about to decode.
    public private(set) var currentIndex: Int

    // MARK: - Initialization

    /// Initializes `self` by referencing the given decoder and container.
    init(referencing decoder: XMLDecoderImplementation, wrapping container: SharedBox<[SingleElementBox]>) {
        self.decoder = decoder
        self.container = container
        codingPath = decoder.codingPath
        currentIndex = 0
    }

    // MARK: - UnkeyedDecodingContainer Methods

    public var count: Int? {
        return container.withShared { unkeyedBox in
            unkeyedBox.count
        }
    }

    public var isAtEnd: Bool {
        return currentIndex >= count!
    }

    public mutating func decodeNil() throws -> Bool {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(Any?.self, DecodingError.Context(
                codingPath: decoder.codingPath + [XMLKey(index: self.currentIndex)],
                debugDescription: "Unkeyed container is at end."
            ))
        }

        let isNull = container.withShared { unkeyedBox in
            unkeyedBox[self.currentIndex].isNull
        }

        if isNull {
            currentIndex += 1
            return true
        } else {
            return false
        }
    }

    public mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        return try decode(type) { decoder, box in
            try decoder.unbox(box)
        }
    }

    private mutating func decode<T: Decodable>(
        _ type: T.Type,
        decode: (XMLDecoderImplementation, Box) throws -> T?
    ) throws -> T {
        guard let strategy = self.decoder.nodeDecodings.last else {
            preconditionFailure("Attempt to access node decoding strategy from empty stack.")
        }
        decoder.codingPath.append(XMLKey(index: currentIndex))
        let nodeDecodings = decoder.options.nodeDecodingStrategy.nodeDecodings(
            forType: T.self,
            with: decoder
        )
        decoder.nodeDecodings.append(nodeDecodings)
        defer {
            _ = decoder.nodeDecodings.removeLast()
            _ = decoder.codingPath.removeLast()
        }
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(
                codingPath: decoder.codingPath + [XMLKey(index: self.currentIndex)],
                debugDescription: "Unkeyed container is at end."
            ))
        }

        decoder.codingPath.append(XMLKey(index: currentIndex))
        defer { self.decoder.codingPath.removeLast() }

        let box = container.withShared { unkeyedBox in
            unkeyedBox[self.currentIndex]
        }

        var value: T?
        do {
            // Drill down to the element in the case of an nested unkeyed element
            value = try decode(decoder, box.element)
        } catch {
            // Specialize for choice elements
            value = try decode(decoder, ChoiceBox(key: box.key, element: box.element))
        }

        defer { currentIndex += 1 }

        if value == nil, let type = type as? AnyOptional.Type,
            let result = type.init() as? T {
            return result
        }

        guard let decoded: T = value else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(
                codingPath: decoder.codingPath + [XMLKey(index: self.currentIndex)],
                debugDescription: "Expected \(type) but found null instead."
            ))
        }

        return decoded
    }

    public mutating func nestedContainer<NestedKey>(
        keyedBy nestedType: NestedKey.Type
    ) throws -> KeyedDecodingContainer<NestedKey> {
        fatalError()
    }

    public mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        fatalError()
    }

    public mutating func superDecoder() throws -> Decoder {
        decoder.codingPath.append(XMLKey(index: currentIndex))
        defer { self.decoder.codingPath.removeLast() }

        guard !isAtEnd else {
            throw DecodingError.valueNotFound(Decoder.self, DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Cannot get superDecoder() -- unkeyed container is at end."
            ))
        }

        let value = container.withShared { unkeyedBox in
            unkeyedBox[self.currentIndex]
        }
        currentIndex += 1

        return XMLDecoderImplementation(
            referencing: value,
            options: decoder.options,
            nodeDecodings: decoder.nodeDecodings,
            codingPath: decoder.codingPath
        )
    }
}
