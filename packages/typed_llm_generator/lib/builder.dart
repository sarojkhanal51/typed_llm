import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/schema_generator.dart';

/// Builder factory registered in `build.yaml` under the `llm_schema` key.
///
/// Add `build_runner` + `typed_llm_generator` as dev dependencies, annotate
/// classes with `@LlmSchema()`, add `part '<file>.g.dart';` to the source
/// file, then run `dart run build_runner build`.
Builder llmSchemaBuilder(BuilderOptions options) =>
    SharedPartBuilder([LlmSchemaGenerator()], 'llm_schema');
