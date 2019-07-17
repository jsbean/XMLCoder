//
//  XMLSingleElementEncodingContainer.swift
//  XMLCoder
//
//  Created by Benjamin Wetherfield on 7/17/19.
//

import Foundation

struct XMLSingleElementEncodingContainer<K: CodingKey>: KeyedEncodingContainerProtocol {
    typealias Key = K
    
    // MARK: Properties
    
    /// A reference to the encoder we're writing to.
    private let encoder: XMLEncoderImplementation
    
    /// A reference to the container we're writing to.
    private var container: SharedBox<SingleElementBox>
    
    /// The path of coding keys taken to get to this point in encoding.
    public private(set) var codingPath: [CodingKey]
    
    // MARK: - Initialization
    
    /// Initializes `self` with the given references.
    init(
        referencing encoder: XMLEncoderImplementation,
        codingPath: [CodingKey],
        wrapping container: SharedBox<SingleElementBox>
        ) {
        self.encoder = encoder
        self.codingPath = codingPath
        self.container = container
    }
    
    // MARK: - Coding Path Operations
    
    private func _converted(_ key: CodingKey) -> CodingKey {
        switch encoder.options.keyEncodingStrategy {
        case .useDefaultKeys:
            return key
        case .convertToSnakeCase:
            let newKeyString = XMLEncoder.KeyEncodingStrategy
                ._convertToSnakeCase(key.stringValue)
            return XMLKey(stringValue: newKeyString, intValue: key.intValue)
        case .convertToKebabCase:
            let newKeyString = XMLEncoder.KeyEncodingStrategy
                ._convertToKebabCase(key.stringValue)
            return XMLKey(stringValue: newKeyString, intValue: key.intValue)
        case let .custom(converter):
            return converter(codingPath + [key])
        case .capitalized:
            let newKeyString = XMLEncoder.KeyEncodingStrategy
                ._convertToCapitalized(key.stringValue)
            return XMLKey(stringValue: newKeyString, intValue: key.intValue)
        case .uppercased:
            let newKeyString = XMLEncoder.KeyEncodingStrategy
                ._convertToUppercased(key.stringValue)
            return XMLKey(stringValue: newKeyString, intValue: key.intValue)
        case .lowercased:
            let newKeyString = XMLEncoder.KeyEncodingStrategy
                ._convertToLowercased(key.stringValue)
            return XMLKey(stringValue: newKeyString, intValue: key.intValue)
        }
    }
    
    // MARK: - KeyedEncodingContainerProtocol Methods
    
    public mutating func encodeNil(forKey key: Key) throws {
        container.withShared {
            $0.key = _converted(key).stringValue
            $0.element = NullBox()
        }
    }
    
    public mutating func encode<T: Encodable>(
        _ value: T,
        forKey key: Key
        ) throws {
        return try encode(value, forKey: key) { encoder, value in
            try encoder.box(value)
        }
    }
    
    private mutating func encode<T: Encodable>(
        _ value: T,
        forKey key: Key,
        encode: (XMLEncoderImplementation, T) throws -> Box
        ) throws {
        defer {
            _ = self.encoder.nodeEncodings.removeLast()
            self.encoder.codingPath.removeLast()
        }
        guard let strategy = self.encoder.nodeEncodings.last else {
            preconditionFailure(
                "Attempt to access node encoding strategy from empty stack."
            )
        }
        encoder.codingPath.append(key)
        let nodeEncodings = encoder.options.nodeEncodingStrategy.nodeEncodings(
            forType: T.self,
            with: encoder
        )
        encoder.nodeEncodings.append(nodeEncodings)
        let box = try encode(encoder, value)
        
        let mySelf = self
        let attributeEncoder: (T, Key, Box) throws -> () = { value, key, box in
            guard let attribute = box as? SimpleBox else {
                throw EncodingError.invalidValue(value, EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Complex values cannot be encoded as attributes."
                ))
            }
            mySelf.container.withShared { container in
                container.attributes.append(attribute, at: mySelf._converted(key).stringValue)
            }
        }
        
        let elementEncoder: (T, Key, Box) throws -> () = { _, key, box in
            mySelf.container.withShared { container in
                container.element = box
                container.key = mySelf._converted(key).stringValue
            }
        }
        
        defer {
            self = mySelf
        }
        
        switch strategy(key) {
        case .attribute:
            try attributeEncoder(value, key, box)
        case .element:
            try elementEncoder(value, key, box)
        case .both:
            try attributeEncoder(value, key, box)
            try elementEncoder(value, key, box)
        }
    }
    
    public mutating func nestedContainer<NestedKey>(
        keyedBy _: NestedKey.Type,
        forKey key: Key
        ) -> KeyedEncodingContainer<NestedKey> {
        if NestedKey.self is XMLChoiceKey.Type {
            return nestedSingleElementContainer(keyedBy: NestedKey.self, forKey: key)
        } else {
            return nestedKeyedContainer(keyedBy: NestedKey.self, forKey: key)
        }
    }
    
    mutating func nestedKeyedContainer<NestedKey>(
        keyedBy _: NestedKey.Type,
        forKey key: Key
        ) -> KeyedEncodingContainer<NestedKey> {
        let sharedKeyed = SharedBox(KeyedBox())
        
        self.container.withShared { container in
            container.element = sharedKeyed
            container.key = _converted(key).stringValue
        }
        
        codingPath.append(key)
        defer { self.codingPath.removeLast() }
        
        let container = XMLKeyedEncodingContainer<NestedKey>(
            referencing: encoder,
            codingPath: codingPath,
            wrapping: sharedKeyed
        )
        return KeyedEncodingContainer(container)
    }
    
    mutating func nestedSingleElementContainer<NestedKey>(
        keyedBy _: NestedKey.Type,
        forKey key: Key
        ) -> KeyedEncodingContainer<NestedKey> {
        let sharedSingleElement = SharedBox(SingleElementBox())
        
        self.container.withShared { container in
            container.element = sharedSingleElement
            container.key = _converted(key).stringValue
        }
        
        codingPath.append(key)
        defer { self.codingPath.removeLast() }
        
        let container = XMLSingleElementEncodingContainer<NestedKey>(
            referencing: encoder,
            codingPath: codingPath,
            wrapping: sharedSingleElement
        )
        return KeyedEncodingContainer(container)
    }
    
    public mutating func nestedUnkeyedContainer(
        forKey key: Key
        ) -> UnkeyedEncodingContainer {
        let sharedUnkeyed = SharedBox(UnkeyedBox())
        
        container.withShared { container in
            container.element = sharedUnkeyed
            container.key = _converted(key).stringValue
        }
        
        codingPath.append(key)
        defer { self.codingPath.removeLast() }
        return XMLUnkeyedEncodingContainer(
            referencing: encoder,
            codingPath: codingPath,
            wrapping: sharedUnkeyed
        )
    }

    public mutating func superEncoder() -> Encoder {
        return XMLReferencingEncoder(
            referencing: encoder,
            key: XMLKey.super,
            convertedKey: _converted(XMLKey.super),
            wrapping: container
        )
    }

    public mutating func superEncoder(forKey key: Key) -> Encoder {
        return XMLReferencingEncoder(
            referencing: encoder,
            key: key,
            convertedKey: _converted(key),
            wrapping: container
        )
    }
}
