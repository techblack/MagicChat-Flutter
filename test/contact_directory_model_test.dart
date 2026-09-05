import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/contacts/contact_directory_model.dart';

void main() {
  test('联系人按英文和中文拼音首字母分组', () {
    final sections = buildContactSections(const [
      Contact(id: 'z', name: '张三'),
      Contact(id: 'a', name: 'Alice'),
      Contact(id: 'l', name: '李四'),
      Contact(id: 'number', name: '9号成员'),
      Contact(id: 'app', name: '应用', type: 'app'),
    ]);

    expect(sections.map((section) => section.label), ['A', 'L', 'Z', '#']);
    expect(
        sections.expand((section) => section.contacts).map((item) => item.id),
        ['a', 'l', 'z', 'number']);
    expect(contactIndexLabel('Émile'), 'E');
  });

  test('通讯录分类按当前用户、加入状态和公开状态筛选', () {
    const contacts = [
      Contact(id: 'mine', name: '我的应用', type: 'app', creatorUserId: 'USER-ME'),
      Contact(
          id: 'other', name: '其他应用', type: 'app', creatorUserId: 'other-user'),
      Contact(id: 'joined', name: '已加入', type: 'group', joined: true),
      Contact(id: 'public', name: '公开群', type: 'group', visibility: 'public'),
    ];

    expect(
        contactsForCategory(
                ContactDirectoryCategory.myApps, contacts, 'user-me')
            .map((item) => item.id),
        ['mine']);
    expect(
        contactsForCategory(
                ContactDirectoryCategory.allApps, contacts, 'user-me')
            .map((item) => item.id),
        ['other', 'mine']);
    expect(
        contactsForCategory(
                ContactDirectoryCategory.joinedGroups, contacts, 'user-me')
            .map((item) => item.id),
        ['joined']);
    expect(
        contactsForCategory(
                ContactDirectoryCategory.publicGroups, contacts, 'user-me')
            .map((item) => item.id),
        ['public']);
  });
}
