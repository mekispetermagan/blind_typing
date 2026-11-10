import 'exercise.dart';

enum MenuCommand { resume, restart, menu }

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
  }) {
    final nodes = allNodes.toList();
    if (nodes.map((node) => node.id).toSet().length != nodes.length ||
        [root, pause, complete].any((node) => node.children.isEmpty) ||
        root.descendants.any((node) => node.command != null) ||
        pause.children.any((node) => node.command == null) ||
        complete.children.any(
          (node) => node.command == null || node.command == MenuCommand.resume,
        )) {
      throw const FormatException('Invalid menu catalog');
    }
  }

  factory MenuCatalog.fromJson(Map<String, dynamic> json) => MenuCatalog(
    root: MenuNode.fromJson(json['root'] as Map<String, dynamic>),
    pause: MenuNode.fromJson(json['pause'] as Map<String, dynamic>),
    complete: MenuNode.fromJson(json['complete'] as Map<String, dynamic>),
  );
  final MenuNode root;
  final MenuNode pause;
  final MenuNode complete;
  Iterable<MenuNode> get allNodes =>
      [root, pause, complete].expand((node) => node.descendants);
}
