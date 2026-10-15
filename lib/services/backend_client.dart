import 'package:http/http.dart' as http;
import 'package:http/retry.dart';

/// One bounded retry for safe reads. Writes always use the original transport
/// once, preserving request identity and the caller's existing timeout budget.
class BackendClient extends http.BaseClient {
  BackendClient({http.Client? network, Duration? retryDelay})
    : _network = network ?? http.Client() {
    _reads = RetryClient(
      _network,
      retries: 1,
      delay: (_) => retryDelay ?? const Duration(seconds: 1),
      when: (response) {
        // Never retry sooner than a provider/server's Retry-After. Long or
        // date-form cooldowns are surfaced for a later explicit user retry.
        final retryAfter = response.headers['retry-after'];
        if (retryAfter != null) {
          final seconds = int.tryParse(retryAfter);
          if (seconds == null || seconds > 1 || seconds < 0) return false;
        }
        return const {429, 500, 502, 503, 504}.contains(response.statusCode);
      },
      whenError: (error, _) => error is http.ClientException,
    );
  }

  final http.Client _network;
  late final RetryClient _reads;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      return await (request.method == 'GET'
          ? _reads.send(request)
          : _network.send(request));
    } on http.ClientException {
      throw http.ClientException(
        'Could not reach YatraCanvas. Check your connection and retry. The server may be starting.',
        request.url,
      );
    }
  }

  @override
  void close() => _reads.close();
}
