import 'package:flutter/material.dart';

import 'package:antenna_aligner/models/access_point.dart';

class APListWidget extends StatelessWidget {
  const APListWidget({
    super.key,
    required this.accessPoints,
    required this.onDelete,
    required this.onSelect,
    this.selectedId,
  });

  final List<AccessPoint> accessPoints;
  final void Function(int id) onDelete;
  final void Function(AccessPoint ap) onSelect;
  final int? selectedId;

  @override
  Widget build(BuildContext context) {
    if (accessPoints.isEmpty) {
      return const Center(
        child: Text('No access points configured yet.'),
      );
    }
    return ListView.builder(
      itemCount: accessPoints.length,
      itemBuilder: (context, index) {
        final item = accessPoints[index];
        final isSelected = item.id == selectedId;
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
          child: ListTile(
            leading: Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? Theme.of(context).primaryColor : null,
            ),
            title: Text(item.name),
            subtitle: Text('Lat ${item.latitude}, Lon ${item.longitude}'),
            onTap: () => onSelect(item),
            trailing: IconButton(
              icon: const Icon(Icons.delete),
              onPressed: item.id == null ? null : () => onDelete(item.id!),
            ),
          ),
        );
      },
    );
  }
}
