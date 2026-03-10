import 'dart:async';
import 'dart:convert';
//import 'dart:io';

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
  final List<Map<String, String>> _initialQuestions = [
    {'key': 'name', 'question': 'What is your name?'},
    {'key': 'fatherName', 'question': 'What is your Father name?'},
    {'key': 'owned', 'question': 'How much land you own?'},
    {'key': 'leasedIn', 'question': 'How much land you have leased-in?'},
    {'key': 'leasedOut', 'question': 'How much land you have leased-out?'},
    {'key': 'parcel', 'question': 'How much parcels do you have?'},
  ];

  List<Map<String, String>> _questions = [];

  // Individual variables for each answer
  String name = "";
  String fatherName = "";
  String owned = "";
  String leasedIn = "";
  String leasedOut = "";
  String totalLand = "";
  String parcel = "";

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

    await tts.speak("Welcome to Sample Survey voicebot. Press start survey to begin.");

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
    
    _questions = List.from(_initialQuestions);
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
    await Future.delayed(const Duration(milliseconds: 500));
    
    _inputTimer?.cancel();
    // Use a longer timer for the input itself to allow for speech recognition processing
    _inputTimer = Timer(const Duration(seconds: 15), _handleNoInput);

    try {
      _log('Listening started...');
      speech.listen(
        onResult: (result) {
          _log('onResult: recognizedWords: ${result.recognizedWords}, final: ${result.finalResult}');
          
          if (mounted) {
            setState(() {
              userText = result.recognizedWords;
            });
          }

          if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
            _inputTimer?.cancel();
            _processAnswer(result.recognizedWords);
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 10), // Shorter pause for faster recognition of single digits
        listenOptions: SpeechListenOptions(
          partialResults: true, // Use SpeechListenOptions instead of deprecated parameter
        ),
      );
    } catch (e) {
      _log('Error starting to listen: $e');
      _inputTimer?.cancel();
    }
  }

  void _processAnswer(String answer) async {
    final questionKey = _questions[_currentQuestionIndex]['key']!;
    _log('Processing answer for $questionKey: $answer');

    // Check if the question expects a numeric answer
    final numericKeys = ['owned', 'leasedIn', 'leasedOut', 'parcel'];
    bool isNumericQuestion = numericKeys.contains(questionKey) || questionKey.contains('area');
    
    String finalAnswer = answer;
    if (isNumericQuestion) {
      finalAnswer = _parseNumber(answer);
      // RETRY LOGIC: If we expected a number but got text that couldn't be parsed
      if (double.tryParse(finalAnswer) == null) {
        _log('Invalid numeric input: $answer');
        _inputAttempts++;
        if (_inputAttempts < 3) {
          await tts.speak("I didn't hear a number. Please say it again, like five or point five.");
          await Future.delayed(const Duration(seconds: 4), _askQuestion);
          return;
        } else {
          _log('Max numeric retries reached. Closing survey.');
          await tts.speak("I'm having trouble understanding the numbers. Closing the survey.");
          await Future.delayed(const Duration(seconds: 4), () => SystemNavigator.pop());
          return;
        }
      }
      _log('Parsed numeric answer: $finalAnswer');
    }

    _answers[questionKey] = finalAnswer;

    // Save to individual variables
    switch (questionKey) {
      case 'name':
        name = finalAnswer;
        break;
      case 'fatherName':
        fatherName = finalAnswer;
        break;
      case 'owned':
        owned = finalAnswer;
        break;
      case 'leasedIn':
        leasedIn = finalAnswer;
        break;
      case 'leasedOut':
        leasedOut = finalAnswer;
        break;
      case 'parcel':
        parcel = finalAnswer;
        // Dynamically add parcel questions
        int parcelCount = int.tryParse(finalAnswer) ?? 0;
        for (int i = 1; i <= parcelCount; i++) {
          _questions.add({'key': 'parcel_${i}_area', 'question': 'What is the area of parcel $i?'});
          _questions.add({'key': 'parcel_${i}_kharif', 'question': 'What kharif crop is grown in parcel $i?'});
          _questions.add({'key': 'parcel_${i}_rabi', 'question': 'What rabi crop is grown in parcel $i?'});
          _questions.add({'key': 'parcel_${i}_zaid', 'question': 'What zaid crop is grown in parcel $i?'});
        }
        break;
    }

    // Safely calculate totalLand
    double o = double.tryParse(owned) ?? 0.0;
    double li = double.tryParse(leasedIn) ?? 0.0;
    double lo = double.tryParse(leasedOut) ?? 0.0;
    totalLand = (o + li - lo).toString();

    // Print variables separately as requested
    _log('Variable Updated: name = $name');
    _log('Variable Updated: fatherName = $fatherName');
    _log('Variable Updated: owned = $owned');
    _log('Variable Updated: leasedIn = $leasedIn');
    _log('Variable Updated: leasedOut = $leasedOut');
    _log('Variable Updated: totalLand = $totalLand');
    _log('Variable Updated: parcel = $parcel');

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
      // 1. Try parsing directly if the STT returned digits (e.g., "5" or "5.5")
      String cleaned = text.trim().replaceAll(RegExp(r'[^0-9.]'), '');
      if (cleaned.isNotEmpty && num.tryParse(cleaned) != null) {
          return cleaned;
      }

      // 2. Fallback to word-to-number parsing
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
      bool foundWord = false;

      for (String word in words) {
          if (numberWords.containsKey(word)) {
              currentResult += numberWords[word]!;
              foundWord = true;
          } else if (word == 'hundred') {
              currentResult *= 100;
              foundWord = true;
          } else if (word == 'thousand') {
              finalResult += currentResult * 1000;
              currentResult = 0;
              foundWord = true;
          }
      }
      finalResult += currentResult;

      if (foundWord || textLower == 'zero') {
          return finalResult % 1 == 0 ? finalResult.toInt().toString() : finalResult.toString();
      }

      return text;
  }

  void _handleNoInput() async {
    _log('_handleNoInput() triggered');
    await speech.stop();
    await Future.delayed(const Duration(milliseconds: 200));

    _inputAttempts++;
    _log('Input retry attempts: $_inputAttempts');

    if (_inputAttempts < 3) {
      _log('Retrying question due to no input.');
      await tts.speak("I did not catch that. Please try again.");
      await Future.delayed(const Duration(seconds: 4));
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
    _log('Exiting app.');
    SystemNavigator.pop();
  }

  Future<void> saveSurveyResults() async {
    // Create a structured list of responses mapping question text to the answer
    List<Map<String, String>> surveyOutput = _questions.map((q) {
      String key = q['key']!;
      return {
        'key': key,
        'question': q['question']!,
        'answer': _answers[key] ?? ""
      };
    }).toList();

    // Add calculated fields to the final JSON
    surveyOutput.add({
      'key': 'totalLand',
      'question': 'Calculated Total Land (Owned + LeasedIn - LeasedOut)',
      'answer': totalLand
    });

    _log('saveSurveyResults() - Structured Data: ${jsonEncode(surveyOutput)}');
    try {
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final file = File('${dir.path}/survey_$timestamp.json');
      await file.writeAsString(jsonEncode(surveyOutput));
      _log('Survey results saved to ${file.path}');
    } catch (e) {
      _log('Error saving survey results: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("FarmTalk Survey")),
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
                FloatingActionButton.extended(
                  onPressed: _finishSurvey, // Allow finishing early
                  label: Text('Finish Survey'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
