import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:convert';
// Use a conditional import so we don't reference `dart:io` on web.
import 'src/platform_stub.dart'
  if (dart.library.io) 'src/platform_io.dart';
// Conditional import for `File`/`Directory` symbols so builds for web don't
// fail when `dart:io` isn't available.
import 'src/io_stub.dart'
  if (dart.library.io) 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(VoiceBot());
}

class VoiceBot extends StatelessWidget {
  const VoiceBot({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: VoiceHome());
  }
}

class VoiceHome extends StatefulWidget {
  const VoiceHome({super.key});

  @override
  _VoiceHomeState createState() => _VoiceHomeState();
}

class _VoiceHomeState extends State<VoiceHome> {
  final SpeechToText speech = SpeechToText();
  final FlutterTts tts = FlutterTts();

  bool isListening = false;
  String userText = "Press mic and speak";
  String botText = "";
  bool speechSupported = false;

  List<Map<String, String>> conversation = [];

  // -----------------------------
  // Start Listening
  // -----------------------------
  void listen() async {
    try {
      bool available = await speech.initialize();

      if (!available) {
        setState(() => userText = "Speech not available on this device");
        setState(() => speechSupported = false);
        return;
      }

      setState(() => isListening = true);

      speech.listen(
        onResult: (result) {
          setState(() {
            userText = result.recognizedWords;
          });

          if (result.finalResult) {
            generateReply(userText);
          }
        },
      );
    } on MissingPluginException catch (_) {
      setState(() => userText = "Speech plugin not implemented on this platform");
      setState(() => speechSupported = false);
    } catch (e) {
      setState(() => userText = "Speech initialization error: $e");
      setState(() => speechSupported = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _checkSpeechAvailability();
  }

  Future<void> _checkSpeechAvailability() async {
    try {
      bool available = await speech.initialize();
      setState(() => speechSupported = available);
      debugPrint('speech initialize returned: $available');
      if (available) {
        // We initialized only to check availability; stop to avoid listening.
        await speech.stop();
      }
    } on MissingPluginException catch (_) {
      setState(() => speechSupported = false);
      debugPrint('MissingPluginException during speech availability check');
    } catch (_) {
      setState(() => speechSupported = false);
      debugPrint('Error during speech availability check');
    }
  }

  // -----------------------------
  // Chatbot Logic
  // -----------------------------
  void generateReply(String input) async {
    String reply;

    input = input.toLowerCase();

    if (input.contains("hello")) {
      reply = "Hello! How can I help you?";
    } else if (input.contains("name")) {
      reply = "I am your voice assistant.";
    } else if (input.contains("time")) {
      reply = DateTime.now().toString();
    } else {
      reply = "Sorry, I didn't understand.";
    }

    setState(() => botText = reply);

    await tts.speak(reply);

    conversation.add({
      "user": input,
      "bot": reply,
    });

    saveConversation();
  }

  // -----------------------------
  // Save conversation JSON
  // -----------------------------
  Future<void> saveConversation() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File("${dir.path}/chat.json");
    await file.writeAsString(jsonEncode(conversation));
  }

  // -----------------------------
  // UI
  // -----------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Voice Chatbot")),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            Text("You: $userText"),
            SizedBox(height: 20),
            Text("Bot: $botText"),
            SizedBox(height: 40),
            FloatingActionButton(
              onPressed: speechSupported ? listen : null,
              tooltip: speechSupported ? 'Start listening' : 'Speech unavailable',
              child: Icon(Icons.mic),
            )
          ],
        ),
      ),
    );
  }
}