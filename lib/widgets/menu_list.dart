import 'package:flutter/material.dart';

import '../models/menu.dart';

/// Owns only scrolling; selection and activation remain application callbacks.
class MenuList extends StatefulWidget {
  const MenuList({
    required this.items,
    required this.selectedIndex,
    required this.onActivate,
    super.key,
  });
  final List<MenuNode> items;
  final int selectedIndex;
  final ValueChanged<int> onActivate;
  @override
  State<MenuList> createState() => _MenuListState();
}

class _MenuListState extends State<MenuList> {
  final _scroll = ScrollController();
  @override
  void didUpdateWidget(MenuList oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final start = widget.selectedIndex * 72.0;
      final end = start + 72;
      final position = _scroll.position;
      final target = start < position.pixels
          ? start
          : end > position.pixels + position.viewportDimension
          ? end - position.viewportDimension
          : position.pixels;
      _scroll.jumpTo(target.clamp(0.0, position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
    controller: _scroll,
    itemExtent: 72,
    itemCount: widget.items.length,
    itemBuilder: (context, index) => ExcludeFocus(
      child: ListTile(
        key: ValueKey(widget.items[index].id),
        selected: index == widget.selectedIndex,
        selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
        title: Text(
          widget.items[index].title,
          style: const TextStyle(fontSize: 24),
        ),
        trailing: Icon(
          widget.items[index].children.isEmpty
              ? Icons.play_arrow
              : Icons.chevron_right,
        ),
        onTap: () => widget.onActivate(index),
      ),
    ),
  );
}
