// ignore_for_file: avoid_print
import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:ghost/engine/agent/skills.dart';
import 'package:logging/logging.dart';

void main() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });

  late Directory tempDir;
  late SkillManager skillManager;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ghost_skill_init_test_');
    skillManager = SkillManager(stateDir: tempDir.path);
    await skillManager.initialize();
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('SkillManager Initialization', () {
    test('Detects and initializes Python venv', () async {
      const skillSlug = 'test-python-skill';
      final skillPath = p.join(skillManager.skillsDir, skillSlug);
      await Directory(p.join(skillPath, 'scripts')).create(recursive: true);
      
      // Create requirements.txt
      await File(p.join(skillPath, 'scripts', 'requirements.txt')).writeAsString('requests');
      
      // We'll mock the _initializeRuntimes call or just run it as-is
      // Note: This actually runs real pip/python if they are in the path!
      // In a real CI we might mock Process.run, but here we want to see it work.
      
      await skillManager.installSkillFromPath(skillPath); // Assuming we add this or similar
      
      // For now, let's just call the private method if we can (using reflection or just making it public for test)
      // Since we can't easily call private methods from outside, we'll verify the logic 
      // by seeing if loadSkills returns the correct hasnPython flag.
      
      // Mock SKILL.md for loadSkills
      await File(p.join(skillPath, 'SKILL.md')).writeAsString('---\nname: Test\n---');
      
      final skills = await skillManager.loadSkills();
      final testSkill = skills.firstWhere((s) => s.slug == skillSlug);
      
      expect(testSkill.hasPython, isTrue);
      expect(testSkill.hasNode, isFalse);
    });

    test('Detects Node.js package.json', () async {
      const skillSlug = 'test-node-skill';
      final skillPath = p.join(skillManager.skillsDir, skillSlug);
      await Directory(skillPath).create(recursive: true);
      
      await File(p.join(skillPath, 'package.json')).writeAsString('{"name": "test"}');
      await File(p.join(skillPath, 'SKILL.md')).writeAsString('---\nname: Test Node\n---');
      
      final skills = await skillManager.loadSkills();
      final testSkill = skills.firstWhere((s) => s.slug == skillSlug);
      
      expect(testSkill.hasPython, isFalse);
      expect(testSkill.hasNode, isTrue);
    });

    test('Imports skill from external directory', () async {
      final externalPath = p.join(tempDir.path, 'external-skill');
      await Directory(externalPath).create();
      await File(p.join(externalPath, 'SKILL.md')).writeAsString('---\nslug: external-slug\nname: External\n---');
      await File(p.join(externalPath, 'requirements.txt')).writeAsString('requests');

      final skill = await skillManager.installSkillFromDirectory(externalPath);
      
      expect(skill.slug, equals('external-slug'));
      expect(await Directory(p.join(skillManager.skillsDir, 'external-slug')).exists(), isTrue);
      expect(skill.hasPython, isTrue);
      
      // Verify venv was created (or at least attempted)
      expect(await Directory(p.join(skillManager.skillsDir, 'external-slug', '.venv')).exists(), isTrue);
    });
  });
}

// Extension to help testing private methods if needed, or just use public API
extension SkillManagerTest on SkillManager {
  Future<void> installSkillFromPath(String path) async {
    // This is a helper for the test to trigger the initialization
    final slug = p.basename(path);
    await initializeRuntimes(slug, path);
  }
}
