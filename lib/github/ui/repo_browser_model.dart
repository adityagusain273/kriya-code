import 'package:flutter/foundation.dart';

import '../api_client.dart';
import '../models.dart';

class RepoBrowserModel extends ChangeNotifier {
  final GitHubApiClient client;
  final String token;

  List<GHRepo> repos = [];
  bool loading = false;
  String? error;

  RepoBrowserModel(this.client, this.token);

  Future<void> loadRepos() async {
    loading = true;
    error = null;
    notifyListeners();
    final result = await client.listRepos(token);
    result.fold(
      (list) => repos = list,
      (message) => error = message,
    );
    loading = false;
    notifyListeners();
  }
}
