/// Buildings that have no indoor rooms to manage. They are hidden from the
/// rooms building filter and their cards do not show a "View Rooms" button.
const List<String> noRoomsBuildings = [
  'Warehouse',
  'Study Hub',
  'Sports Complex',
  'Security Safety Office',
  'ROTC Field',
  'Motor Pool',
  'Matina Gate',
  'Maa Gate',
  'Food Courts',
  'Food Court 1',
  'Food Court 2',
  'UMPX Canteen',
  'FEA Covered Court',
  'Ecumenical Chapel',
  'Cagliari Hall',
  'Alumni Office',
];

/// Returns true when [name] is a building that has manageable rooms.
bool buildingHasRooms(String? name) {
  if (name == null) return false;
  final normalized = name.trim().toLowerCase();
  return !noRoomsBuildings.any((b) => b.toLowerCase() == normalized);
}
