import 'package:flutter/material.dart';
import 'package:flutter_mind_local/flutter_mind_local.dart';
import 'package:flutter_mind_local_example/constants/enum.dart';
import 'package:flutter_mind_local_example/widgets/bubble.dart';
import 'package:flutter_mind_local_example/widgets/input_bar.dart';
import 'package:flutter_mind_local_example/widgets/status_bar.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => ChatPageState();
}

class ChatPageState extends State<ChatPage> {
  late final LocalEngine _engine;
  final _messages = <({String text, bool isUser})>[];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  Status _status = Status.idle;
  String? _error;
  static const _modelPath =
      '/data/user/0/dev.bedaya.flutter_mind_local_example/files/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf';

  @override
  void initState() {
    super.initState();
    _engine = LocalEngine(
      config: LocalConfig(
        modelPath: _modelPath,
        modelType: LocalModelType.auto,
        onEvent: _onEvent,
        stopSequences: ['<|im_end|>', '<|im_start|>'],
      ),
    );
  }

  void _onEvent(LocalEngineEvent event) {
    debugPrint('[${DateTime.now().toIso8601String()}] $event');
    setState(() {
      switch (event) {
        case ModelLoadStarted():
          _status = Status.loading;
        case ModelReady():
          _status = Status.ready;
        case ModelFailed(:final error):
          _status = Status.idle;
          _error = error;
        case InferenceStarted():
          _status = Status.thinking;
        case InferenceCompleted():
          _status = Status.ready;
        case InferenceFailed(:final error):
          _status = Status.ready;
          _error = error;
        case ModelDisposed():
          _status = Status.idle;
        case ContextCleared():
          break;
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty ||
        _status == Status.thinking ||
        _status == Status.loading) {
      return;
    }

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
          child: StatusBar(status: _status),
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
                ? const Center(
                    child: Text(
                      'Send a message to load the model and start chatting.',
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) => Bubble(message: _messages[i]),
                  ),
          ),
          InputBar(
            controller: _controller,
            enabled: _status != Status.thinking && _status != Status.loading,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}
