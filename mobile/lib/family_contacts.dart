import 'repository.dart';

List<Map<String, dynamic>> familyContacts(FamilyRepository repository) {
  final contacts = repository
      .rows('members')
      .where(
        (member) => member['active'] == 1 && member['id'] != repository.userId,
      )
      .toList();
  const order = {'child': 0, 'parent': 1, 'relative': 2};
  contacts.sort((a, b) {
    final roleOrder = (order[a['role']] ?? 3).compareTo(order[b['role']] ?? 3);
    if (roleOrder != 0) return roleOrder;
    final nameOrder = (a['name'] as String).toLowerCase().compareTo(
      (b['name'] as String).toLowerCase(),
    );
    return nameOrder != 0
        ? nameOrder
        : (a['id'] as String).compareTo(b['id'] as String);
  });
  return contacts;
}

Map<String, dynamic>? contactRoom(
  FamilyRepository repository,
  String contactId,
) => repository
    .rows('rooms')
    .where(
      (room) =>
          room['kind'] == 'private' &&
          (room['contact'] as Map?)?['id'] == contactId,
    )
    .firstOrNull;

String conversationName(Map<String, dynamic> room) =>
    (room['contact'] as Map?)?['name'] as String? ?? room['title'] as String;

Set<String> reservedCallParticipants(Map<String, dynamic>? call) => {
  for (final member in (call?['participants'] as List? ?? []))
    if (['joined', 'invited', 'revoking'].contains((member as Map)['status']))
      member['user_id'] as String,
};
