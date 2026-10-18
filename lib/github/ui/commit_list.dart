import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models.dart';

class CommitListPage extends StatefulWidget {
  final String repo;
  final String token;
  final GitHubApiClient client;

  const CommitListPage({
    super.key,
    required this.repo,
    required this.token,
    required this.client,
  });

  @override
  State<CommitListPage> createState() => _CommitListPageState();
}

class _CommitListPageState extends State<CommitListPage> {
  List<GHCommit> commits = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    final result = await widget.client.listCommits(widget.token, widget.repo, 'HEAD');
    if (!mounted) return;
    result.fold(
      (list) => commits = list,
      (message) => error = message,
    );
    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Commits · ${widget.repo}')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(error!),
                      TextButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: commits.length,
                    itemBuilder: (context, i) {
                      final c = commits[i];
                      final author = c.author.length > 24 ? c.author.substring(0, 24) : c.author;
                      final shortSha = c.sha.length >= 7 ? c.sha.substring(0, 7) : c.sha;
                      return ListTile(
                        leading: const Icon(Icons.commit, size: 18),
                        title: Text(c.message.split('\n').first,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('$author · $shortSha'),
                        trailing: Text(_fmt(c.date), style: const TextStyle(fontSize: 11)),
                      );
                    },
                  ),
                ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
