import 'package:meta/meta.dart';

/// A single node in a provider-agnostic JSON Schema (a practical subset of
/// [JSON Schema Draft 2020-12](https://json-schema.org/draft/2020-12)) that
/// is sufficient to drive OpenAI, Gemini, and Claude structured-output modes.
///
/// Build a schema with one of the named constructors, then call [toMap] to
/// get the plain `Map<String, dynamic>` that gets sent to a provider or fed
/// to [SchemaValidator.validate]:
///
/// ```dart
/// final schema = JsonSchema.object(
///   properties: {
///     'vendorName': JsonSchema.string(),
///     'totalAmount': JsonSchema.number(),
///     'dueDate': JsonSchema.string(format: 'date-time'),
///   },
///   required: ['vendorName', 'totalAmount', 'dueDate'],
/// );
/// final map = schema.toMap();
/// ```
///
/// Nullable fields are represented with a `type` array (e.g.
/// `["string", "null"]`), matching standard JSON Schema and what OpenAI
/// strict mode and Claude's tool `input_schema` expect natively. Providers
/// with a different dialect (for example Gemini's OpenAPI-style subset,
/// which uses a separate `nullable: true` keyword) down-convert this map
/// themselves.
@immutable
sealed class JsonSchema {
  /// Constructor for subclasses; see the named factory constructors on this
  /// class (e.g. [JsonSchema.string]) to build a schema.
  const JsonSchema({this.title, this.description, this.nullable = false});

  /// Emitted as JSON Schema `title`, if set.
  final String? title;

  /// Emitted as JSON Schema `description`, if set. Descriptions materially
  /// improve extraction accuracy and should be set on every field via
  /// `@LlmField(description: '...')` in annotated classes.
  final String? description;

  /// Whether `null` is an accepted value, emitted as a `type` array
  /// (e.g. `["string", "null"]`) rather than the OpenAPI `nullable` keyword.
  final bool nullable;

  /// Converts this node (and, recursively, any nested nodes) to the plain
  /// `Map<String, dynamic>` JSON Schema representation.
  Map<String, dynamic> toMap();

  /// A JSON Schema `string` node, optionally constrained by [format] (e.g.
  /// `'date-time'`) or [enumValues].
  const factory JsonSchema.string({
    String? title,
    String? description,
    bool nullable,
    String? format,
    List<String>? enumValues,
  }) = StringSchema;

  /// A JSON Schema `number` node (accepts integers and floats).
  const factory JsonSchema.number({
    String? title,
    String? description,
    bool nullable,
  }) = NumberSchema;

  /// A JSON Schema `integer` node (accepts only whole numbers).
  const factory JsonSchema.integer({
    String? title,
    String? description,
    bool nullable,
  }) = IntegerSchema;

  /// A JSON Schema `boolean` node.
  const factory JsonSchema.boolean({
    String? title,
    String? description,
    bool nullable,
  }) = BooleanSchema;

  /// A JSON Schema `array` node whose elements each match [items].
  const factory JsonSchema.array({
    required JsonSchema items,
    String? title,
    String? description,
    bool nullable,
  }) = ArraySchema;

  /// A JSON Schema `object` node with named [properties].
  ///
  /// [additionalProperties] defaults to `false` because OpenAI strict mode
  /// requires it, and every entry in [properties] not meant to be optional
  /// must be listed in [required].
  const factory JsonSchema.object({
    required Map<String, JsonSchema> properties,
    required List<String> required,
    String? title,
    String? description,
    bool nullable,
    bool additionalProperties,
  }) = ObjectSchema;

  /// Builds the `type`/`title`/`description` entries shared by every schema
  /// node; subclasses spread this into their own [toMap] and add their
  /// type-specific keys.
  @protected
  Map<String, dynamic> baseMap(String jsonType) {
    return <String, dynamic>{
      'type': nullable ? <String>[jsonType, 'null'] : jsonType,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
    };
  }
}

/// A JSON Schema `string` node. Build one via [JsonSchema.string].
final class StringSchema extends JsonSchema {
  /// Creates a string schema node; prefer the [JsonSchema.string] factory.
  const StringSchema({
    super.title,
    super.description,
    super.nullable,
    this.format,
    this.enumValues,
  });

  /// A well-known string format keyword, e.g. `'date-time'`.
  final String? format;

  /// If set, restricts the value to one of these strings (JSON Schema
  /// `enum`).
  final List<String>? enumValues;

  @override
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      ...baseMap('string'),
      if (format != null) 'format': format,
      if (enumValues != null) 'enum': enumValues,
    };
  }
}

/// A JSON Schema `number` node. Build one via [JsonSchema.number].
final class NumberSchema extends JsonSchema {
  /// Creates a number schema node; prefer the [JsonSchema.number] factory.
  const NumberSchema({super.title, super.description, super.nullable});

  @override
  Map<String, dynamic> toMap() => baseMap('number');
}

/// A JSON Schema `integer` node. Build one via [JsonSchema.integer].
final class IntegerSchema extends JsonSchema {
  /// Creates an integer schema node; prefer the [JsonSchema.integer]
  /// factory.
  const IntegerSchema({super.title, super.description, super.nullable});

  @override
  Map<String, dynamic> toMap() => baseMap('integer');
}

/// A JSON Schema `boolean` node. Build one via [JsonSchema.boolean].
final class BooleanSchema extends JsonSchema {
  /// Creates a boolean schema node; prefer the [JsonSchema.boolean] factory.
  const BooleanSchema({super.title, super.description, super.nullable});

  @override
  Map<String, dynamic> toMap() => baseMap('boolean');
}

/// A JSON Schema `array` node. Build one via [JsonSchema.array].
final class ArraySchema extends JsonSchema {
  /// Creates an array schema node; prefer the [JsonSchema.array] factory.
  const ArraySchema({
    required this.items,
    super.title,
    super.description,
    super.nullable,
  });

  /// The schema every element of the array must match.
  final JsonSchema items;

  @override
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      ...baseMap('array'),
      'items': items.toMap(),
    };
  }
}

/// A JSON Schema `object` node. Build one via [JsonSchema.object].
final class ObjectSchema extends JsonSchema {
  /// Creates an object schema node; prefer the [JsonSchema.object] factory.
  const ObjectSchema({
    required this.properties,
    required this.required,
    super.title,
    super.description,
    super.nullable,
    this.additionalProperties = false,
  });

  /// Schema for each named property.
  final Map<String, JsonSchema> properties;

  /// Names of properties (from [properties]) that must be present.
  final List<String> required;

  /// Whether keys not listed in [properties] are permitted. OpenAI strict
  /// mode requires this to be `false`.
  final bool additionalProperties;

  @override
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      ...baseMap('object'),
      'properties': properties.map(
        (key, value) => MapEntry(key, value.toMap()),
      ),
      'required': required,
      'additionalProperties': additionalProperties,
    };
  }
}
