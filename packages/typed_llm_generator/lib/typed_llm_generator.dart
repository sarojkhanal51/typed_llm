/// The `build_runner` code generator for `typed_llm`.
///
/// This library is not meant to be imported by application code — add
/// `typed_llm_generator` as a dev dependency and run
/// `dart run build_runner build`; the builder itself is registered via
/// `build.yaml` pointing at `package:typed_llm_generator/builder.dart`. This
/// file exists so the package has a conventional main library for
/// discoverability, and exposes [LlmSchemaGenerator] for anyone composing
/// it into a custom build pipeline.
library;

export 'src/schema_generator.dart' show LlmSchemaGenerator;
