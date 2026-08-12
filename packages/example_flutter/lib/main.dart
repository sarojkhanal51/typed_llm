import 'package:flutter/material.dart';
import 'package:typed_llm/typed_llm.dart';

import 'models.dart';

const _sampleText = '''
Acme Corp
Invoice #4471
Due: 2026-09-01
Total due: \$77.50
''';

enum _ProviderKind { openAi, gemini, claude }

void main() => runApp(const _App());

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'typed_llm device demo',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
      home: const _HomePage(),
    );
  }
}

class _HomePage extends StatefulWidget {
  const _HomePage();

  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  final _apiKeyController = TextEditingController();
  final _textController = TextEditingController(text: _sampleText);
  _ProviderKind _provider = _ProviderKind.openAi;
  bool _loading = false;
  String? _resultText;
  String? _errorText;

  @override
  void dispose() {
    _apiKeyController.dispose();
    _textController.dispose();
    super.dispose();
  }

  LlmProvider _buildProvider(String apiKey) {
    return switch (_provider) {
      _ProviderKind.openAi => OpenAiProvider(apiKey: apiKey, model: 'gpt-4o-2024-08-06'),
      _ProviderKind.gemini => GeminiProvider(apiKey: apiKey, model: 'gemini-2.0-flash'),
      _ProviderKind.claude => ClaudeProvider(apiKey: apiKey, model: 'claude-opus-4-6'),
    };
  }

  Future<void> _extract() async {
    setState(() {
      _loading = true;
      _resultText = null;
      _errorText = null;
    });

    final extractor = Extractor(provider: _buildProvider(_apiKeyController.text.trim()));
    try {
      final invoice = await extractor.extract(
        $Invoice,
        prompt: 'Extract the invoice from this text:\n\n${_textController.text}',
      );
      setState(() {
        _resultText = 'Vendor: ${invoice.vendorName}\nTotal: ${invoice.totalAmount}\nDue: ${invoice.dueDate}';
      });
    } on TypedLlmException catch (e) {
      setState(() => _errorText = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('typed_llm device demo')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            SegmentedButton<_ProviderKind>(
              segments: const [
                ButtonSegment(value: _ProviderKind.openAi, label: Text('OpenAI')),
                ButtonSegment(value: _ProviderKind.gemini, label: Text('Gemini')),
                ButtonSegment(value: _ProviderKind.claude, label: Text('Claude')),
              ],
              selected: {_provider},
              onSelectionChanged: (selection) => setState(() => _provider = selection.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _apiKeyController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'API key', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _textController,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Source text', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loading ? null : _extract,
              child: _loading ? const CircularProgressIndicator() : const Text('Extract'),
            ),
            const SizedBox(height: 16),
            if (_resultText != null) SelectableText(_resultText!),
            if (_errorText != null) SelectableText(_errorText!, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }
}
