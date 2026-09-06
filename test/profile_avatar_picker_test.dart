import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:magicchat_client/data/repository.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/settings/profile_avatar_picker_dialog.dart';
import 'package:magicchat_client/features/settings/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('小屏可浏览 64 个系统头像，取消不保存并可确认选择', (tester) async {
    final repository = _ProfileRepository();
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SettingsPage(repository: repository, serverUrl: null),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('profile-avatar-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('系统头像'));
    await tester.pumpAndSettle();
    final grid = tester.widget<GridView>(
        find.byKey(const ValueKey('profile-builtin-avatar-grid')));
    expect(
        grid.childrenDelegate.estimatedChildCount, profileBuiltinAvatarCount);
    await tester.tap(find.byKey(const ValueKey('profile-builtin-avatar-03')));
    await tester.pump();
    expect(
        find.descendant(
          of: find.byKey(const ValueKey('profile-builtin-avatar-03')),
          matching: find.byIcon(Icons.check_circle),
        ),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('profile-builtin-avatar-04')));
    await tester.tap(find.byKey(const ValueKey('profile-avatar-close')));
    await tester.pumpAndSettle();
    expect(repository.updatedAvatars, isEmpty);

    await tester.tap(find.byKey(const ValueKey('profile-avatar-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('系统头像'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile-builtin-avatar-04')));
    await tester.pump();
    final save = find.byKey(const ValueKey('profile-builtin-avatar-save'));
    expect(save.hitTestable(), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(repository.updatedAvatars, [profileBuiltinAvatarPath(4)]);
    expect(find.byType(ProfileAvatarPickerDialog), findsNothing);
  });

  testWidgets('系统头像保存失败保留选中态并可原位重试', (tester) async {
    final repository = _ProfileRepository(failFirstBuiltinSave: true);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SettingsPage(repository: repository, serverUrl: null),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('profile-avatar-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('系统头像'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile-builtin-avatar-04')));
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('profile-builtin-avatar-save')))
            .onPressed,
        isNotNull);
    await tester.tap(find.byKey(const ValueKey('profile-builtin-avatar-save')));
    await tester.pumpAndSettle();

    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(find.byType(ProfileAvatarPickerDialog), findsOneWidget);
    expect(
        find.descendant(
          of: find.byKey(const ValueKey('profile-builtin-avatar-04')),
          matching: find.byIcon(Icons.check_circle),
        ),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('profile-builtin-avatar-save')));
    await tester.pumpAndSettle();
    expect(repository.updatedAvatars,
        [profileBuiltinAvatarPath(4), profileBuiltinAvatarPath(4)]);
    expect(find.byType(ProfileAvatarPickerDialog), findsNothing);
  });

  testWidgets('自定义头像可预览、缩放、拖动裁剪并保存 256 WebP', (tester) async {
    Uint8List? uploaded;
    var attempts = 0;
    final source = image.Image(width: 400, height: 200);
    final sourceBytes = Uint8List.fromList(image.encodePng(source));
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => showDialog<CurrentUser>(
                context: context,
                barrierDismissible: false,
                builder: (_) => ProfileAvatarPickerDialog(
                  repository: DemoRepository(),
                  selectedAvatar: 'https://assets.example/avatar.webp',
                  imagePicker: () async => ProfileAvatarImage(
                    name: 'avatar.png',
                    bytes: sourceBytes,
                  ),
                  onSaveBuiltin: (_) async => _user,
                  onSaveCustom: (bytes) async {
                    attempts++;
                    if (attempts == 1) throw StateError('offline');
                    uploaded = bytes;
                    return _user;
                  },
                ),
              ),
              child: const Text('打开头像选择'),
            ),
          ),
        );
      }),
    ));

    await tester.tap(find.text('打开头像选择'));
    await tester.pumpAndSettle();
    expect(find.text('自定义头像'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('profile-custom-avatar-pick')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-custom-avatar-crop')),
        findsOneWidget);

    await tester.drag(find.byKey(const ValueKey('profile-custom-avatar-zoom')),
        const Offset(80, 0));
    await tester.pump();
    await tester.drag(find.byKey(const ValueKey('profile-custom-avatar-crop')),
        const Offset(-30, 0));
    await tester.pump();
    final save = find.byKey(const ValueKey('profile-custom-avatar-save'));
    await tester.ensureVisible(save);
    expect(save.hitTestable(), findsOneWidget);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.textContaining('上传失败'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-custom-avatar-crop')),
        findsOneWidget);

    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    final decoded = image.decodeWebP(uploaded!);
    expect(decoded, isNotNull);
    expect(decoded!.width, 256);
    expect(decoded.height, 256);
    expect(uploaded!.length, lessThanOrEqualTo(1024 * 1024));
    expect(find.byType(ProfileAvatarPickerDialog), findsNothing);
  });
}

const _user = CurrentUser(
  id: 'user-1',
  name: '演示用户',
  email: 'demo@example.com',
  avatar: '/assets/avatars/builtin/03.webp',
);

class _ProfileRepository extends DemoRepository {
  _ProfileRepository({this.failFirstBuiltinSave = false});

  final bool failFirstBuiltinSave;
  final updatedAvatars = <String>[];
  CurrentUser user = const CurrentUser(
    id: 'user-1',
    name: '演示用户',
    email: 'demo@example.com',
  );

  @override
  Future<CurrentUser> currentUser() async => user;

  @override
  Future<CurrentUser> updateProfile({String? nickname, String? avatar}) async {
    if (avatar != null) updatedAvatars.add(avatar);
    if (failFirstBuiltinSave && updatedAvatars.length == 1) {
      throw StateError('offline');
    }
    user = CurrentUser(
      id: user.id,
      name: user.name,
      email: user.email,
      nickname: nickname ?? user.nickname,
      avatar: avatar ?? user.avatar,
      phone: user.phone,
    );
    return user;
  }
}
