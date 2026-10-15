import 'package:http/http.dart' as http;

import '../models/auth_controller.dart';
import '../config/api_config.dart';
import 'backend_client.dart';

class AuthenticatedClient extends http.BaseClient {
  AuthenticatedClient({http.Client? network, AuthController? auth})
    : network = network ?? BackendClient(),
      auth = auth ?? AuthController.instance;
  final http.Client network;
  final AuthController auth;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final base = Uri.parse(ApiConfig.baseUrl);
    if (request.url.origin == base.origin && auth.session != null) {
      request.headers['Authorization'] = 'Bearer ${auth.session!.token}';
    }
    final response = await network.send(request);
    if (request.url.origin == base.origin &&
        response.statusCode == 401 &&
        auth.signedIn) {
      await auth.logout();
    }
    return response;
  }

  @override
  void close() {
    network.close();
    super.close();
  }
}
