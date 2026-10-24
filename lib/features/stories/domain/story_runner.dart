import '../../../content/models/story.dart';

/// One visible step the learner has passed through.
class StoryStep {
  const StoryStep(this.nodeId, {this.choiceId, this.wrongChoiceIds = const []});
  final String nodeId;

  /// The accepted choice at a choice node.
  final String? choiceId;

  /// Wrong choices tried before the accepted one (feeds the recap).
  final List<String> wrongChoiceIds;

  Map<String, Object?> toJson() => {
        'n': nodeId,
        if (choiceId != null) 'c': choiceId,
        if (wrongChoiceIds.isNotEmpty) 'w': wrongChoiceIds,
      };

  factory StoryStep.fromJson(Map<String, dynamic> j) => StoryStep(
        j['n'] as String,
        choiceId: j['c'] as String?,
        wrongChoiceIds: ((j['w'] as List?) ?? const []).cast<String>(),
      );
}

class StoryState {
  const StoryState({required this.nodeId, required this.flags, required this.history, this.pendingWrong = const []});
  final String nodeId;
  final Set<String> flags;

  /// Completed steps, oldest first. Does not include [nodeId].
  final List<StoryStep> history;

  /// Wrong choices tried at the current choice node.
  final List<String> pendingWrong;
}

class ChoiceResult {
  const ChoiceResult(this.state, this.choice);
  final StoryState state;
  final StoryChoice choice;
  bool get advanced => choice.next != null;
}

/// Pure interpreter for an [Episode] graph. The UI renders [StoryState];
/// persistence stores node, flags and history.
class StoryRunner {
  const StoryRunner(this.episode);
  final Episode episode;

  StoryNode node(String id) {
    final n = episode.nodes[id];
    if (n == null) throw StateError('episode ${episode.id} has no node $id');
    return n;
  }

  StoryState start() => StoryState(nodeId: _resolve(episode.start, const {}), flags: const {}, history: const []);

  bool isAtEnd(StoryState s) => node(s.nodeId) is EndNode;

  /// Moves past a narration or line node.
  StoryState advance(StoryState s) {
    final next = switch (node(s.nodeId)) {
      NarrationNode(:final next) => next,
      LineNode(:final next) => next,
      _ => throw StateError('node ${s.nodeId} cannot be advanced without a choice'),
    };
    return StoryState(
      nodeId: _resolve(next, s.flags),
      flags: s.flags,
      history: [...s.history, StoryStep(s.nodeId)],
    );
  }

  /// Applies a choice. Wrong choices without a target keep the learner at
  /// the same node so they can try again after reading the explanation.
  ChoiceResult choose(StoryState s, String choiceId) {
    final n = node(s.nodeId);
    if (n is! ChoiceNode) throw StateError('node ${s.nodeId} is not a choice');
    final choice = n.choices.firstWhere(
      (c) => c.id == choiceId,
      orElse: () => throw ArgumentError('unknown choice $choiceId at ${s.nodeId}'),
    );
    if (choice.next == null) {
      return ChoiceResult(
        StoryState(
          nodeId: s.nodeId,
          flags: s.flags,
          history: s.history,
          pendingWrong: {...s.pendingWrong, choice.id}.toList(),
        ),
        choice,
      );
    }
    final flags = {...s.flags, ...choice.setFlags};
    return ChoiceResult(
      StoryState(
        nodeId: _resolve(choice.next!, flags),
        flags: flags,
        history: [...s.history, StoryStep(s.nodeId, choiceId: choice.id, wrongChoiceIds: s.pendingWrong)],
      ),
      choice,
    );
  }

  /// Follows branch nodes until a visible node is reached.
  String _resolve(String id, Set<String> flags) {
    var current = id;
    for (var guard = 0; guard < 64; guard++) {
      final n = node(current);
      if (n is! BranchNode) return current;
      current = n.cases.firstWhere((c) => flags.contains(c.flag), orElse: () => BranchCase(flag: '', next: n.otherwise)).next;
    }
    throw StateError('branch loop in ${episode.id} at $id');
  }

  /// Number of choices answered right on the first attempt.
  ({int firstTry, int total}) choiceAccuracy(List<StoryStep> history) {
    var first = 0;
    var total = 0;
    for (final h in history) {
      if (h.choiceId == null) continue;
      total++;
      final n = node(h.nodeId) as ChoiceNode;
      final c = n.choices.firstWhere((c) => c.id == h.choiceId);
      if (h.wrongChoiceIds.isEmpty && c.verdict != ChoiceVerdict.wrong) first++;
    }
    return (firstTry: first, total: total);
  }
}
