import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class GroqClient {
  GroqClient({http.Client? client}) : _http = client ?? http.Client();

  static final Uri _endpoint = Uri.parse(
    'https://api.groq.com/openai/v1/chat/completions',
  );

  final http.Client _http;

  Future<String> complete({
    required String apiKey,
    required String model,
    required List<Map<String, String>> conversation,
    int maxTokens = 900,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const GroqApiException(
        'Add your Groq API key in Settings to begin.',
      );
    }

    final response = await _http
        .post(
          _endpoint,
          headers: {
            'Authorization': 'Bearer ${apiKey.trim()}',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'messages': [
              {
                'role': 'system',
                'content':
                    'You are JARVIS, a concise, capable voice assistant. '
                    'Reply naturally in clear spoken language. Avoid markdown '
                    'tables and keep answers focused unless more detail is asked for.',
              },
              ...conversation,
            ],
            'temperature': 0.7,
            'max_tokens': maxTokens,
            'stream': false,
          }),
        )
        .timeout(const Duration(seconds: 40));

    final Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('The response was not a JSON object.');
      }
      payload = decoded;
    } on FormatException {
      throw const GroqApiException(
        'Groq returned an unreadable response. Check the model setting and try again.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GroqApiException(_messageForFailure(response.statusCode, payload));
    }

    final choices = payload['choices'];
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      final message = (choices.first as Map)['message'];
      if (message is Map) {
        final content = message['content'];
        if (content is String && content.trim().isNotEmpty) {
          return content.trim();
        }
      }
    }

    throw const GroqApiException(
      'Groq returned an empty reply. Please try asking that another way.',
    );
  }

  Future<void> testConnection({
    required String apiKey,
    required String model,
  }) async {
    await complete(
      apiKey: apiKey,
      model: model,
      maxTokens: 24,
      conversation: const [
        {
          'role': 'user',
          'content': 'Reply with only: JARVIS connection successful.',
        },
      ],
    );
  }

  String _messageForFailure(int statusCode, Map<String, dynamic> payload) {
    if (statusCode == 401 || statusCode == 403) {
      return 'Groq rejected the API key. Check it in Settings and try again.';
    }
    if (statusCode == 429) {
      return 'Groq is rate-limiting requests. Wait a moment and try again.';
    }
    if (statusCode == 404) {
      return 'That Groq model was not found. Check the model name in Settings.';
    }

    final error = payload['error'];
    final detail = error is Map ? error['message']?.toString() : null;
    if (detail != null && detail.isNotEmpty) {
      return 'Groq request failed ($statusCode): $detail';
    }
    return 'Groq request failed ($statusCode). Check your connection and try again.';
  }

  void close() => _http.close();
}

class GroqApiException implements Exception {
  const GroqApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
