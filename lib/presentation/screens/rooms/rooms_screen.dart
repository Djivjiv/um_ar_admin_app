import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/no_rooms_buildings.dart';
import '../../../core/utils/ui_helpers.dart';
import '../../../data/repositories/building_repository.dart';
import '../../../data/repositories/room_repository.dart';
import '../../../domain/models/building_model.dart';
import '../../../domain/models/room_model.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/data_table_card.dart';
import '../../widgets/slide_panel.dart';
import 'room_form.dart';

class RoomsScreen extends StatefulWidget {
  final int? initialBuildingId;

  const RoomsScreen({super.key, this.initialBuildingId});

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  final _roomRepo = RoomRepository();
  final _buildingRepo = BuildingRepository();

  List<BuildingModel> _buildings = [];
  List<RoomModel> _rooms = [];
  bool _loading = true;
  Object? _error;
  int? _filterBuildingId;

  @override
  void initState() {
    super.initState();
    _filterBuildingId = widget.initialBuildingId;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final buildings = await _buildingRepo.getAll();
      final rooms = _filterBuildingId != null
          ? await _roomRepo.getByBuilding(_filterBuildingId!)
          : await _roomRepo.getAll();
      setState(() {
        _buildings = buildings;
        _rooms = rooms;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// Buildings that can actually contain rooms (excludes [noRoomsBuildings]).
  List<BuildingModel> get _roomableBuildings =>
      _buildings.where((b) => buildingHasRooms(b.name)).toList();

  String _buildingName(int? id) {
    if (id == null) return '—';
    final match = _buildings.where((b) => b.id == id);
    return match.isEmpty ? '#$id' : match.first.name;
  }

  int _floorRank(String? floor) =>
      int.tryParse((floor ?? '').trim()) ?? 1000000;

  /// Sorted by building name, then floor number, then room name.
  List<RoomModel> get _sortedRooms {
    final list = List<RoomModel>.from(_rooms);
    list.sort((a, b) {
      final byBuilding = _buildingName(a.buildingId)
          .toLowerCase()
          .compareTo(_buildingName(b.buildingId).toLowerCase());
      if (byBuilding != 0) return byBuilding;
      final byFloor = _floorRank(a.floor).compareTo(_floorRank(b.floor));
      if (byFloor != 0) return byFloor;
      final byFloorText =
          (a.floor ?? '').toLowerCase().compareTo((b.floor ?? '').toLowerCase());
      if (byFloorText != 0) return byFloorText;
      return a.roomname.toLowerCase().compareTo(b.roomname.toLowerCase());
    });
    return list;
  }

  Future<void> _openForm([RoomModel? room]) async {
    final result = await SlidePanel.show<bool>(
      context,
      title: room == null ? 'Add Room' : 'Edit Room',
      subtitle: room?.roomname,
      body: RoomForm(
        // The form's building selector keeps every building so editing a room
        // already attached to one never breaks; only the screen's *filter*
        // dropdown hides the no-rooms buildings.
        room: room,
        buildings: _buildings,
        defaultBuildingId: _filterBuildingId,
      ),
    );
    if (result == true) _load();
  }

  Future<void> _delete(RoomModel r) async {
    final ok = await ConfirmDialog.show(context, itemName: r.roomname);
    if (!ok) return;
    try {
      await _roomRepo.delete(r.id!);
      if (mounted) context.showSuccess('Room deleted');
      _load();
    } catch (e) {
      if (mounted) context.showError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rooms = _sortedRooms;
    final roomable = _roomableBuildings;
    final filterValue =
        roomable.any((b) => b.id == _filterBuildingId) ? _filterBuildingId : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<int?>(
                initialValue: filterValue,
                decoration: const InputDecoration(
                    isDense: true, labelText: 'Filter by building'),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('All buildings')),
                  for (final b in roomable)
                    DropdownMenuItem(value: b.id, child: Text(b.name)),
                ],
                onChanged: (v) {
                  setState(() => _filterBuildingId = v);
                  _load();
                },
              ),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _buildings.isEmpty ? null : () => _openForm(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Room'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error.toString()),
                      const SizedBox(height: 8),
                      ElevatedButton(
                          onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : DataTableCard(
                  title: '${rooms.length} Rooms',
                  isLoading: _loading,
                  columns: const [
                    DataColumn2(label: Text('Name'), size: ColumnSize.L),
                    DataColumn2(label: Text('Building'), size: ColumnSize.L),
                    DataColumn2(label: Text('Floor'), size: ColumnSize.S),
                    DataColumn2(label: Text('Type'), size: ColumnSize.M),
                    DataColumn2(label: Text('Services'), size: ColumnSize.M),
                    DataColumn2(label: Text('Actions'), size: ColumnSize.M),
                  ],
                  rows: [
                    for (final r in rooms)
                      DataRow2(
                        cells: [
                          DataCell(Text(r.roomname)),
                          DataCell(Text(_buildingName(r.buildingId))),
                          DataCell(Text(r.floor ?? '—')),
                          DataCell(Text(r.type ?? '—')),
                          DataCell(Text('${r.services.length}')),
                          DataCell(Row(
                            children: [
                              IconButton(
                                tooltip: 'Edit',
                                icon: const Icon(Icons.edit, size: 18),
                                onPressed: () => _openForm(r),
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(Icons.delete_outline,
                                    size: 18, color: AppColors.errorRed),
                                onPressed: () => _delete(r),
                              ),
                            ],
                          )),
                        ],
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
