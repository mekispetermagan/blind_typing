import 'exercise.dart';

enum MenuCommand {
  resume,
  restart,
  menu,
  nextExercise,
  nextLesson;

  bool get isProgression => this == nextExercise || this == nextLesson;
}

class ActivityReference {
  ActivityReference({required this.type, required this.content}) {
    if (!RegExp(r'^data/[a-zA-Z0-9_/]+\.json$').hasMatch(content)) {
      throw FormatException('Invalid content asset: $content');
    }
  }
  final ActivityType type;
  final String content;
}

class MenuNode {
  MenuNode({
    required this.id,
    required this.title,
    List<MenuNode> children = const [],
    this.activity,
    this.command,
  }) : children = List.unmodifiable(children) {
    final alternatives =
        (children.isNotEmpty ? 1 : 0) +
        (activity != null ? 1 : 0) +
        (command != null ? 1 : 0);
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(id) ||
        title.trim().isEmpty ||
        alternatives != 1) {
      throw FormatException('Invalid menu entry: $id');
    }
  }

  factory MenuNode.fromJson(Map<String, dynamic> json) {
    final reference = json['activity'] as Map<String, dynamic>?;
    return MenuNode(
      id: json['id'] as String,
      title: json['title'] as String,
      children: (json['children'] as List? ?? [])
          .map((child) => MenuNode.fromJson(child as Map<String, dynamic>))
          .toList(),
      activity: reference == null
          ? null
          : ActivityReference(
              type: ActivityType.values.byName(reference['type'] as String),
              content: reference['content'] as String,
            ),
      command: json['command'] == null
          ? null
          : MenuCommand.values.byName(json['command'] as String),
    );
  }

  final String id;
  final String title;
  final List<MenuNode> children;
  final ActivityReference? activity;
  final MenuCommand? command;
  String get audioAsset => 'assets/audio/menu_$id.wav';
  Iterable<MenuNode> get descendants sync* {
    yield this;
    for (final child in children) {
      yield* child.descendants;
    }
  }
}

class MenuCatalog {
  MenuCatalog({
    required this.root,
    required this.pause,
    required this.complete,
    List<List<String>> progression = const [],
  }) : progression = List.unmodifiable(
         progression.map((lesson) => List<String>.unmodifiable(lesson)),
       ) {
    final nodes = allNodes.toList();
    final activities = root.descendants
        .where((node) => node.activity != null)
        .map((node) => node.id)
        .toSet();
    final ordered = progression.expand((lesson) => lesson).toList();
    if (progression.any((lesson) => lesson.isEmpty) ||
        ordered.toSet().length != ordered.length ||
        ordered.any((id) => !activities.contains(id)) ||
        nodes.map((node) => node.id).toSet().length != nodes.length ||
        [root, pause, complete].any((node) => node.children.isEmpty) ||
        root.descendants.any((node) => node.command != null) ||
        pause.children.any((node) => node.command?.isProgression ?? true) ||
        complete.children.any(
          (node) => node.command == null || node.command == MenuCommand.resume,
        ) ||
        !complete.children.any(
          (node) => node.command?.isProgression == false,
        )) {
      throw const FormatException('Invalid menu catalog');
    }
  }

  factory MenuCatalog.fromJson(Map<String, dynamic> json) => MenuCatalog(
    root: MenuNode.fromJson(json['root'] as Map<String, dynamic>),
    pause: MenuNode.fromJson(json['pause'] as Map<String, dynamic>),
    complete: MenuNode.fromJson(json['complete'] as Map<String, dynamic>),
    progression: (json['progression'] as List? ?? [])
        .map((lesson) => (lesson as List).cast<String>())
        .toList(),
  );
  final List<List<String>> progression;
  final MenuNode root;
  final MenuNode pause;
  final MenuNode complete;
  ({String id, MenuCommand command})? nextActivity(String id) {
    for (var lesson = 0; lesson < progression.length; lesson++) {
      final index = progression[lesson].indexOf(id);
      if (index < 0) continue;
      if (index + 1 < progression[lesson].length) {
        return (
          id: progression[lesson][index + 1],
          command: MenuCommand.nextExercise,
        );
      }
      if (lesson + 1 < progression.length) {
        return (
          id: progression[lesson + 1].first,
          command: MenuCommand.nextLesson,
        );
      }
      return null;
    }
    return null;
  }

  List<int>? routeTo(String id) {
    List<int>? visit(MenuNode node, List<int> route) {
      if (node.id == id && node.activity != null) return route;
      for (var i = 0; i < node.children.length; i++) {
        final found = visit(node.children[i], [...route, i]);
        if (found != null) return found;
      }
      return null;
    }

    return visit(root, []);
  }

  Iterable<MenuNode> get allNodes =>
      [root, pause, complete].expand((node) => node.descendants);
}
