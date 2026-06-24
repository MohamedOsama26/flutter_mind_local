# flutter_mind_local example

A chat UI that runs a quantized `.gguf` model entirely on-device, with no API key
and no network connection, using [flutter_mind_local](https://pub.dev/packages/flutter_mind_local).

## Usage

```dart
import 'package:flutter_mind/flutter_mind.dart';
import 'package:flutter_mind_local/flutter_mind_local.dart';

final ai = FlutterMindClient(
  engine: LocalEngine(
    config: LocalConfig(
      modelPath: '/path/to/your/model.gguf',
      modelType: LocalModelType.auto, // detects the chat template from .gguf metadata
    ),
  ),
);

// The model loads lazily on the first call — no explicit init step.
final response = await ai.send(userMessage: 'Hello! Who are you?');
print(response.text);

// Or stream the response token by token for a live typing effect:
ai.stream(userMessage: 'Tell me a story').listen((chunk) => print(chunk));
```

See [lib/pages/chat_page.dart](lib/pages/chat_page.dart) for the full implementation,
including lifecycle events (`ModelLoadStarted`, `ModelReady`, `InferenceFailed`, etc.)
driving the chat UI's loading/error states.

## Running this example

You need a `.gguf` model file on the device first — this example does not bundle one
(model files are hundreds of MB to several GB). Download one from
[HuggingFace](https://huggingface.co/models?library=gguf) (the main package README
has a table of good starting models for mobile), then push it to the device:

```bash
adb push your-model.gguf /data/local/tmp/model.gguf
adb shell run-as <your.app.id> mkdir -p files
adb shell run-as <your.app.id> cp /data/local/tmp/model.gguf files/model.gguf
adb shell rm /data/local/tmp/model.gguf
```

Update `_modelPath` in [lib/pages/chat_page.dart](lib/pages/chat_page.dart) to match,
then run:

```bash
flutter run
```
