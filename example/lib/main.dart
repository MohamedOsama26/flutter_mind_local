import 'package:flutter/material.dart';
import 'package:flutter_mind_local/flutter_mind_local.dart';

// ─── Change this to the absolute path of your .gguf model on the device ──────
const _modelPath = '/data/user/0/com.example.flutter_mind_local_example/files/qwen2.5-0.5b-q4.gguf';

void main() => runApp(const _App());

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_mind_local demo',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      home: const _ChatPage(),
    );
  }
}

// ─── Page ─────────────────────────────────────────────────────────────────────

class _ChatPage extends StatefulWidget {
  const _ChatPage();

  @override
  State<_ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<_ChatPage> {
  late final LocalEngine _engine;
  final _messages = <({String text, bool isUser})>[];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  _Status _status = _Status.idle;
  String? _error;

  @override
  void initState() {
    super.initState();
    _engine = LocalEngine(
      config: LocalConfig(
        modelPath: _modelPath,
        modelType: LocalModelType.auto,
        onEvent: _onEvent,
      ),
    );
  }

  void _onEvent(LocalEngineEvent event) {
    setState(() {
      switch (event) {
        case ModelLoadStarted():
          _status = _Status.loading;
        case ModelReady():
          _status = _Status.ready;
        case ModelFailed(:final error):
          _status = _Status.idle;
          _error = error;
        case InferenceStarted():
          _status = _Status.thinking;
        case InferenceCompleted():
          _status = _Status.ready;
        case InferenceFailed(:final error):
          _status = _Status.ready;
          _error = error;
        case ModelDisposed():
          _status = _Status.idle;
        case ContextCleared():
          break;
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _status == _Status.thinking || _status == _Status.loading) return;

    _controller.clear();
    setState(() {
      _messages.add((text: text, isUser: true));
      _error = null;
    });
    _scrollToBottom();

    try {
      final response = await _engine.send(userMessage: text);
      setState(() => _messages.add((text: response.text, isUser: false)));
      _scrollToBottom();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _engine.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('flutter_mind_local'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _StatusBar(status: _status),
        ),
      ),
      body: Column(
        children: [
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              actions: [
                TextButton(
                  onPressed: () => setState(() => _error = null),
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          Expanded(
            child: _messages.isEmpty
                ? const Center(child: Text('Send a message to load the model and start chatting.'))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) => _Bubble(message: _messages[i]),
                  ),
          ),
          _InputBar(
            controller: _controller,
            enabled: _status != _Status.thinking && _status != _Status.loading,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

// ─── Widgets ──────────────────────────────────────────────────────────────────

enum _Status { idle, loading, thinking, ready }

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.status});
  final _Status status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      _Status.loading => const LinearProgressIndicator(),
      _Status.thinking => LinearProgressIndicator(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final ({String text, bool isUser}) message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: message.isUser ? scheme.primary : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: message.isUser ? scheme.onPrimary : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: enabled ? 'Type a message…' : 'Please wait…',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: enabled ? onSend : null,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
