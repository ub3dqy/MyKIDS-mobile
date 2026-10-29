import 'repository.dart';

/// QR carries only the existing one-time token and its intended family role.
class Invitation {
  static const roles = ['child', 'parent', 'relative'];
  final String role, token;

  Invitation({required this.role, required this.token}) {
    if (!roles.contains(role) ||
        token.length != 43 ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token)) {
      throw ApiFailure(400, 'Приглашение недействительно. Создайте новое');
    }
  }

  String get qrData => Uri(
    scheme: 'mykids',
    host: 'invite',
    queryParameters: {'version': '1', 'role': role, 'token': token},
  ).toString();

  static Invitation parse(String data, {required String expectedRole}) {
    if (data.length > 512 || !roles.contains(expectedRole)) {
      throw ApiFailure(400, 'Это не QR-код приглашения MyKIDS');
    }
    final uri = Uri.tryParse(data);
    if (uri == null ||
        uri.scheme != 'mykids' ||
        uri.host != 'invite' ||
        uri.path.isNotEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasFragment) {
      throw ApiFailure(400, 'Это не QR-код приглашения MyKIDS');
    }
    final values = uri.queryParametersAll;
    if (values.length != 3 ||
        ![
          'version',
          'role',
          'token',
        ].every((key) => values[key]?.length == 1) ||
        values['version']?.single != '1') {
      throw ApiFailure(400, 'Это не QR-код приглашения MyKIDS');
    }
    final invitation = Invitation(
      role: values['role']!.single,
      token: values['token']!.single,
    );
    if (invitation.role != expectedRole) {
      final roleName = const {
        'child': 'ребёнка',
        'parent': 'родителей',
        'relative': 'бабушек и дедушек',
      }[invitation.role];
      throw ApiFailure(400, 'Это приглашение для $roleName. Выберите эту роль');
    }
    return invitation;
  }
}
