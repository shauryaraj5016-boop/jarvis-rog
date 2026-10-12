import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'groq_client.dart';
import 'jarvis_orb.dart';
import 'jarvis_phase.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  static const Color _red = Color(0xFFFF3344);
  static const Color _muted = Color(0xFF94949C);
  static const String _defaultModel = 'llama-3.3-70b-versatile';
  static const String _apiKeyName = 'groq_api_key';
  static const String _modelName = 'groq_model';
  static const String _buildApiKey = String.fromEnvironment('GROQ_API_KEY');

  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final GroqClient _groq = GroqClient();
  final List<ConversationMessage> _messages = [];

  JarvisPhase _phase = JarvisPhase.ready;
  String _apiKey = '';
  String _model = _defaultModel;
  String _liveTranscript = '';
  String? _notice;
  bool _settingsLoaded = false;
  bool _speechAvailable = false;
  bool _submittedCurrentSession = false;

  bool get _isListening => _phase == JarvisPhase.listening;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
    unawaited(_initializeSpeech());
    unawaited(_initializeTts());
  }

  Future<void> _loadSettings() async {
    try {
      final key = await _secureStorage.read(key: _apiKeyName);
      final model = await _secureStorage.read(key: _modelName);
      if (!mounted) return;
      setState(() {
        final savedKey = key?.trim() ?? '';
        _apiKey = savedKey.isNotEmpty ? savedKey : _buildApiKey.trim();
        _model = model?.trim().isNotEmpty == true
            ? model!.trim()
            : _defaultModel;
        _settingsLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _apiKey = _buildApiKey.trim();
        _settingsLoaded = true;
        _notice = 'Secure settings could not be read on this device.';
      });
    }
  }

  Future<void> _initializeSpeech() async {
    try {
      final available = await _speech.initialize(
        onStatus: _onSpeechStatus,
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _phase = JarvisPhase.ready;
            _liveTranscript = '';
            _notice = error.errorMsg;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _speechAvailable = available;
        if (!available) {
          _notice = 'Speech recognition is unavailable on this device.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _speechAvailable = false;
        _notice =
            'Could not start speech recognition. Check microphone permissions.';
      });
    }
  }

  Future<void> _initializeTts() async {
    _tts.setStartHandler(() => _setPhase(JarvisPhase.speaking));
    _tts.setCompletionHandler(() => _setPhase(JarvisPhase.ready));
    _tts.setCancelHandler(() => _setPhase(JarvisPhase.ready));
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.47);
      await _tts.setPitch(0.94);
      await _tts.awaitSpeakCompletion(true);
    } catch (_) {
      // Keep the text response available when a device has no TTS voice installed.
    }
  }

  void _onSpeechStatus(String status) {
    if (!mounted) return;
    if (status == 'listening') {
      _setPhase(JarvisPhase.listening);
      return;
    }

    if ((status == 'done' || status == 'notListening') &&
        _phase == JarvisPhase.listening) {
      final transcript = _liveTranscript.trim();
      if (transcript.isNotEmpty && !_submittedCurrentSession) {
        _submittedCurrentSession = true;
        unawaited(_sendPrompt(transcript));
      } else {
        setState(() {
          _phase = JarvisPhase.ready;
          _liveTranscript = '';
        });
      }
    }
  }

  Future<void> _onMicPressed() async {
    if (!_settingsLoaded) return;

    if (_isListening) {
      await _speech.stop();
      return;
    }

    if (_phase == JarvisPhase.thinking) return;
    if (_phase == JarvisPhase.speaking) {
      await _tts.stop();
      if (!mounted) return;
      setState(() => _phase = JarvisPhase.ready);
    }

    if (_apiKey.trim().isEmpty) {
      await _openSettings();
      return;
    }

    if (!_speechAvailable) {
      await _initializeSpeech();
      if (!_speechAvailable) {
        _showNotice(
          'Allow microphone and speech recognition access to use voice input.',
        );
        return;
      }
    }

    _submittedCurrentSession = false;
    setState(() {
      _liveTranscript = '';
      _notice = null;
      _phase = JarvisPhase.listening;
    });

    try {
      await _speech.listen(
        onResult: (result) {
          if (!mounted) return;
          final transcript = result.recognizedWords.trim();
          setState(() => _liveTranscript = transcript);
          if (result.finalResult &&
              transcript.isNotEmpty &&
              !_submittedCurrentSession) {
            _submittedCurrentSession = true;
            unawaited(_sendPrompt(transcript));
          }
        },
        listenOptions: SpeechListenOptions(
          listenFor: const Duration(seconds: 45),
          pauseFor: const Duration(seconds: 4),
          localeId: 'en_US',
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: true,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = JarvisPhase.ready;
        _notice = 'Could not start listening. Check microphone permissions.';
      });
    }
  }

  Future<void> _sendPrompt(String prompt) async {
    final cleanPrompt = prompt.trim();
    if (cleanPrompt.isEmpty || !mounted) return;

    setState(() {
      _liveTranscript = '';
      _phase = JarvisPhase.thinking;
      _notice = null;
      _messages.add(ConversationMessage(role: 'user', content: cleanPrompt));
    });

    final conversation = _messages
        .where((message) => !message.isError)
        .toList()
        .reversed
        .take(12)
        .toList()
        .reversed
        .map((message) => {'role': message.role, 'content': message.content})
        .toList();

    try {
      final reply = await _groq.complete(
        apiKey: _apiKey,
        model: _model,
        conversation: conversation,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(ConversationMessage(role: 'assistant', content: reply));
        _phase = JarvisPhase.speaking;
      });

      try {
        await _tts.speak(reply);
      } catch (_) {
        if (mounted) {
          setState(() {
            _phase = JarvisPhase.ready;
            _notice =
                'Reply received. Speech playback is unavailable on this device.';
          });
        }
      }
      if (mounted && _phase == JarvisPhase.speaking) {
        setState(() => _phase = JarvisPhase.ready);
      }
    } on GroqApiException catch (error) {
      _appendError(error.message);
    } on TimeoutException {
      _appendError(
        'Groq took too long to respond. Check your connection and try again.',
      );
    } catch (_) {
      _appendError(
        'Could not reach Groq. Check your connection and API settings.',
      );
    }
  }

  void _appendError(String message) {
    if (!mounted) return;
    setState(() {
      _phase = JarvisPhase.ready;
      _notice = message;
      _messages.add(
        ConversationMessage(role: 'assistant', content: message, isError: true),
      );
    });
  }

  void _setPhase(JarvisPhase phase) {
    if (!mounted || _phase == JarvisPhase.thinking) return;
    setState(() => _phase = phase);
  }

  Future<void> _openSettings() async {
    final keyController = TextEditingController(text: _apiKey);
    final modelController = TextEditingController(text: _model);
    var revealKey = false;
    var testingConnection = false;
    var testSucceeded = false;
    String? testFeedback;

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (sheetContext) => Scaffold(
          backgroundColor: const Color(0xFF111215),
          appBar: AppBar(
            backgroundColor: const Color(0xFF111215),
            title: const Text(
              'SETTINGS',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
          ),
          body: StatefulBuilder(
            builder: (context, setSheetState) => SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  22,
                  12,
                  22,
                  MediaQuery.viewInsetsOf(context).bottom + 24,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 22),
                      const Text(
                        'SYSTEM CONFIGURATION',
                        style: TextStyle(
                          color: _red,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Connect your Groq account',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Your key is stored in the device’s secure storage. Voice requests go directly from this app to Groq.',
                        style: TextStyle(
                          color: _muted,
                          height: 1.45,
                          fontSize: 13,
                        ),
                      ),
                      if (_buildApiKey.trim().isNotEmpty) ...[
                        const SizedBox(height: 10),
                        const Text(
                          'A build-time GROQ_API_KEY is available. A key saved on this device takes priority.',
                          style: TextStyle(
                            color: Color(0xFF8C8991),
                            height: 1.45,
                            fontSize: 11,
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      const _FieldLabel('GROQ API KEY'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: keyController,
                        obscureText: !revealKey,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          hintText: 'Paste your key here',
                          hintStyle: const TextStyle(color: Color(0xFF64636A)),
                          suffixIcon: IconButton(
                            tooltip: revealKey ? 'Hide key' : 'Show key',
                            onPressed: () =>
                                setSheetState(() => revealKey = !revealKey),
                            icon: Icon(
                              revealKey
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: _muted,
                              size: 19,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const _FieldLabel('MODEL'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: modelController,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          hintText: _defaultModel,
                          hintStyle: TextStyle(color: Color(0xFF64636A)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Default: llama-3.3-70b-versatile. Change it if your Groq account uses another model.',
                        style: TextStyle(
                          color: _muted,
                          fontSize: 11,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (testFeedback != null)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: testSucceeded
                                ? const Color(0xFF10251A)
                                : const Color(0xFF311519),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: testSucceeded
                                  ? const Color(0x6678DCA1)
                                  : const Color(0x66FF3344),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                testSucceeded
                                    ? Icons.check_circle_outline_rounded
                                    : Icons.error_outline_rounded,
                                size: 17,
                                color: testSucceeded
                                    ? const Color(0xFF78DCA1)
                                    : const Color(0xFFFF8991),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  testFeedback!,
                                  style: TextStyle(
                                    color: testSucceeded
                                        ? const Color(0xFFBDE8CC)
                                        : const Color(0xFFFFA0A7),
                                    fontSize: 12,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: testingConnection
                              ? null
                              : () async {
                                  final key = keyController.text.trim();
                                  final enteredModel = modelController.text
                                      .trim();
                                  setSheetState(() {
                                    testingConnection = true;
                                    testFeedback = null;
                                  });
                                  try {
                                    await _groq.testConnection(
                                      apiKey: key,
                                      model: enteredModel.isEmpty
                                          ? _defaultModel
                                          : enteredModel,
                                    );
                                    if (!sheetContext.mounted) return;
                                    setSheetState(() {
                                      testSucceeded = true;
                                      testFeedback =
                                          'Connection successful. Groq returned a reply for this model.';
                                    });
                                  } on GroqApiException catch (error) {
                                    if (!sheetContext.mounted) return;
                                    setSheetState(() {
                                      testSucceeded = false;
                                      testFeedback = error.message;
                                    });
                                  } on TimeoutException {
                                    if (!sheetContext.mounted) return;
                                    setSheetState(() {
                                      testSucceeded = false;
                                      testFeedback =
                                          'Groq took too long to respond. Check the connection and try again.';
                                    });
                                  } catch (_) {
                                    if (!sheetContext.mounted) return;
                                    setSheetState(() {
                                      testSucceeded = false;
                                      testFeedback =
                                          'Could not reach Groq. Check the key, model, and internet connection.';
                                    });
                                  } finally {
                                    if (sheetContext.mounted) {
                                      setSheetState(
                                        () => testingConnection = false,
                                      );
                                    }
                                  }
                                },
                          icon: testingConnection
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.network_check_rounded,
                                  size: 17,
                                ),
                          label: Text(
                            testingConnection
                                ? 'TESTING CONNECTION…'
                                : 'TEST GROQ CONNECTION',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFFF7B86),
                            side: const BorderSide(color: Color(0xAAFF3344)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: () async {
                            final key = keyController.text.trim();
                            final model = modelController.text.trim();
                            try {
                              if (key.isEmpty) {
                                await _secureStorage.delete(key: _apiKeyName);
                              } else {
                                await _secureStorage.write(
                                  key: _apiKeyName,
                                  value: key,
                                );
                              }
                              await _secureStorage.write(
                                key: _modelName,
                                value: model.isEmpty ? _defaultModel : model,
                              );
                              if (!mounted) return;
                              setState(() {
                                _apiKey = key.isEmpty
                                    ? _buildApiKey.trim()
                                    : key;
                                _model = model.isEmpty ? _defaultModel : model;
                                _settingsLoaded = true;
                              });
                              if (sheetContext.mounted) {
                                Navigator.of(sheetContext).pop();
                              }
                              _showNotice(
                                key.isEmpty
                                    ? 'Groq key removed from this device.'
                                    : 'Groq settings saved securely on this device.',
                              );
                            } catch (_) {
                              if (sheetContext.mounted) {
                                ScaffoldMessenger.of(sheetContext).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Could not save settings securely.',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                          icon: const Icon(
                            Icons.lock_outline_rounded,
                            size: 18,
                          ),
                          label: const Text(
                            'SAVE SETTINGS',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: _red,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () async {
                            await _secureStorage.delete(key: _apiKeyName);
                            if (!mounted) return;
                            setState(() => _apiKey = _buildApiKey.trim());
                            if (sheetContext.mounted) {
                              Navigator.of(sheetContext).pop();
                            }
                            _showNotice(
                              _buildApiKey.trim().isEmpty
                                  ? 'Groq key removed from this device.'
                                  : 'Saved key removed. The build-time key is still active.',
                            );
                          },
                          child: const Text(
                            'REMOVE SAVED KEY',
                            style: TextStyle(
                              color: Color(0xFFB1ADB4),
                              fontSize: 11,
                              letterSpacing: 1.3,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    keyController.dispose();
    modelController.dispose();
  }

  void _showNotice(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _clearConversation() {
    setState(() {
      _messages.clear();
      _liveTranscript = '';
      _notice = null;
    });
  }

  @override
  void dispose() {
    unawaited(_stopNativeServices());
    _groq.close();
    super.dispose();
  }

  Future<void> _stopNativeServices() async {
    try {
      await _speech.cancel();
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF111014), Color(0xFF08090B), Color(0xFF09090B)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final orbSize = math
                    .min(
                      constraints.maxWidth * 0.84,
                      math.max(200.0, constraints.maxHeight * 0.46),
                    )
                    .toDouble();

                return Column(
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 16),
                    _buildStatusStrip(),
                    Expanded(
                      flex: 13,
                      child: Center(
                        child: JarvisOrb(size: orbSize, phase: _phase),
                      ),
                    ),
                    Expanded(flex: 6, child: _buildTransmission()),
                    const SizedBox(height: 12),
                    _buildMicrophoneControl(),
                    const SizedBox(height: 8),
                    _buildFooter(),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 43,
          height: 43,
          decoration: BoxDecoration(
            color: const Color(0xFF241115),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: const Color(0x99FF3344)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22FF3344),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
          child: const Center(
            child: Text(
              'R',
              style: TextStyle(
                color: _red,
                fontSize: 25,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
                height: 1,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'JARVIS',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                letterSpacing: 3.2,
                height: 1.15,
              ),
            ),
            SizedBox(height: 3),
            Text(
              'ROG  /  VOICE SYSTEM',
              style: TextStyle(
                color: _muted,
                fontSize: 9,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Settings',
          onPressed: _openSettings,
          style: IconButton.styleFrom(
            foregroundColor: const Color(0xFFE8E2E4),
            backgroundColor: const Color(0xFF171619),
            side: const BorderSide(color: Color(0xFF393238)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
          icon: const Icon(Icons.tune_rounded, size: 19),
        ),
      ],
    );
  }

  Widget _buildStatusStrip() {
    final statusColor = switch (_phase) {
      JarvisPhase.ready => const Color(0xFF78DCA1),
      JarvisPhase.listening => _red,
      JarvisPhase.thinking => const Color(0xFFFFC46B),
      JarvisPhase.speaking => const Color(0xFF85B9FF),
    };

    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: statusColor,
            boxShadow: [
              BoxShadow(
                color: statusColor.withValues(alpha: 0.65),
                blurRadius: 8,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _phase.label,
          style: TextStyle(
            color: statusColor,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.6,
          ),
        ),
        const Spacer(),
        Icon(
          _apiKey.isNotEmpty ? Icons.link_rounded : Icons.link_off_rounded,
          size: 13,
          color: _apiKey.isNotEmpty ? const Color(0xFF77747C) : _red,
        ),
        const SizedBox(width: 5),
        Text(
          _apiKey.isNotEmpty ? 'GROQ LINK READY' : 'API KEY NEEDED',
          style: TextStyle(
            color: _apiKey.isNotEmpty ? _muted : const Color(0xFFFF7882),
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.05,
          ),
        ),
      ],
    );
  }

  Widget _buildTransmission() {
    final recentMessages = _messages.reversed.take(6).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0xCC111215),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF29272D)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.terminal_rounded, color: _red, size: 15),
              const SizedBox(width: 7),
              const Text(
                'TRANSMISSION FEED',
                style: TextStyle(
                  color: Color(0xFFD9D5D8),
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
              const Spacer(),
              if (_messages.isNotEmpty)
                GestureDetector(
                  onTap: _clearConversation,
                  child: const Text(
                    'CLEAR',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                )
              else
                const Icon(Icons.more_horiz_rounded, color: _muted, size: 17),
            ],
          ),
          const SizedBox(height: 8),
          if (_isListening && _liveTranscript.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 7),
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: const Color(0xFF241115),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _liveTranscript,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          Expanded(
            child: recentMessages.isEmpty
                ? _buildEmptyFeed()
                : ListView.builder(
                    reverse: true,
                    padding: EdgeInsets.zero,
                    itemCount: recentMessages.length,
                    itemBuilder: (context, index) {
                      final message = recentMessages[index];
                      final isUser = message.role == 'user';
                      return Align(
                        alignment: isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 300),
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: message.isError
                                ? const Color(0xFF311519)
                                : isUser
                                ? const Color(0xFF281519)
                                : const Color(0xFF1B1B20),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: message.isError
                                  ? const Color(0x66FF3344)
                                  : isUser
                                  ? const Color(0x33FF4654)
                                  : const Color(0xFF2C2B31),
                            ),
                          ),
                          child: Text(
                            message.content,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: message.isError
                                  ? const Color(0xFFFFA0A7)
                                  : const Color(0xFFE7E4E7),
                              fontSize: 11,
                              height: 1.35,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_notice != null && !_isListening)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _notice!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFFF9BA3),
                    fontSize: 10,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyFeed() {
    final needsKey = _apiKey.isEmpty;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            needsKey
                ? 'CONFIGURE GROQ TO GET STARTED'
                : 'YOUR CONVERSATION APPEARS HERE',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF9E9AA1),
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            needsKey
                ? 'Open Settings and add your API key'
                : 'Tap the mic and speak naturally',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF66636B), fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildMicrophoneControl() {
    final busy = _phase == JarvisPhase.thinking;
    final buttonColor = _isListening ? const Color(0xFFFF4857) : _red;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Clear conversation',
          onPressed: _messages.isEmpty ? null : _clearConversation,
          style: IconButton.styleFrom(
            foregroundColor: const Color(0xFF98939B),
            disabledForegroundColor: const Color(0xFF45434A),
            backgroundColor: const Color(0xFF151417),
            side: const BorderSide(color: Color(0xFF302D32)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
        ),
        const SizedBox(width: 20),
        Semantics(
          button: true,
          label: _isListening ? 'Stop listening' : 'Start voice command',
          child: GestureDetector(
            onTap: busy ? null : _onMicPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _isListening
                      ? const [Color(0xFFFF6470), Color(0xFFCE1E31)]
                      : const [Color(0xFFFF4A59), Color(0xFFD4192B)],
                ),
                border: Border.all(color: const Color(0xFFFF8991), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: buttonColor.withValues(
                      alpha: _isListening ? 0.55 : 0.36,
                    ),
                    blurRadius: _isListening ? 28 : 20,
                    spreadRadius: _isListening ? 3 : 1,
                  ),
                ],
              ),
              child: Center(
                child: busy
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                        color: Colors.white,
                        size: 29,
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 20),
        IconButton(
          tooltip: 'Settings',
          onPressed: _openSettings,
          style: IconButton.styleFrom(
            foregroundColor: const Color(0xFF98939B),
            backgroundColor: const Color(0xFF151417),
            side: const BorderSide(color: Color(0xFF302D32)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: const Icon(Icons.settings_outlined, size: 18),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    final label = switch (_phase) {
      JarvisPhase.ready =>
        _apiKey.isEmpty
            ? 'ADD YOUR GROQ KEY IN SETTINGS'
            : 'TAP THE MIC TO START A VOICE SESSION',
      JarvisPhase.listening => 'TAP AGAIN TO SEND YOUR QUESTION',
      JarvisPhase.thinking => 'SECURE CHANNEL  /  GROQ',
      JarvisPhase.speaking => 'VOICE RESPONSE IN PROGRESS',
    };

    return Text(
      label,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Color(0xFF68656C),
        fontSize: 9,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

class ConversationMessage {
  const ConversationMessage({
    required this.role,
    required this.content,
    this.isError = false,
  });

  final String role;
  final String content;
  final bool isError;
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFFDAD5D8),
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.4,
      ),
    );
  }
}
