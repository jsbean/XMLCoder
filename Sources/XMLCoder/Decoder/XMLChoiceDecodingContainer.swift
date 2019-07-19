//
//  XMLChoiceDecodingContainer.swift
//  XMLCoder
//
//  Created by James Bean on 7/18/19.
//

import Foundation

struct XMLChoiceDecodingContainer<K: CodingKey>: KeyedDecodingContainerProtocol {
    typealias Key = K

    // MARK: Properties

    /// A reference to the decoder we're reading from.
    private let decoder: XMLDecoderImplementation

    /// A reference to the container we're reading from.
    private let container: SharedBox<SingleElementBox>

    /// The path of coding keys taken to get to this point in decoding.
    public private(set) var codingPath: [CodingKey]

    // MARK: - Initialization

    /// Initializes `self` by referencing the given decoder and container.
    init(referencing decoder: XMLDecoderImplementation, wrapping container: SharedBox<SingleElementBox>) {
        print("Single Element Container init: Key: \(container.unboxed.key)")
        self.decoder = decoder

        func mapKeys(
            _ container: SharedBox<SingleElementBox>, closure: (String) -> String
        ) -> SharedBox<SingleElementBox> {
            let attributes = container.withShared { singleElementBox in
                singleElementBox.attributes.map { (closure($0), $1) }
            }
            container.withShared { singleElementBox in
                //keyedBox.elements.map { (closure($0), $1) }
                singleElementBox.key = closure(singleElementBox.key)
            }
            //let keyedBox = KeyedBox(elements: elements, attributes: attributes)
            let singleElementBox = SingleElementBox(
                attributes: .init(),
                key: closure(container.withShared { $0.key }),
                element: container.withShared { $0.element }
            )

            return SharedBox(singleElementBox)
        }

        switch decoder.options.keyDecodingStrategy {
        case .useDefaultKeys:
            self.container = container
        case .convertFromSnakeCase:
            // Convert the snake case keys in the container to camel case.
            // If we hit a duplicate key after conversion, then we'll use the
            // first one we saw. Effectively an undefined behavior with dictionaries.
            self.container = mapKeys(container) { key in
                XMLDecoder.KeyDecodingStrategy._convertFromSnakeCase(key)
            }
        case .convertFromKebabCase:
            self.container = mapKeys(container) { key in
                XMLDecoder.KeyDecodingStrategy._convertFromKebabCase(key)
            }
        case .convertFromCapitalized:
            self.container = mapKeys(container) { key in
                XMLDecoder.KeyDecodingStrategy._convertFromCapitalized(key)
            }
        case let .custom(converter):
            self.container = mapKeys(container) { key in
                let codingPath = decoder.codingPath + [
                    XMLKey(stringValue: key, intValue: nil),
                ]
                return converter(codingPath).stringValue
            }
        }
        codingPath = decoder.codingPath
    }

    // MARK: - KeyedDecodingContainerProtocol Methods

    public var allKeys: [Key] {
        return container.withShared { Key(stringValue: $0.key) }.map { [$0] } ?? []
    }

    public func contains(_ key: Key) -> Bool {
        return container.withShared { $0.key == key.stringValue }
    }

    public func decodeNil(forKey key: Key) throws -> Bool {
        return container.withShared { $0.element.isNull }
    }

    public func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        guard container.withShared({ $0.key == key.stringValue }) else {
            throw DecodingError.typeMismatch(
                at: codingPath,
                expectation: type,
                reality: container
            )
        }
        return try decodeConcrete(type, forKey: key)
    }

    public func nestedContainer<NestedKey>(
        keyedBy keyType: NestedKey.Type, forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> {
        if keyType.self is XMLChoiceKey.Type {
            return try nestedSingleElementContainer(keyedBy: keyType, forKey: key)
        } else {
            return try nestedKeyedContainer(keyedBy: keyType, forKey: key)
        }
    }

    public func nestedKeyedContainer<NestedKey>(
        keyedBy _: NestedKey.Type, forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> {
        decoder.codingPath.append(key)
        defer { decoder.codingPath.removeLast() }

        let value = container.withShared { $0.element }
        let container: XMLKeyedDecodingContainer<NestedKey>

        if let keyedContainer = value as? SharedBox<KeyedBox> {
            container = XMLKeyedDecodingContainer<NestedKey>(
                referencing: decoder,
                wrapping: keyedContainer
            )
        } else if let keyedContainer = value as? KeyedBox {
            container = XMLKeyedDecodingContainer<NestedKey>(
                referencing: decoder,
                wrapping: SharedBox(keyedContainer)
            )
        } else {
            throw DecodingError.typeMismatch(
                at: codingPath,
                expectation: [String: Any].self,
                reality: value
            )
        }
        return KeyedDecodingContainer(container)
    }

    public func nestedSingleElementContainer<NestedKey>(
        keyedBy _: NestedKey.Type, forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> {
        decoder.codingPath.append(key)
        defer { decoder.codingPath.removeLast() }

        let value = container.withShared { $0.element }
        let container: XMLChoiceDecodingContainer<NestedKey>

        if let keyedContainer = value as? SharedBox<SingleElementBox> {
            container = XMLChoiceDecodingContainer<NestedKey>(
                referencing: decoder,
                wrapping: keyedContainer
            )
        } else if let keyedContainer = value as? SingleElementBox {
            container = XMLChoiceDecodingContainer<NestedKey>(
                referencing: decoder,
                wrapping: SharedBox(keyedContainer)
            )
        } else {
            throw DecodingError.typeMismatch(
                at: codingPath,
                expectation: [String: Any].self,
                reality: value
            )
        }
        return KeyedDecodingContainer(container)
    }

    public func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        decoder.codingPath.append(key)
        defer { decoder.codingPath.removeLast() }
        guard let unkeyedElement = container.withShared({ $0.element }) as? UnkeyedBox else {
            fatalError("Throw error instead")
        }
        return XMLUnkeyedDecodingContainer(
            referencing: decoder,
            wrapping: SharedBox(unkeyedElement)
        )

    }

    public func superDecoder() throws -> Decoder {
        return try _superDecoder(forKey: XMLKey.super)
    }

    public func superDecoder(forKey key: Key) throws -> Decoder {
        return try _superDecoder(forKey: key)
    }
}

/// Private functions
extension XMLChoiceDecodingContainer {
    private func _errorDescription(of key: CodingKey) -> String {
        switch decoder.options.keyDecodingStrategy {
        case .convertFromSnakeCase:
            // In this case we can attempt to recover the original value by
            // reversing the transform
            let original = key.stringValue
            let converted = XMLEncoder.KeyEncodingStrategy
                ._convertToSnakeCase(original)
            if converted == original {
                return "\(key) (\"\(original)\")"
            } else {
                return "\(key) (\"\(original)\"), converted to \(converted)"
            }
        default:
            // Otherwise, just report the converted string
            return "\(key) (\"\(key.stringValue)\")"
        }
    }

    private func decodeSignedInteger<T>(_ type: T.Type,
                                        forKey key: Key) throws -> T
        where T: BinaryInteger & SignedInteger & Decodable {
            return try decodeConcrete(type, forKey: key)
    }

    private func decodeUnsignedInteger<T>(_ type: T.Type,
                                          forKey key: Key) throws -> T
        where T: BinaryInteger & UnsignedInteger & Decodable {
            return try decodeConcrete(type, forKey: key)
    }

    private func decodeFloatingPoint<T>(_ type: T.Type,
                                        forKey key: Key) throws -> T
        where T: BinaryFloatingPoint & Decodable {
            return try decodeConcrete(type, forKey: key)
    }

    private func decodeConcrete<T: Decodable>(
        _ type: T.Type,
        forKey key: Key
    ) throws -> T {
        print("decode concrete: \(type) for key: \(key), reality: \(container.unboxed.element)")
        guard let strategy = self.decoder.nodeDecodings.last else {
            preconditionFailure(
                """
                Attempt to access node decoding strategy from empty stack.
                """
            )
        }

        let elements = container
            .withShared { singleElementBox -> [KeyedBox.Element] in
                dump(singleElementBox)
                if let unkeyed = singleElementBox.element as? UnkeyedBox {
                    print("element is unkeyed box: \(unkeyed)")
                    return unkeyed
                } else if let keyed = singleElementBox.element as? KeyedBox {
                    print("element is keyed box: \(keyed)")
                    return keyed.elements[key.stringValue]
                } else {

                    return []
                }
//                if ["value", ""].contains(key.stringValue) {
//                    let keyString = key.stringValue.isEmpty ? "value" : key.stringValue
//                    let value = keyedBox.elements[keyString]
//                    if !value.isEmpty {
//                        return value
//                    } else if let value = keyedBox.value {
//                        return [value]
//                    } else {
//                        return []
//                    }
//                } else {
//                    return keyedBox.elements[key.stringValue]
//                }
        }

        let attributes = container.withShared { keyedBox in
            keyedBox.attributes[key.stringValue]
        }
        print("Attributes should be empty?: \(attributes.isEmpty)")

        decoder.codingPath.append(key)
        let nodeDecodings = decoder.options.nodeDecodingStrategy.nodeDecodings(
            forType: T.self,
            with: decoder
        )
        decoder.nodeDecodings.append(nodeDecodings)
        defer {
            _ = decoder.nodeDecodings.removeLast()
            decoder.codingPath.removeLast()
        }
        let box: Box

        // You can't decode sequences from attributes, but other strategies
        // need special handling for empty sequences.
        if strategy(key) != .attribute && elements.isEmpty,
            let empty = (type as? AnySequence.Type)?.init() as? T {
            return empty
        }

        switch strategy(key) {
        case .attribute:
            guard
                let attributeBox = attributes.first
                else {
                    throw DecodingError.keyNotFound(key, DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription:
                        """
                        No attribute found for key \(_errorDescription(of: key)).
                        """
                    ))
            }
            box = attributeBox
        case .element:
            box = elements
        case .elementOrAttribute:
            guard
                let anyBox = elements.isEmpty ? attributes.first : elements as Box?
                else {
                    throw DecodingError.keyNotFound(key, DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription:
                        """
                        No attribute or element found for key \
                        \(_errorDescription(of: key)).
                        """
                    ))
            }
            box = anyBox
        }

        let value: T?
        if !(type is AnySequence.Type), let unkeyedBox = box as? UnkeyedBox,
            let first = unkeyedBox.first {
            value = try decoder.unbox(first)
        } else {
            value = try decoder.unbox(box)
        }

        if value == nil, let type = type as? AnyOptional.Type,
            let result = type.init() as? T {
            return result
        }

        guard let unwrapped = value else {
            print("no value")
            throw DecodingError.valueNotFound(type, DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription:
                "Expected \(type) value but found null instead."
            ))
        }
        print("value: \(value)")

        return unwrapped
    }

    private func _superDecoder(forKey key: CodingKey) throws -> Decoder {
        decoder.codingPath.append(key)
        defer { decoder.codingPath.removeLast() }

        let attributes = container.withShared { keyedBox in
            keyedBox.attributes[key.stringValue]
        }

        let box: Box = container.withShared { $0.element }
        return XMLDecoderImplementation(
            referencing: box,
            options: decoder.options,
            nodeDecodings: decoder.nodeDecodings,
            codingPath: decoder.codingPath
        )
    }
}
