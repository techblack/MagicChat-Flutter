# Flutter 重构迁移矩阵

Flutter 工程与现有客户端并行演进，页面层通过 `MagicChatRepository` 访问数据，确保桌面和移动端共享同一套交互与状态模型。

| 现有能力 | Flutter 入口 | 状态 |
| --- | --- | --- |
| 登录、Server 会话 | 启动登录页、`AuthService`、`SessionStore`、设置页 | 密码/邮箱验证码登录、Native HTTP/Bearer 与 Web HttpOnly Cookie、退出登录、服务器切换、实时连接清理、主题持久化已接入 |
| 账户资料 | 设置页 | `/api/client/me` 查询、昵称修改、头像选择及严格 256x256 WebP 裁剪上传已接入；`user.profile.updated` 会触发设置页刷新 |
| 多账户 | 设置页、`SessionStore` | 安全存储多个 Server 账户、切换和长按删除、需重新登录账户的密码认证 UI 已接入 |
| 本地存储 | 设置页、`StorageService` | 跨平台缓存占用统计、路径展示和清理已接入 |
| 私聊、群聊、应用会话 | 消息 → 会话 → 消息面板 | 私聊/群聊创建、应用会话打开、联系人打开会话、公开群组加入、成员多选/添加/移除、群头像/公告/名称/公开状态修改、会话移除/恢复、置顶/免打扰、会话关键词搜索与全部/未读/私聊/群聊/应用筛选、按置顶和最新序号稳定排序、话题创建、话题列表/详情/参与/关闭、来源消息上下文与话题回复预览、消息转发、消息面板和顶部历史分页已接入；归档话题的发送、回复、回应、选择和撤回入口已按原版门控；群成员角色权限门控、退出/解散已接入；普通用户设置管理员暂缺服务端 API；选择消息支持历史快照恢复、单/多选交互和实时回流，以及提及/选择提醒标记已接入。 |
| WebSocket 实时同步 | `MagicChatRealtime`、`RealtimeSession`、`RealtimeStore` | cursor/envelope、退避重连、dispose、消息归属与会话事件幂等投影、消息视图监听及会话列表实时刷新已接入；历史消息按当前用户 ID 正确标记归属 |
| 联系人、在线状态 | `features/contacts` | `/api/client/contacts` 目录模式与关键词查询、用户资料批量解析、完整邮箱/手机号/用户 ID 精确查找、好友申请发送/查看/接受/拒绝/取消、删除好友、在线状态展示、应用/公开群组加入及打开会话已接入；自有应用创建/编辑/启停/删除、头像、凭据与密钥重置已接入；`user.presence.updated` 实时投影已接入 |
| 聊天记录搜索 | AppBar 搜索 | `/api/client/search/messages` 已接入，支持跳转会话 |
| 会话管理 | 会话长按菜单 | 置顶、免打扰 API 与 UI 已接入；打开会话或停留在底部时按最新序号同步已读 |
| 版本检查 | 设置页、`UpdateService` | 移动端版本清单按 Android/iOS 平台选择、HTTPS 下载地址和非负整数 build 严格校验，发现新版本可打开下载地址；原生桌面自动更新仍由桌面端负责 |
| 推送授权与通知路由 | `PushService`、`PushTokenProvider`、设置页、`AppShell` | 私有 Server grant 注册/撤销、启动路由解析、通知总开关持久化、开启通知时系统权限请求、Android/iOS 本地通知通道及原生令牌桥接契约已接入；APNs/JPush 厂商 SDK 实现待补 |
| 二维码 | `QrScannerPage` | Android/iOS/macOS/Web 相机扫码、HTTP(S) 链接打开、文本结果展示及桌面粘贴兜底已接入 |
| 项目、任务视图 | `features/projects` | 个人/团队项目摘要、项目创建/编辑/删除、项目关键词过滤与游标分页、任务连续分页加载及关键词/状态/优先级筛选、列表/看板/月历/甘特、任务创建、编辑（描述/项目成员负责人/状态/优先级/日期/标签/一次性与周期提醒）、状态更新、删除、任务详情、完整活动流与 Markdown 评论、成员列表、群组授权管理已接入；目标仍与原版一致为待完善占位 |
| 文档协作 | `features/projects`、`DocumentRealtime`、`DocumentCollaborationSession`、`RichDocumentView` | 文档目录树、富文本/Markdown 类型、创建/重命名/移动/删除、Markdown 编辑预览与格式工具栏（粗体/斜体/删除线、列表/任务、链接/图片、分割线/表格）、Hocuspocus v4 认证与 Yjs `Y.Text("markdown")` 状态同步、富文档 `Y.XmlFragment("body")` 正文状态同步、远端更新灌入编辑器、本地更新回传、Awareness 在线协作者计数及协作标题接口已接入；Flutter 支持富文档 XML block/列表/任务/表格/代码/引用/图片/marks 的只读渲染，新增富文档 block 格式工具栏，可直接追加段落/标题/列表/任务/引用/代码块；已有 block 仍保持只读，完整原位格式化工具栏仍待迁移 |
| 图片、文件、语音、选择、对象卡片、图表、回应、系统事件 | `_MessageBubble`、`VoiceMessagePlayer`、`flutter_markdown_plus`、文件选择器、`VoiceRecorder`、`_ChartPreview` | 文件选择与 multipart 发送、Markdown 渲染及链接、图片交互预览、附件打开、应用内语音播放/暂停/串音频/转录展开、录音时长上传、历史附件分页列表、麦克风录制发送、类型摘要、折线/柱状/饼图/雷达图专用预览、对象展开、图标、choice 选项响应、choice 状态/响应人数及实时快照恢复、reaction 胶囊及长按参与者列表与历史快照恢复、系统事件摘要和居中展示已接入；普通音频文件按文件类型发送；撤回消息在历史与实时路径统一显示占位并禁用消息操作；文本和附件回复引用、输入表情选择已接入 |
| 推送、系统通知、平台文件能力 | Flutter platform channels | 待按平台接入 |

## 迁移顺序

1. 先实现认证、HTTP 请求和 WebSocket 仓储，并复用服务端 `/api/client/` 协议。
2. 迁移消息分页、缓存、附件和消息类型渲染；以现有 mobile/desktop 测试作为行为基线。
3. 迁移通讯录、项目/任务、协作文档、推送和更新能力。
4. 在 Android、iOS、Windows、macOS、Linux 真机分别执行功能矩阵后，再替换旧客户端入口。

## 代码结构迁移

- 通讯录页面和好友管理弹窗已从 `main.dart` 迁移到 `lib/features/contacts/`，项目工作区和文档编辑器已迁移到 `lib/features/projects/`；页面只依赖仓储契约、领域模型与必要的平台存储适配。
- 设置页已迁移到 `lib/features/settings/`；后续继续拆分消息页，`main.dart` 最终只保留应用启动与顶层装配。
