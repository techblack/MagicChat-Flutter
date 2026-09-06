import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:magicchat_client/domain/models.dart';
import 'package:magicchat_client/features/projects/document_export.dart';

void main() {
  test('导出文件名清理平台非法字符并按文档类型选择扩展名', () {
    const markdown = ProjectDocument(
        id: 'doc-1',
        projectId: 'project-1',
        title: '计划: 九月/发布',
        documentType: 'markdown');
    const rich = ProjectDocument(
        id: 'doc-2',
        projectId: 'project-1',
        title: '设计稿',
        documentType: 'document');

    expect(documentExportFileName(markdown), '计划_ 九月_发布.md');
    expect(documentExportFileName(rich), '设计稿.txt');
  });

  test('导出正文保留标题并使用 UTF-8 字节', () {
    const title = '发布计划';
    const body = '第一项\n第二项';
    expect(documentExportText(title: title, body: body), '# 发布计划\n\n第一项\n第二项');
    expect(utf8.decode(documentExportBytes(title: title, body: body)),
        '# 发布计划\n\n第一项\n第二项');
  });
}
