import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:convert';
// Use a conditional import so we don't reference `dart:io` on web.
//import 'src/platform_stub.dart'
  //if (dart.library.io) 'src/platform_io.dart';
// Conditional import for `File`/`Directory` symbols so builds for web don't
// fail when `dart:io` isn't available.
import 'src/io_stub.dart'
  if (dart.library.io) 'dart:io';
import 'package:path_provider/path_provider.dart';
//import 'package:flutter/services.dart';

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

  @override
  void initState() {
    super.initState();
    debugPrint('initState()');
    _initializeSpeech();
  }

  Future<void> _initializeSpeech() async {
    debugPrint('_initializeSpeech() called');
    // Set up listeners via initialize parameters
    try {
      bool available = await speech.initialize(
        debugLogging: true,
        onStatus: (status) {
          debugPrint('onStatus: $status');
          if (status == SpeechToText.doneStatus || status == SpeechToText.notListeningStatus) {
            if (mounted) {
              setState(() => isListening = false);
            }
          }
        },
        onError: (errorNotification) {
          debugPrint('onError: ${errorNotification.errorMsg}');
          if (mounted) {
            setState(() {
              isListening = false;
              userText = 'Error: ${errorNotification.errorMsg}';
            });
          }
        },
      );
      if (mounted) {
        setState(() => speechSupported = available);
      }
      debugPrint('speech.initialize returned: $available');
    } catch (e) {
      if(mounted) setState(() => speechSupported = false);
      debugPrint('Error during speech initialization: $e');
    }
  }

  // ----------------------------- 
  // Start/Stop Listening
  // ----------------------------- 
  void listen() {
    debugPrint('listen() called');
    if (isListening) {
      debugPrint('stopping listening');
      speech.stop();
      // onStatus callback will set isListening to false
      return;
    }

    if (!speechSupported) {
      debugPrint('speech not supported, cannot listen');
      return;
    }

    if (mounted) {
      setState(() => isListening = true);
    }

    speech.listen(
      onResult: (result) {
        debugPrint('onResult: ${result.recognizedWords}');
        if (mounted) {
          setState(() {
            userText = result.recognizedWords;
          });
        }
        if (result.finalResult) {
          generateReply(userText);
        }
      },
      listenFor: Duration(seconds: 30),
      pauseFor: Duration(seconds: 5),
      partialResults: true,
    );
  }

  // ----------------------------- 
  // Chatbot Logic
  // ----------------------------- 
  void generateReply(String input) async {
    debugPrint('generateReply() called with input: $input');
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

    if (mounted) {
        setState(() => botText = reply);
    }

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
    debugPrint('saveConversation() called');
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File("${dir.path}/chat.json");
      await file.writeAsString(jsonEncode(conversation));
      debugPrint('Conversation saved to ${file.path}');
    } catch (e) {
      debugPrint('Error saving conversation: $e');
    }
  }

  // ----------------------------- 
  // UI
  // ----------------------------- 
  @override
  Widget build(BuildContext context) {
    debugPrint('build() called, speechSupported=$speechSupported, isListening=$isListening');
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
              tooltip: isListening ? 'Stop' : (speechSupported ? 'Listen' : 'Speech not available'),
              child: Icon(isListening ? Icons.mic_off : Icons.mic),
            )
          ],
        ),
      ),
    );
  }
}
