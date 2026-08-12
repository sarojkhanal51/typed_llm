// A minimal example using typed_llm's lower-level API directly — building
// the schema and the parser by hand, no code generation involved. For the
// full, `@LlmSchema()`-generator-driven workflow (including a freezed
// class), see the runnable example app in this repository's
// `packages/example` directory.
import 'dart:io';

import 'package:typed_llm/typed_llm.dart';

class Point {
  Point({required this.x, required this.y});

  final int x;
  final int y;
}

Point _pointFromJson(Map<String, dynamic> json) =>
    Point(x: json['x'] as int, y: json['y'] as int);

final _pointSchema = const JsonSchema.object(
  properties: {'x': JsonSchema.integer(), 'y': JsonSchema.integer()},
  required: ['x', 'y'],
).toMap();

// The generator emits one of these as `$Point`; built by hand here, since
// this example deliberately skips code generation.
final _pointType = LlmType<Point>(
  name: 'Point',
  schema: _pointSchema,
  fromJson: _pointFromJson,
);

Future<void> main() async {
  final apiKey = Platform.environment['OPENAI_API_KEY'];
  if (apiKey == null) {
    stdout.writeln('Set OPENAI_API_KEY to run this example.');
    return;
  }

  final extractor = Extractor(
      provider: OpenAiProvider(apiKey: apiKey, model: 'gpt-4o-2024-08-06'));

  final point = await extractor.extract(
    _pointType,
    prompt: 'Extract the point (3, 4) as JSON with integer fields x and y.',
  );

  stdout.writeln('Point(${point.x}, ${point.y})');
}
