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

Future<void> main() async {
  final apiKey = Platform.environment['OPENAI_API_KEY'];
  if (apiKey == null) {
    stdout.writeln('Set OPENAI_API_KEY to run this example.');
    return;
  }

  final extractor = Extractor(
      provider: OpenAiProvider(apiKey: apiKey, model: 'gpt-4o-2024-08-06'));

  final point = await extractor.extract<Point>(
    prompt: 'Extract the point (3, 4) as JSON with integer fields x and y.',
    schema: _pointSchema,
    fromJson: _pointFromJson,
  );

  stdout.writeln('Point(${point.x}, ${point.y})');
}
