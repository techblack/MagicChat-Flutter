/// 私聊用户安全操作使用的服务端枚举。
enum UserReportReason {
  sexualContent,
  violenceOrThreat,
  harassmentOrAbuse,
  hateOrDiscrimination,
  fraud,
  spam,
  illegalContent,
  privacyOrIpViolation,
  other,
}

const userReportReasons = <UserReportReason, ({String label, String value})>{
  UserReportReason.sexualContent: (label: '色情低俗', value: 'sexual_content'),
  UserReportReason.violenceOrThreat: (
    label: '暴力或威胁',
    value: 'violence_or_threat'
  ),
  UserReportReason.harassmentOrAbuse: (
    label: '骚扰或辱骂',
    value: 'harassment_or_abuse'
  ),
  UserReportReason.hateOrDiscrimination: (
    label: '仇恨或歧视',
    value: 'hate_or_discrimination',
  ),
  UserReportReason.fraud: (label: '诈骗', value: 'fraud'),
  UserReportReason.spam: (label: '垃圾广告', value: 'spam'),
  UserReportReason.illegalContent: (label: '违法违规', value: 'illegal_content'),
  UserReportReason.privacyOrIpViolation: (
    label: '侵犯隐私或知识产权',
    value: 'privacy_or_ip_violation',
  ),
  UserReportReason.other: (label: '其他', value: 'other'),
};

String userReportReasonLabel(UserReportReason reason) =>
    userReportReasons[reason]!.label;

String userReportReasonValue(UserReportReason reason) =>
    userReportReasons[reason]!.value;

class UserBlockStatus {
  const UserBlockStatus(
      {required this.userId, required this.blocked, this.blockedAt});

  final String userId;
  final bool blocked;
  final String? blockedAt;
}
