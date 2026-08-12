import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';
import 'package:typed_llm/typed_llm.dart';

const TypeChecker _llmSchemaChecker = TypeChecker.typeNamed(
  LlmSchema,
  inPackage: 'typed_llm',
);
const TypeChecker _llmFieldChecker = TypeChecker.typeNamed(
  LlmField,
  inPackage: 'typed_llm',
);

/// Turns an `@LlmSchema()`-annotated class into three top-level members in
/// that class's `.g.dart` part file:
///
/// - `$<Class>` — an `LlmType<Class>` binding the schema to the factory.
///   This is what you pass to `Extractor.extract`.
/// - `<Class>Schema` — the raw JSON Schema map, for callers that want to
///   send or inspect the schema themselves.
/// - `_$<Class>FromValidatedJson` — the factory `$<Class>` points at.
///
/// Nested `@LlmSchema` classes and `List<T>` of a supported type are
/// resolved recursively and inlined into both the schema and the factory —
/// see [_planForClass] for the single traversal that builds both.
class LlmSchemaGenerator extends GeneratorForAnnotation<LlmSchema> {
  @override
  String generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        '@LlmSchema can only annotate classes, but was applied to '
        '${element.displayName}.',
        element: element,
      );
    }

    final plan = _planForClass(element, <ClassElement>{});
    final schemaLiteral = _emitDartLiteral(plan.schema.toMap());
    final className = element.name;

    return '''
/// The [LlmType] for [$className] — pass this to `Extractor.extract`.
const LlmType<$className> \$$className = LlmType<$className>(
  name: '$className',
  schema: ${className}Schema,
  fromJson: _\$${className}FromValidatedJson,
);

/// The raw JSON Schema describing [$className].
const Map<String, dynamic> ${className}Schema = $schemaLiteral;

$className _\$${className}FromValidatedJson(Map<String, dynamic> json) {
  return ${plan.build('json')};
}
''';
  }
}

/// The generated schema for one field, and the Dart expression (given a
/// source expression for the raw JSON value) that extracts it.
typedef _FieldPlan = ({JsonSchema schema, String Function(String) extract});

/// The generated schema for a whole `@LlmSchema` class, and a function that
/// builds a `ClassName(field: ..., ...)` construction expression given a
/// source expression for the decoded JSON object (a `Map<String, dynamic>`).
typedef _ClassPlan = ({JsonSchema schema, String Function(String) build});

_ClassPlan _planForClass(
  ClassElement classElement,
  Set<ClassElement> visiting,
) {
  if (!visiting.add(classElement)) {
    final cycle = [
      ...visiting.map((e) => e.name),
      classElement.name,
    ].join(' -> ');
    throw InvalidGenerationSourceError(
      'Cyclic @LlmSchema reference detected: $cycle. typed_llm does not '
      'support recursive/cyclic @LlmSchema class graphs.',
      element: classElement,
    );
  }

  final constructor = classElement.unnamedConstructor;
  if (constructor == null) {
    throw InvalidGenerationSourceError(
      'Class ${classElement.name} has no unnamed constructor. @LlmSchema '
      'requires an unnamed constructor (or, for freezed classes, an unnamed '
      'const factory) with only named parameters.',
      element: classElement,
    );
  }

  final fieldPlans = <String, _FieldPlan>{};
  for (final parameter in constructor.formalParameters) {
    // A named parameter always has a name; `name` is only null for a
    // positional wildcard (`_`), which the same check rejects.
    final parameterName = parameter.name;
    if (!parameter.isNamed || parameterName == null) {
      throw InvalidGenerationSourceError(
        "Parameter '${parameter.displayName}' on ${classElement.name}'s "
        'constructor is positional. @LlmSchema requires every constructor '
        'parameter to be named.',
        element: parameter,
      );
    }
    fieldPlans[parameterName] = _planForField(
      parameter,
      parameterName,
      classElement,
      visiting,
    );
  }

  visiting.remove(classElement);

  final properties = {
    for (final entry in fieldPlans.entries) entry.key: entry.value.schema,
  };
  final schema = JsonSchema.object(
    properties: properties,
    required: properties.keys.toList(),
  );

  String build(String mapExpr) {
    final args = fieldPlans.entries
        .map(
          (entry) =>
              "${entry.key}: ${entry.value.extract("$mapExpr['${entry.key}']")}",
        )
        .join(', ');
    return '${classElement.name}($args)';
  }

  return (schema: schema, build: build);
}

_FieldPlan _planForField(
  FormalParameterElement parameter,
  String fieldName,
  ClassElement owner,
  Set<ClassElement> visiting,
) {
  final fieldAnnotation = _llmFieldChecker.firstAnnotationOf(parameter);
  final reader = fieldAnnotation == null
      ? null
      : ConstantReader(fieldAnnotation);
  final description = reader == null || reader.read('description').isNull
      ? null
      : reader.read('description').stringValue;
  final explicitlyOptional =
      reader != null && reader.read('optional').boolValue;

  final type = parameter.type;
  final nullable = type.nullabilitySuffix == NullabilitySuffix.question;
  if (explicitlyOptional && !nullable) {
    throw InvalidGenerationSourceError(
      "Field '$fieldName' on ${owner.name} is marked "
      '@LlmField(optional: true) but its Dart type is non-nullable. Make '
      'the field nullable (add ?) or remove optional: true.',
      element: parameter,
    );
  }

  return _planForType(
    type,
    description: description,
    owner: owner,
    fieldName: fieldName,
    visiting: visiting,
  );
}

_FieldPlan _planForType(
  DartType type, {
  required String? description,
  required ClassElement owner,
  required String fieldName,
  required Set<ClassElement> visiting,
}) {
  final nullable = type.nullabilitySuffix == NullabilitySuffix.question;

  if (type.isDartCoreString) {
    return (
      schema: JsonSchema.string(description: description, nullable: nullable),
      extract: (expr) => nullable ? '$expr as String?' : '$expr as String',
    );
  }
  if (type.isDartCoreBool) {
    return (
      schema: JsonSchema.boolean(description: description, nullable: nullable),
      extract: (expr) => nullable ? '$expr as bool?' : '$expr as bool',
    );
  }
  if (type.isDartCoreInt) {
    return (
      schema: JsonSchema.integer(description: description, nullable: nullable),
      extract: (expr) =>
          nullable ? '($expr as num?)?.toInt()' : '($expr as num).toInt()',
    );
  }
  if (type.isDartCoreDouble) {
    return (
      schema: JsonSchema.number(description: description, nullable: nullable),
      extract: (expr) => nullable
          ? '($expr as num?)?.toDouble()'
          : '($expr as num).toDouble()',
    );
  }
  if (type.isDartCoreNum) {
    return (
      schema: JsonSchema.number(description: description, nullable: nullable),
      extract: (expr) => nullable ? '$expr as num?' : '$expr as num',
    );
  }
  if (_isDateTime(type)) {
    return (
      schema: JsonSchema.string(
        description: description,
        nullable: nullable,
        format: 'date-time',
      ),
      extract: (expr) => nullable
          ? '$expr == null ? null : DateTime.parse($expr as String)'
          : 'DateTime.parse($expr as String)',
    );
  }

  final element = type.element;
  if (element is EnumElement) {
    final enumName = element.name;
    return (
      schema: JsonSchema.string(
        description: description,
        nullable: nullable,
        enumValues: [
          for (final constant in element.fields.where(
            (field) => field.isEnumConstant,
          ))
            if (constant.name case final name?) name,
        ],
      ),
      extract: (expr) => nullable
          ? '$expr == null ? null : $enumName.values.byName($expr as String)'
          : '$enumName.values.byName($expr as String)',
    );
  }

  if (type.isDartCoreList && type is InterfaceType) {
    final itemType = type.typeArguments.single;
    final itemPlan = _planForType(
      itemType,
      description: null,
      owner: owner,
      fieldName: fieldName,
      visiting: visiting,
    );
    final itemExpr = itemPlan.extract('e');
    return (
      schema: JsonSchema.array(
        description: description,
        nullable: nullable,
        items: itemPlan.schema,
      ),
      extract: (expr) => nullable
          ? '($expr as List<dynamic>?)?.map((e) => $itemExpr).toList()'
          : '($expr as List<dynamic>).map((e) => $itemExpr).toList()',
    );
  }

  if (element is ClassElement && _llmSchemaChecker.hasAnnotationOf(element)) {
    final nestedPlan = _planForClass(element, visiting);
    final nestedObjectSchema = nestedPlan.schema as ObjectSchema;
    return (
      schema: JsonSchema.object(
        properties: nestedObjectSchema.properties,
        required: nestedObjectSchema.required,
        description: description,
        nullable: nullable,
      ),
      extract: (expr) => nullable
          ? "$expr == null ? null : ${nestedPlan.build('($expr as Map<String, dynamic>)')}"
          : nestedPlan.build('($expr as Map<String, dynamic>)'),
    );
  }

  throw InvalidGenerationSourceError(
    "Field '$fieldName' on ${owner.name} has unsupported type '$type'. "
    'Supported types: String, int, double, num, bool, DateTime, enum types, '
    'List<T> of a supported type, and other @LlmSchema-annotated classes. If '
    'this type should be extracted as a nested object, annotate its class '
    'with @LlmSchema().',
    element: owner,
  );
}

bool _isDateTime(DartType type) {
  final element = type.element;
  return element is ClassElement &&
      element.name == 'DateTime' &&
      element.library.isDartCore;
}

String _emitDartLiteral(Object? value) {
  return switch (value) {
    null => 'null',
    final bool value => '$value',
    final num value => '$value',
    final String value => "'${_escapeDartString(value)}'",
    final List<dynamic> value => '[${value.map(_emitDartLiteral).join(', ')}]',
    final Map<String, dynamic> value =>
      '{${value.entries.map((entry) => "'${_escapeDartString(entry.key)}': ${_emitDartLiteral(entry.value)}").join(', ')}}',
    _ => throw ArgumentError(
      'Cannot emit a Dart literal for $value (${value.runtimeType}).',
    ),
  };
}

String _escapeDartString(String value) => value
    .replaceAll(r'\', r'\\')
    .replaceAll("'", r"\'")
    .replaceAll(r'$', r'\$');
