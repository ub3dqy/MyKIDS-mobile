import 'package:flutter/foundation.dart';

@immutable
class PlayItem {
  final String id, name, description;
  final int artwork, tasks;
  final bool wearable, familyReward;
  const PlayItem(
    this.id,
    this.name,
    this.description,
    this.artwork, {
    this.tasks = 0,
    this.wearable = false,
    this.familyReward = false,
  });
}

const playItems = <PlayItem>[
  PlayItem(
    'badge',
    'Звезда героя',
    'Первый предмет твоей коллекции',
    2,
    wearable: true,
  ),
  PlayItem(
    'headphones',
    'Яркие наушники',
    'Для новых открытий',
    0,
    tasks: 2,
    wearable: true,
  ),
  PlayItem(
    'cape',
    'Плащ героя',
    'Приключения начинаются!',
    1,
    tasks: 3,
    wearable: true,
  ),
  PlayItem('plant', 'Зелёный друг', 'Уют начинается с малого', 6),
  PlayItem('chair', 'Уютное кресло', 'Место для отдыха', 4, tasks: 1),
  PlayItem('desk', 'Стол открытий', 'Для книг и новых идей', 3, tasks: 2),
  PlayItem('lamp', 'Звёздный свет', 'Немного волшебства вечером', 5, tasks: 3),
  PlayItem('beanbag', 'Мягкий пуф', 'Устройся поудобнее', 8, tasks: 4),
  PlayItem(
    'trophy',
    'Наша общая победа',
    'За завершённую семейную миссию',
    7,
    familyReward: true,
  ),
];

PlayItem playItem(String id) => playItems.firstWhere((item) => item.id == id);

@immutable
class PlayMember {
  final String id, name, role;
  const PlayMember(this.id, this.name, this.role);
}

@immutable
class PlayTask {
  final String id, title, note, status;
  final String reviewNote, submissionNote;
  final int reward;
  const PlayTask(
    this.id,
    this.title,
    this.note,
    this.status,
    this.reward, {
    this.reviewNote = '',
    this.submissionNote = '',
  });
  bool get completed => status == 'completed';
  bool get waiting => status == 'submitted';
  bool get canSubmit => status == 'assigned' || status == 'returned';
}

@immutable
class MissionStep {
  final String id, owner, title;
  final String? taskId;
  const MissionStep(this.id, this.owner, this.title, {this.taskId});
  Map<String, dynamic> toJson() => {
    'id': id,
    'owner': owner,
    'title': title,
    'task_id': taskId,
  };
  static MissionStep fromJson(Map<String, dynamic> value) => MissionStep(
    value['id'] as String,
    value['owner'] as String,
    value['title'] as String,
    taskId: value['task_id'] as String?,
  );
}

@immutable
class FamilyMission {
  final String id, title, description, reward;
  final List<MissionStep> steps;
  const FamilyMission(
    this.id,
    this.title,
    this.description,
    this.reward,
    this.steps,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'reward': reward,
    'steps': steps.map((s) => s.toJson()).toList(),
  };
  static FamilyMission fromJson(Map<String, dynamic> value) => FamilyMission(
    value['id'] as String,
    value['title'] as String,
    value['description'] as String,
    value['reward'] as String,
    (value['steps'] as List)
        .map((s) => MissionStep.fromJson(Map<String, dynamic>.from(s as Map)))
        .toList(),
  );
}

class PlayState {
  String hero = 'auto', name = 'Искра';
  Set<String> worn = {'badge'};
  List<String?> room = ['plant', null, null];
  List<String> adventureTaskIds = [];
  Set<String> joined = {}, adultSteps = {}, claimedMissions = {};
  Set<String> confirmedTasks = {}, earned = {'badge', 'plant'};
  List<Map<String, String>> praise = [];
  bool adventureClaimed = false;
  Map<String, bool> enabled = {'hero': true, 'adventure': true, 'family': true};
  List<FamilyMission> missions = [];

  Map<String, dynamic> toJson() => {
    'schema': 1,
    'hero': hero,
    'name': name,
    'worn': worn.toList(),
    'room': room,
    'adventure_task_ids': adventureTaskIds,
    'joined': joined.toList(),
    'adult_steps': adultSteps.toList(),
    'claimed_missions': claimedMissions.toList(),
    'confirmed_tasks': confirmedTasks.toList(),
    'earned': earned.toList(),
    'praise': praise,
    'adventure_claimed': adventureClaimed,
    'enabled': enabled,
    'missions': missions.map((m) => m.toJson()).toList(),
  };

  static PlayState fromJson(Map<String, dynamic> value) {
    if (value['schema'] != 1) {
      throw const FormatException('Unsupported play state');
    }
    final result = PlayState();
    result.hero = value['hero'] as String;
    if (![
      'auto',
      'blocks',
      'squad',
      'comic',
      'workshop',
      'islands',
    ].contains(result.hero)) {
      throw const FormatException('Unknown hero');
    }
    result.name = value['name'] as String;
    if (result.name.trim().isEmpty ||
        result.name.length > 256 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(result.name)) {
      throw const FormatException('Invalid hero name');
    }
    result.worn = (value['worn'] as List).cast<String>().toSet();
    if (result.worn.any(
      (id) => !playItems.any((i) => i.id == id && i.wearable),
    )) {
      throw const FormatException('Unknown wearable');
    }
    result.room = (value['room'] as List).cast<String?>().toList();
    result.adventureTaskIds = (value['adventure_task_ids'] as List)
        .cast<String>();
    if (![0, 3].contains(result.adventureTaskIds.length) ||
        result.adventureTaskIds.toSet().length !=
            result.adventureTaskIds.length) {
      throw const FormatException('Invalid adventure');
    }
    if (result.room.length != 3 ||
        result.room.whereType<String>().toSet().length !=
            result.room.whereType<String>().length ||
        result.room.whereType<String>().any(
          (id) => !playItems.any((i) => i.id == id && !i.wearable),
        )) {
      throw const FormatException('Invalid room slots');
    }
    result.joined = (value['joined'] as List).cast<String>().toSet();
    result.adultSteps = (value['adult_steps'] as List).cast<String>().toSet();
    result.claimedMissions = (value['claimed_missions'] as List)
        .cast<String>()
        .toSet();
    result.confirmedTasks = (value['confirmed_tasks'] as List)
        .cast<String>()
        .toSet();
    result.earned = (value['earned'] as List).cast<String>().toSet();
    result.praise = (value['praise'] as List)
        .map((row) => Map<String, String>.from(row as Map))
        .toList();
    if (result.earned.any((id) => !playItems.any((i) => i.id == id)) ||
        result.confirmedTasks.length > 1000 ||
        result.praise.length > 40 ||
        result.praise.any(
          (p) =>
              p.length != 3 ||
              !p.containsKey('mission') ||
              (p['sender'] ?? '').isEmpty ||
              !praiseMessages.contains(p['text']),
        )) {
      throw const FormatException('Invalid achievements or praise');
    }
    result.adventureClaimed = value['adventure_claimed'] as bool;
    result.enabled = Map<String, bool>.from(value['enabled'] as Map);
    if (result.enabled.keys.toSet().difference({
          'hero',
          'adventure',
          'family',
        }).isNotEmpty ||
        result.enabled.length != 3) {
      throw const FormatException('Invalid play settings');
    }
    result.missions = (value['missions'] as List)
        .map((m) => FamilyMission.fromJson(Map<String, dynamic>.from(m as Map)))
        .toList();
    if (result.missions.length > 20 ||
        result.missions.map((m) => m.id).toSet().length !=
            result.missions.length) {
      throw const FormatException('Invalid missions');
    }
    for (final mission in result.missions) {
      if (mission.title.trim().isEmpty ||
          mission.title.length > 80 ||
          mission.description.length > 300 ||
          mission.reward.length > 100 ||
          mission.steps.length != 3 ||
          mission.steps.any((s) => s.owner.isEmpty || s.owner.length > 100) ||
          mission.steps.map((s) => s.owner).toSet().length != 3 ||
          mission.steps.map((s) => s.id).toSet().length != 3 ||
          mission.steps.any(
            (s) => s.title.trim().isEmpty || s.title.length > 100,
          )) {
        throw const FormatException('Invalid mission content');
      }
    }
    return result;
  }
}

/// The app and the approval entry render the same widgets through this contract.
/// A server-backed implementation can replace the synthetic review controller.
abstract class EngagementController extends ChangeNotifier {
  PlayState get state;
  List<PlayTask> get tasks;
  List<PlayMember> get members;
  String get currentMemberId;
  String get childId;
  Object get accessIdentity => (currentMemberId, childId, role);
  String memberName(String id) =>
      members.where((m) => m.id == id).firstOrNull?.name ?? 'Участник семьи';
  String memberRole(String id) =>
      members.where((m) => m.id == id).firstOrNull?.role ?? '';
  String get role;
  bool get busy;
  String? get storageError;
  int get completedCount => state.confirmedTasks.length;
  List<PlayTask> get adventureTasks => [
    for (final id in state.adventureTaskIds) ...tasks.where((t) => t.id == id),
  ];
  bool stepDone(MissionStep step) => step.taskId != null
      ? tasks.any((t) => t.id == step.taskId && t.completed)
      : state.adultSteps.contains(step.id);
  bool missionDone(FamilyMission m) => m.steps.every(stepDone);
  int get completedMissions => state.missions.where(missionDone).length;
  bool unlocked(PlayItem item) => state.earned.contains(item.id);
  String unlockText(PlayItem item) => item.familyReward
      ? 'Завершите семейную миссию'
      : 'Подтверждённых дел: $completedCount из ${item.tasks}';
  Future<void> chooseHero(String id);
  Future<void> renameHero(String value);
  Future<void> wear(String id);
  Future<void> place(String? id, int slot);
  Future<void> submit(String taskId, String note);
  Future<void> review(String taskId, {required bool approve, String note = ''});
  Future<void> join(String missionId);
  Future<void> markOwnStep(String missionId, String stepId);
  Future<void> claimAdventure();
  Future<void> chooseAdventureTasks(List<String> ids);
  Future<void> claimMission(String missionId);
  Future<void> setEnabled(String feature, bool value);
  Future<void> sendPraise(String missionId, String text);
  Future<void> createMission({
    required String title,
    required String description,
    required String reward,
    required String childStep,
    required String parentStep,
    required String helperId,
    required String helperStep,
  });
}

const praiseMessages = [
  'Горжусь тобой!',
  'Отличная команда!',
  'Спасибо за помощь!',
  'Спасибо!',
];
