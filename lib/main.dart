import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';

// Conditional import for `File`/`Directory` symbols so builds for web don't
// fail when `dart:io` isn't available.
import 'src/io_stub.dart' if (dart.library.io) 'dart:io';

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

  // Logging State
  File? _logFile;

  // Survey State
  final List<Map<String, String>> _questions = [
    {'key': 'name', 'question': 'What is your name?'},
    {'key': 'fatherName', 'question': 'What is your Father name?'},
    {'key': 'owned', 'question': 'How much land you own?'},
    {'key': 'leasedIn', 'question': 'How much land you have leased-in?'},
    {'key': 'leasedOut', 'question': 'How much land you have leased-out?'},
    {'key': 'parcel', 'question': 'How much parcels do you have?'},
  ];

  // TO DO
  // Find out total land for farming. Total = owned + leasedIn - leasedOut
  // Get the each parcel area by iterating through the no. of parcels
  // Get the kharif, Rabi & Zaid crops & its area by iterating through the no. of parcels

  int _currentQuestionIndex = 0;
  final Map<String, String> _answers = {};

  // UI and Speech State
  String userText = "";
  String botText = "";
  bool speechSupported = false;
  bool _surveyStarted = false;

  // Timing Logic
  int _inputAttempts = 0;
  Timer? _inputTimer;
  Timer? _initialActionTimer;

  @override
  void initState() {
    super.initState();
    _initLogFile().then((_) {
      _log('initState()');
      _initializeSpeech();
    });
  }

  @override
  void dispose() {
    _inputTimer?.cancel();
    _initialActionTimer?.cancel();
    super.dispose();
  }

  Future<void> _initLogFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
      _logFile = File('${dir.path}/app_log_$timestamp.txt');
      await _logFile!.writeAsString('--- Log started at ${DateTime.now()} ---\n');
      _log('Log file created at: ${_logFile!.path}');
    } catch (e) {
      debugPrint('Error initializing log file: $e');
    }
  }

  Future<void> _log(String message) async {
    final timestamp = DateTime.now().toIso8601String();
    final logLine = '[$timestamp] $message';
    debugPrint(logLine);
    try {
      if (_logFile != null) {
        await _logFile!.writeAsString('$logLine\n', mode: FileMode.append);
      }
    } catch (e) {
      debugPrint('Error writing to log file: $e');
    }
  }

  Future<void> _initializeSpeech() async {
    _log('_initializeSpeech() called');
    try {
      bool available = await speech.initialize(
        debugLogging: true,
        onStatus: (status) => _log('Speech status: $status'),
        onError: (error) => _log('Speech error: $error'),
      );
      if (mounted) {
        setState(() => speechSupported = available);
      }
      _log('speech.initialize returned: $available');
    } catch (e) {
      if (mounted) setState(() => speechSupported = false);
      _log('Error during speech initialization: $e');
    }

    await tts.speak("Press start survey to begin.");

    // Start a 30-second timer to close the app if Start Survey is not clicked
    _initialActionTimer?.cancel();
    _initialActionTimer = Timer(const Duration(seconds: 30), () async {
      if (!_surveyStarted) {
        _log('Initial timeout reached: User did not start survey within 30s.');
        await tts.speak("No action detected. Closing the app.");
        await Future.delayed(const Duration(seconds: 3));
        SystemNavigator.pop();
      }
    });
  }

  void _startSurvey() {
    _log('_startSurvey() called');
    _initialActionTimer?.cancel(); // Stop the initial timeout timer
    
    if (_surveyStarted) return; // Prevent re-entry

    if (mounted) {
      setState(() {
        _surveyStarted = true;
      });
    }
    
    _currentQuestionIndex = 0;
    _answers.clear();
    _inputAttempts = 0;
    _askQuestion();
  }

  void _askQuestion() async {
    if (_currentQuestionIndex >= _questions.length) {
      _log('Survey finished. Asking questions complete.');
      _finishSurvey();
      return;
    }

    String question = _questions[_currentQuestionIndex]['question']!;
    _log('Asking question index $_currentQuestionIndex: $question');
    if (mounted) {
      setState(() {
        botText = question;
        userText = "Listening...";
      });
    }
    await tts.speak(question);
    // Add a short delay to prevent the app from listening to its own voice
    await Future.delayed(const Duration(seconds: 1));
    
    _inputTimer?.cancel();
    _inputTimer = Timer(const Duration(seconds: 10), _handleNoInput);

    try {
      _log('Listening started...');
      speech.listen(
        onResult: (result) {
          _log('onResult: recognizedWords: ${result.recognizedWords}, final: ${result.finalResult}');
          if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
            _inputTimer?.cancel();
            _processAnswer(result.recognizedWords);
          }
        },
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 10),
        partialResults: false,
      );
    } catch (e) {
      _log('Error starting to listen: $e');
      _inputTimer?.cancel();
    }
  }

  void _processAnswer(String answer) {
    final questionKey = _questions[_currentQuestionIndex]['key']!;
    _log('Processing answer for $questionKey: $answer');

    // Check if the question expects a numeric answer
    final numericKeys = ['owned', 'leasedIn', 'leasedOut', 'parcel'];
    String finalAnswer = answer;
    if (numericKeys.contains(questionKey)) {
      finalAnswer = _parseNumber(answer);
      _log('Parsed numeric answer: $finalAnswer');
    }

    _answers[questionKey] = finalAnswer;

    if (mounted) {
      setState(() {
        userText = finalAnswer; // Show the parsed number in the UI
      });
    }

    _currentQuestionIndex++;
    _inputAttempts = 0; // Reset retry attempts for the next question

    // Wait a bit before asking the next question
    Future.delayed(const Duration(seconds: 1), _askQuestion);
  }

  String _parseNumber(String text) {
      // try direct parsing first
      if (int.tryParse(text) != null) {
          return text;
      }
      final textLower = text.toLowerCase().replaceAll('-', ' ').replaceAll(' and ', ' ').trim();
      const numberWords = {
        'zero': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
        'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
        'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14, 'fifteen': 15,
        'sixteen': 16, 'seventeen': 17, 'eighteen': 18, 'nineteen': 19,
        'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50, 'sixty': 60,
        'seventy': 70, 'eighty': 80, 'ninety': 90
      };
      
      List<String> words = textLower.split(' ');
      num finalResult = 0;
      num currentResult = 0;

      for (String word in words) {
          if (numberWords.containsKey(word)) {
              currentResult += numberWords[word]!;
          } else if (word == 'hundred') {
              currentResult *= 100;
          } else if (word == 'thousand') {
              finalResult += currentResult * 1000;
              currentResult = 0;
          }
      }
      finalResult += currentResult;

      if (finalResult != 0 || textLower == 'zero') {
          return finalResult.toString();
      }

      // If parsing fails, return original text
      return text;
  }

  void _handleNoInput() async {
    _log('_handleNoInput() triggered');
    await speech.stop();
    // A short, non-blocking delay to ensure the audio focus is released.
    await Future.delayed(const Duration(milliseconds: 200));

    _inputAttempts++;
    _log('Input retry attempts: $_inputAttempts');

    if (_inputAttempts < 3) {
      _log('Retrying question due to no input.');
      await tts.speak("I did not catch that. Please try again.");
      await Future.delayed(const Duration(seconds: 5));
      _askQuestion();
    } else {
      _log('Max retry attempts reached. Closing survey.');
      await tts.speak("No input received after several attempts. Closing the survey.");
      await Future.delayed(const Duration(seconds: 4));
      SystemNavigator.pop();
    }
  }

  void _finishSurvey() async {
    _log('_finishSurvey() called');
    if (mounted) {
      setState(() {
        botText = "Survey complete. Thank you!";
        userText = "";
      });
    }
    await tts.speak("Thank you for completing the survey. The app will now close.");
    await saveSurveyResults();
    await Future.delayed(const Duration(seconds: 4));
    await Future.delayed(const Duration(seconds: 4));
    _log('Exiting app.');
    SystemNavigator.pop();
  }

  Future<void> saveSurveyResults() async {
    _log('saveSurveyResults() - Answers: ${jsonEncode(_answers)}');
    try {
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final file = File('${dir.path}/survey_$timestamp.json');
      await file.writeAsString(jsonEncode(_answers));
      _log('Survey results saved to ${file.path}');
    } catch (e) {
      _log('Error saving survey results: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Sample Survey VoiceBot")),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Bot: $botText"),
            SizedBox(height: 20),
            Text("You: $userText"),
            SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FloatingActionButton.extended(
                  onPressed: speechSupported && !_surveyStarted ? _startSurvey : null,
                  tooltip: _surveyStarted ? 'Survey in progress...' : (speechSupported ? 'Start Survey' : 'Speech not available'),
                  icon: Icon(_surveyStarted ? Icons.mic : Icons.mic),
                  label: Text('Start Survey'),
                  backgroundColor: _surveyStarted ? Colors.grey : null,
                ),
                ElevatedButton(
                  onPressed: _finishSurvey, // Allow finishing early
                  child: Text('Finish Survey'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
