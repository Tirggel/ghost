// ignore_for_file: avoid_print
import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:ghost/engine/agent/skills.dart';
import 'package:archive/archive.dart';

void main() {
  late Directory tempDir;
  late SkillManager skillManager;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ghost_skill_zip_test_');
    skillManager = SkillManager(stateDir: tempDir.path);
    await skillManager.initialize();
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('SkillManager ZIP Installation', () {
    test('Fails to show skill when ZIP has a root folder (Current Bug)', () async {
      print('Starting ZIP installation test...');
      final encoder = ZipEncoder();
      final archive = Archive();

      // Create a ZIP with a root folder
      print('Creating mock ZIP with root folder...');
      const skillMd = '---\nname: Test Skill\nslug: test-skill\n---\n# Test Skill';
      archive.addFile(ArchiveFile('some-root-folder/SKILL.md', skillMd.length, skillMd.codeUnits));
      archive.addFile(ArchiveFile('some-root-folder/main.py', 0, <int>[]));

      final zipBytes = encoder.encode(archive);
      
      // Install the skill
      print('Installing skill...');
      final installedSkill = await skillManager.installSkill(zipBytes);
      print('Installed skill slug: ${installedSkill.slug}');
      
      // Check the list of skills
      print('Loading skills...');
      final skills = await skillManager.loadSkills();
      print('Found ${skills.length} skills');
      final found = skills.any((s) => s.slug == installedSkill.slug);
      
      // Now, this is EXPECTED TO PASS because of the fix
      expect(found, isTrue, reason: 'The fix should allow skills in a root folder to be found by loadSkills');
      
      // Verify the directory structure (why it now works)
      final skillPath = p.join(skillManager.skillsDir, installedSkill.slug);
      final expectedMd = File(p.join(skillPath, 'SKILL.md'));
      
      expect(expectedMd.existsSync(), isTrue);
    });
  });
}
