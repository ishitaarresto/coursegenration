import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import '../../../core/services/chat_service.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/arresto_ai_logo.dart';

/// Context about the lesson the learner is currently watching, passed into the
/// AI companion so it can answer about *this* lesson and the current section.
class AiLessonContext {
  final String lessonId;
  final String courseId;
  final String lessonTitle;
  final int timestampSecs;
  final String? transcript;

  const AiLessonContext({
    required this.lessonId,
    required this.courseId,
    required this.lessonTitle,
    required this.timestampSecs,
    this.transcript,
  });

  String get timestampLabel {
    final m = timestampSecs ~/ 60;
    final s = timestampSecs % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

enum _Voice { idle, listening, transcribing, processing, speaking }

class ArrestoAIPanel extends StatefulWidget {
  final String? seedQuestion;
  final AiLessonContext? lessonContext;
  const ArrestoAIPanel({super.key, this.seedQuestion, this.lessonContext});

  @override
  State<ArrestoAIPanel> createState() => _ArrestoAIPanelState();
}

class _ArrestoAIPanelState extends State<ArrestoAIPanel> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_Message> _messages = [];
  bool _typing = false;

  // ── Voice: speech-to-text ──
  final SpeechToText _stt = SpeechToText();
  bool _sttReady = false;
  bool _sttDenied = false;
  bool _listening = false;
  bool _sttProcessing = false;       // true while backend is transcribing
  String? _voiceError;

  // ── Web MediaRecorder (used on web instead of speech_to_text) ──
  html.MediaRecorder? _recorder;
  html.MediaStream? _micStream;
  final List<html.Blob> _audioChunks = [];

  // ── Voice: text-to-speech ──
  final FlutterTts _tts = FlutterTts();
  int? _speakingIndex;
  bool _paused = false;

  bool get _speaking => _speakingIndex != null && !_paused;

  _Voice get _voiceState {
    if (_listening) return _Voice.listening;
    if (_sttProcessing) return _Voice.transcribing;
    if (_typing) return _Voice.processing;
    if (_speaking) return _Voice.speaking;
    return _Voice.idle;
  }

  @override
  void initState() {
    super.initState();
    _initTts();
    // Defer STT init to first mic tap — requesting permission immediately on
    // panel open can be blocked silently by some browsers.
    if (widget.seedQuestion != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _send(widget.seedQuestion!);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _stt.cancel();
    _tts.stop();
    _recorder?.stop();
    _micStream?.getTracks().forEach((t) => t.stop());
    super.dispose();
  }

  void _track(String event) {
    final ctx = widget.lessonContext;
    debugPrint('[analytics] ai_companion:$event '
        'lesson=${ctx?.lessonId ?? "-"} course=${ctx?.courseId ?? "-"} '
        't=${ctx?.timestampSecs ?? "-"}');
  }

  // ── Speech-to-text ──────────────────────────────────────────────────────────
  //
  // On web: uses MediaRecorder (browser API) → POSTs webm to backend Sarvam STT.
  //         No Google servers, no VPN issues, works on any network.
  // On mobile: keeps speech_to_text (native STT).

  Future<void> _toggleListen() async {
    _clearVoiceError();
    if (kIsWeb) {
      if (_listening) {
        _stopWebRecording();
      } else {
        await _startWebRecording();
      }
    } else {
      // Mobile path — native speech_to_text
      if (_listening) {
        await _stt.stop();
        setState(() => _listening = false);
        return;
      }
      if (!_sttReady) await _initSttMobile();
      if (!_sttReady) {
        setState(() => _voiceError = 'Speech recognition isn\'t available on this device.');
        return;
      }
      await _stopSpeak();
      _track('voice_listen_start');
      setState(() => _listening = true);
      await _stt.listen(
        onResult: (SpeechRecognitionResult r) {
          if (!mounted) return;
          setState(() => _controller.text = r.recognizedWords);
          if (r.finalResult) {
            final text = r.recognizedWords.trim();
            setState(() => _listening = false);
            if (text.isNotEmpty) {
              _track('voice_listen_result');
              _send(text);
              _controller.clear();
            }
          }
        },
        listenOptions: SpeechListenOptions(
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 4),
          partialResults: true,
          cancelOnError: false,
        ),
      );
    }
  }

  // ── Web: MediaRecorder → Sarvam backend STT ─────────────────────────────────

  Future<void> _startWebRecording() async {
    _audioChunks.clear();
    try {
      final stream = await html.window.navigator.mediaDevices!
          .getUserMedia({'audio': true, 'video': false});
      _micStream = stream;

      // Prefer opus/webm; fall back to browser default
      final mimeType = html.MediaRecorder.isTypeSupported('audio/webm;codecs=opus')
          ? 'audio/webm;codecs=opus'
          : '';
      final recorder = mimeType.isNotEmpty
          ? html.MediaRecorder(stream, {'mimeType': mimeType})
          : html.MediaRecorder(stream);
      _recorder = recorder;

      recorder.addEventListener('dataavailable', (event) {
        final blob = (event as html.BlobEvent).data;
        if (blob != null && blob.size > 0) _audioChunks.add(blob);
      });

      recorder.addEventListener('stop', (_) {
        stream.getTracks().forEach((t) => t.stop());
        _micStream = null;
        _recorder = null;
        if (_audioChunks.isNotEmpty) {
          _transcribeChunks();
        } else {
          if (mounted) {
            setState(() {
              _sttProcessing = false;
              _voiceError = 'No audio recorded. Hold the mic button while speaking.';
            });
          }
        }
      });

      recorder.start();
      await _stopSpeak();
      _track('voice_listen_start');
      if (mounted) setState(() => _listening = true);
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (mounted) {
        setState(() {
          _sttDenied = msg.contains('permission') || msg.contains('denied') || msg.contains('notallowed');
          _voiceError = _sttDenied
              ? 'Microphone access denied. Click the lock icon in your browser address bar and allow microphone.'
              : 'Could not start microphone. Please check your browser settings.';
        });
      }
    }
  }

  void _stopWebRecording() {
    if (_recorder != null) {
      _recorder!.stop();
      if (mounted) setState(() { _listening = false; _sttProcessing = true; });
    }
  }

  Future<void> _transcribeChunks() async {
    try {
      // Merge all recorded chunks into one Blob
      final blob = html.Blob(_audioChunks, 'audio/webm');
      _audioChunks.clear();

      // FileReader.readAsArrayBuffer returns a JS ArrayBuffer → ByteBuffer in Dart
      final completer = Completer<Uint8List>();
      final reader = html.FileReader();
      reader.onLoad.listen((_) {
        final buf = reader.result as ByteBuffer;
        completer.complete(buf.asUint8List());
      });
      reader.onError.listen((_) {
        completer.completeError('FileReader failed to read audio');
      });
      reader.readAsArrayBuffer(blob);
      final bytes = await completer.future;

      _track('voice_listen_result');
      final text = await ChatService.transcribeAudio(bytes);

      if (!mounted) return;
      if (text.isEmpty) {
        setState(() {
          _sttProcessing = false;
          _voiceError = 'Didn\'t catch that — please speak again.';
        });
      } else {
        setState(() {
          _sttProcessing = false;
          _controller.text = text;
        });
        _send(text);
        _controller.clear();
      }
    } catch (e) {
      debugPrint('[STT] transcription error: $e');
      if (!mounted) return;
      setState(() {
        _sttProcessing = false;
        // Show the real error so it's visible during debugging
        _voiceError = 'Transcription error: $e';
      });
    }
  }

  // ── Mobile: speech_to_text init ─────────────────────────────────────────────

  Future<void> _initSttMobile() async {
    try {
      _sttReady = await _stt.initialize(
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'done' || status == 'notListening') {
            setState(() => _listening = false);
          }
        },
        onError: (err) {
          if (!mounted) return;
          final msg = err.errorMsg.toLowerCase();
          setState(() {
            _listening = false;
            _sttDenied = msg.contains('denied') ||
                msg.contains('not-allowed') ||
                msg.contains('permission');
            _voiceError = 'Voice input error: ${err.errorMsg}. Try again or type your question.';
          });
        },
      );
    } catch (e) {
      _sttReady = false;
    }
    if (mounted) setState(() {});
  }

  void _clearVoiceError() {
    if (_voiceError != null) setState(() => _voiceError = null);
  }

  // ── Text-to-speech ──────────────────────────────────────────────────────────
  Future<void> _initTts() async {
    // Language MUST be set before speak() on Chrome — without it, the browser
    // can't select a voice and speak() fires silently with no audio.
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.48);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    _tts.setCompletionHandler(() {
      if (mounted) setState(() { _speakingIndex = null; _paused = false; });
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() { _speakingIndex = null; _paused = false; });
    });
    _tts.setErrorHandler((e) {
      debugPrint('[TTS] error: $e');
      if (mounted) setState(() { _speakingIndex = null; _paused = false; });
    });
  }

  String _stripForSpeech(String md) => md
      .replaceAll('**', '')
      .replaceAll('*', '')
      .replaceAll('`', '')
      .replaceAll(RegExp(r'#{1,6}\s'), '')
      .replaceAll(RegExp(r'[•✨📍📝①②③④⑤]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Future<void> _speak(int index) async {
    if (_listening) await _stt.stop();
    await _tts.stop();
    // Re-apply language before each speak call — on Chrome, voices load
    // asynchronously so the first setLanguage() in initState may have found
    // an empty voice list. By the time the user taps "Listen", voices are ready.
    if (kIsWeb) await _tts.setLanguage('en-US');
    _track('voice_speak');
    setState(() { _speakingIndex = index; _paused = false; });
    await _tts.speak(_stripForSpeech(_messages[index].text));
  }

  Future<void> _pauseResume(int index) async {
    if (_paused) {
      setState(() => _paused = false);
      await _tts.speak(_stripForSpeech(_messages[index].text));
    } else {
      await _tts.pause();
      setState(() => _paused = true);
    }
  }

  Future<void> _stopSpeak() async {
    await _tts.stop();
    if (mounted) setState(() { _speakingIndex = null; _paused = false; });
  }

  // ── Chat ────────────────────────────────────────────────────────────────────
  void _send(String text) async {
    if (text.trim().isEmpty) return;
    _track('ask');
    setState(() {
      _messages.add(_Message(text: text, isUser: true));
      _typing = true;
    });
    _scrollToBottom();

    // Build conversation history from previous messages (last 6, before the one just added)
    final prevMessages = _messages.sublist(0, _messages.length - 1);
    final historyWindow = prevMessages.length > 6
        ? prevMessages.sublist(prevMessages.length - 6)
        : prevMessages;
    final history = historyWindow
        .map((m) => {'role': m.isUser ? 'user' : 'assistant', 'text': m.text})
        .toList();

    try {
      final answer = await ChatService.ask(
        text,
        lessonContext: widget.lessonContext,
        history: history,
      );
      if (!mounted) return;
      setState(() {
        _typing = false;
        _messages.add(_Message(text: answer, isUser: false));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _typing = false;
        _messages.add(_Message(
          text: 'Sorry, I could not reach the AI right now. Please check that the backend is running.',
          isUser: false,
        ));
      });
    }
    _scrollToBottom();
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
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: const BoxDecoration(
        color: ArrestoColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                color: ArrestoColors.lineStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(
              color: ArrestoColors.ink,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                const ArrestoAiLogo(size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Arresto AI', style: ArrestoText.h4(color: Colors.white)),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: ArrestoColors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              widget.lessonContext != null
                                  ? 'On: ${widget.lessonContext!.lessonTitle}'
                                  : 'Online — Safety training assistant',
                              overflow: TextOverflow.ellipsis,
                              style: ArrestoText.xs(color: Colors.white54),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // Messages
          Expanded(
            child: _messages.isEmpty
                ? _EmptyState(onChip: _send, lessonContext: widget.lessonContext)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
                    itemCount: _messages.length + (_typing ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (i == _messages.length) return const _TypingIndicator();
                      final msg = _messages[i];
                      return _MessageBubble(
                        msg: msg,
                        canSpeak: !msg.isUser,
                        isSpeaking: _speakingIndex == i && !_paused,
                        isPaused: _speakingIndex == i && _paused,
                        onSpeak: () => _speak(i),
                        onPauseResume: () => _pauseResume(i),
                        onStop: _stopSpeak,
                      );
                    },
                  ),
          ),
          // Voice status / error banner
          if (_voiceError != null)
            _VoiceErrorBar(message: _voiceError!, onRetry: _toggleListen, onDismiss: _clearVoiceError)
          else if (_voiceState != _Voice.idle)
            _VoiceStatusBar(state: _voiceState),
          // Input bar
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: ArrestoColors.line)),
            ),
            child: Row(
              children: [
                _MicButton(
                  listening: _listening,
                  disabled: _sttDenied,
                  transcribing: _sttProcessing,
                  onTap: _toggleListen,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Ask Arresto AI, or tap the mic…',
                      hintStyle: ArrestoText.small().copyWith(color: ArrestoColors.textMuted),
                      filled: true,
                      fillColor: ArrestoColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: ArrestoColors.line),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: ArrestoColors.line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: ArrestoColors.amber, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    onSubmitted: (v) {
                      _send(v);
                      _controller.clear();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    _send(_controller.text);
                    _controller.clear();
                  },
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [ArrestoColors.amber, ArrestoColors.orange],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: ArrestoColors.amber.withOpacity(0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.send_rounded, size: 18, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Microphone button ─────────────────────────────────────────────────────────
class _MicButton extends StatefulWidget {
  final bool listening;
  final bool disabled;
  final bool transcribing;
  final VoidCallback onTap;
  const _MicButton({required this.listening, required this.disabled, required this.transcribing, required this.onTap});

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listening = widget.listening;
    final transcribing = widget.transcribing;
    return Tooltip(
      message: widget.disabled
          ? 'Microphone blocked — enable it in site settings'
          : transcribing
              ? 'Transcribing…'
              : listening
                  ? 'Tap to stop recording'
                  : 'Tap to speak',
      child: GestureDetector(
        onTap: widget.disabled || transcribing ? null : widget.onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (listening)
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) {
                    final t = _pulse.value;
                    return Container(
                      width: 28 + 16 * t,
                      height: 28 + 16 * t,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ArrestoColors.red.withValues(alpha: (1 - t) * 0.35),
                      ),
                    );
                  },
                ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.disabled
                      ? ArrestoColors.bg2
                      : transcribing
                          ? ArrestoColors.orange.withValues(alpha: 0.12)
                          : listening
                              ? ArrestoColors.red
                              : ArrestoColors.bg2,
                  border: Border.all(
                    color: transcribing
                        ? ArrestoColors.orange
                        : listening
                            ? ArrestoColors.red
                            : ArrestoColors.line,
                  ),
                ),
                child: transcribing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: ArrestoColors.orange,
                        ),
                      )
                    : Icon(
                        widget.disabled
                            ? Icons.mic_off_rounded
                            : listening
                                ? Icons.stop_rounded
                                : Icons.mic_rounded,
                        size: 20,
                        color: listening ? Colors.white : ArrestoColors.textSecondary,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Voice status pill ─────────────────────────────────────────────────────────
class _VoiceStatusBar extends StatelessWidget {
  final _Voice state;
  const _VoiceStatusBar({required this.state});

  @override
  Widget build(BuildContext context) {
    late final String label;
    late final IconData icon;
    late final Color color;
    switch (state) {
      case _Voice.listening:
        label = 'Recording… tap mic to stop';
        icon = Icons.mic_rounded;
        color = ArrestoColors.red;
        break;
      case _Voice.transcribing:
        label = 'Transcribing…';
        icon = Icons.sync_rounded;
        color = ArrestoColors.orange;
        break;
      case _Voice.processing:
        label = 'Processing…';
        icon = Icons.bubble_chart_rounded;
        color = ArrestoColors.orange;
        break;
      case _Voice.speaking:
        label = 'Speaking…';
        icon = Icons.volume_up_rounded;
        color = ArrestoColors.green;
        break;
      case _Voice.idle:
        label = '';
        icon = Icons.circle;
        color = ArrestoColors.textMuted;
        break;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: color.withValues(alpha: 0.08),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(label, style: ArrestoText.small(color: color).copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _VoiceErrorBar extends StatelessWidget {
  final String message;
  final VoidCallback onRetry, onDismiss;
  const _VoiceErrorBar({required this.message, required this.onRetry, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: ArrestoColors.redSoft,
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, size: 16, color: ArrestoColors.red),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: ArrestoText.xs(color: ArrestoColors.red))),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: Size.zero),
            child: Text('Retry',
                style: ArrestoText.xs(color: ArrestoColors.red)
                    .copyWith(fontWeight: FontWeight.w700)),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(Icons.close_rounded, size: 16, color: ArrestoColors.red),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final ValueChanged<String> onChip;
  final AiLessonContext? lessonContext;
  const _EmptyState({required this.onChip, this.lessonContext});

  static const _generic = [
    'What is the minimum anchor strength?',
    'How do I inspect a full-body harness?',
    'Explain the 6-foot free-fall rule.',
  ];

  @override
  Widget build(BuildContext context) {
    final lc = lessonContext;
    final suggestions = lc != null
        ? [
            '✨ Summarize this lesson',
            '📍 Explain current section (${lc.timestampLabel})',
            '📝 Generate quiz questions',
          ]
        : _generic;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const ArrestoAiLogo(size: 56),
            const SizedBox(height: 12),
            Text(
              lc != null
                  ? 'Ask me about "${lc.lessonTitle}"'
                  : 'Ask me anything about safety training',
              style: ArrestoText.h4(color: ArrestoColors.ink),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text('Type or tap the mic to talk',
                style: ArrestoText.xs(), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: suggestions.map((s) {
                return GestureDetector(
                  onTap: () => onChip(s),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: ArrestoColors.bg2,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: ArrestoColors.line),
                    ),
                    child: Text(s,
                        style: ArrestoText.small().copyWith(fontWeight: FontWeight.w500)),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Message bubble (markdown for AI, plain text for user) ─────────────────────
class _MessageBubble extends StatelessWidget {
  final _Message msg;
  final bool canSpeak, isSpeaking, isPaused;
  final VoidCallback onSpeak, onPauseResume, onStop;

  const _MessageBubble({
    required this.msg,
    required this.canSpeak,
    required this.isSpeaking,
    required this.isPaused,
    required this.onSpeak,
    required this.onPauseResume,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final active = isSpeaking || isPaused;
    return Column(
      crossAxisAlignment: msg.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: msg.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!msg.isUser) ...[
              const ArrestoAiLogo(size: 28),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Container(
                margin: const EdgeInsets.only(bottom: 4),
                constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.72),
                decoration: BoxDecoration(
                  color: msg.isUser ? ArrestoColors.amber : ArrestoColors.surface,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(msg.isUser ? 16 : 4),
                    bottomRight: Radius.circular(msg.isUser ? 4 : 16),
                  ),
                  border: msg.isUser ? null : Border.all(color: ArrestoColors.cardBorder),
                  boxShadow: msg.isUser ? null : ArrestoColors.sh1,
                ),
                child: msg.isUser
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        child: Text(
                          msg.text,
                          style: ArrestoText.body(color: ArrestoColors.ink)
                              .copyWith(fontWeight: FontWeight.w500),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                        child: MarkdownBody(
                          data: msg.text,
                          selectable: true,
                          styleSheet: _mdSheet(),
                        ),
                      ),
              ),
            ),
          ],
        ),
        // TTS controls under AI replies
        if (canSpeak)
          Padding(
            padding: const EdgeInsets.only(left: 36, bottom: 12),
            child: Row(
              children: [
                if (!active)
                  _voiceChip(Icons.volume_up_rounded, 'Listen', onSpeak)
                else ...[
                  _voiceChip(
                      isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                      isPaused ? 'Resume' : 'Pause',
                      onPauseResume),
                  const SizedBox(width: 6),
                  _voiceChip(Icons.stop_rounded, 'Stop', onStop),
                ],
              ],
            ),
          ),
      ],
    );
  }

  MarkdownStyleSheet _mdSheet() {
    final body = ArrestoText.body(color: ArrestoColors.ink);
    final small = ArrestoText.small(color: ArrestoColors.textSecondary);
    return MarkdownStyleSheet(
      p: body,
      strong: body.copyWith(fontWeight: FontWeight.w700, color: ArrestoColors.ink),
      em: body.copyWith(fontStyle: FontStyle.italic),
      h1: ArrestoText.h3(color: ArrestoColors.ink),
      h2: ArrestoText.h4(color: ArrestoColors.ink),
      h3: ArrestoText.bodyBold(color: ArrestoColors.ink),
      listBullet: body,
      tableBody: small,
      blockquote: body.copyWith(
          color: ArrestoColors.textMuted, fontStyle: FontStyle.italic),
      code: body.copyWith(
        fontFamily: 'monospace',
        color: ArrestoColors.orange,
      ),
      codeblockDecoration: BoxDecoration(
        color: ArrestoColors.amberSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ArrestoColors.amber.withOpacity(0.3)),
      ),
      blockquoteDecoration: BoxDecoration(
        color: ArrestoColors.bg2,
        borderRadius: BorderRadius.circular(6),
        border: const Border(
          left: BorderSide(color: ArrestoColors.amber, width: 3),
        ),
      ),
      pPadding: const EdgeInsets.only(bottom: 4),
      listIndent: 18,
      blockquotePadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      codeblockPadding: const EdgeInsets.all(12),
    );
  }

  Widget _voiceChip(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: ArrestoColors.bg2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: ArrestoColors.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: ArrestoColors.textSecondary),
          const SizedBox(width: 4),
          Text(label, style: ArrestoText.xs()),
        ]),
      ),
    );
  }
}

// ── Typing indicator ──────────────────────────────────────────────────────────
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with TickerProviderStateMixin {
  final List<AnimationController> _controllers = [];

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 3; i++) {
      final c = AnimationController(
          vsync: this, duration: const Duration(milliseconds: 600))
        ..repeat(reverse: true);
      Future.delayed(Duration(milliseconds: i * 200), () {
        if (mounted) c.forward();
      });
      _controllers.add(c);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const ArrestoAiLogo(size: 28),
        const SizedBox(width: 8),
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: ArrestoColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ArrestoColors.cardBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              return AnimatedBuilder(
                animation: _controllers[i],
                builder: (_, __) => Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: ArrestoColors.amber
                        .withValues(alpha: 0.3 + 0.7 * _controllers[i].value),
                    shape: BoxShape.circle,
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _Message {
  final String text;
  final bool isUser;
  const _Message({required this.text, required this.isUser});
}
