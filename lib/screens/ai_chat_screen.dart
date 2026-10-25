import 'package:flutter/material.dart';

import '../models/record_summary.dart';
import '../services/ai_narrative_service.dart';
import '../services/gait_screening_model.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// Follow-up Q&A about one session ("why are my numbers elevated", "what
/// should I do") -- a thin chat UI over `AiNarrativeService.sendChatMessage`.
/// All conversation state lives here on the client; each send resends the
/// session's metrics plus the transcript so far to the (stateless)
/// `chatAboutSession` Cloud Function.
class AiChatScreen extends StatefulWidget {
  final RecordSummary summary;
  final String? recoverySummary;
  final String? personalBaselineSummary;
  final GaitScreeningResult? screening;

  const AiChatScreen({
    super.key,
    required this.summary,
    this.recoverySummary,
    this.personalBaselineSummary,
    this.screening,
  });

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _messages = <ChatMessage>[];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _messages.add(ChatMessage(role: ChatRole.user, content: text));
      _controller.clear();
      _sending = true;
      _error = null;
    });
    _scrollToBottom();

    try {
      final reply = await AiNarrativeService.sendChatMessage(
        summary: widget.summary,
        history: _messages,
        recoverySummary: widget.recoverySummary,
        personalBaselineSummary: widget.personalBaselineSummary,
        screening: widget.screening,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(role: ChatRole.assistant, content: reply));
        _sending = false;
      });
      _scrollToBottom();
    } on AiNarrativeException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _sending = false;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: const Text('Ask about this session')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: p.surface2,
            child: Text(
              'Explains this session\'s numbers in plain language. Not a diagnosis, '
              'and it won\'t tell you what treatment to follow -- for that, talk to '
              'your clinician or physiotherapist.',
              style: TextStyle(color: p.textSecondary, fontSize: 11),
            ),
          ),
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Ask something like "why is my stride asymmetry elevated?" or '
                        '"what does my personal baseline deviation mean?"',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: p.textTertiary),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) => _MessageBubble(message: _messages[i]),
                  ),
          ),
          if (_sending)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(_error!, style: const TextStyle(color: AppColors.warning, fontSize: 12)),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'Ask about this session...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _send(),
                      textInputAction: TextInputAction.send,
                      enabled: !_sending,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send, color: AppColors.primary),
                    onPressed: _sending ? null : _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isUser = message.role == ChatRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isUser ? AppColors.primary.withValues(alpha: 0.15) : p.surface2,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(message.content, style: TextStyle(color: p.text, fontSize: 13)),
      ),
    );
  }
}
