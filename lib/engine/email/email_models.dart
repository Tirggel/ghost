import 'package:uuid/uuid.dart';

class EmailAccount {
  EmailAccount({
    required this.id,
    required this.name,
    required this.email,
    required this.imapHost,
    required this.imapPort,
    required this.imapSecure,
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpSecure,
    this.autoSummarize = true,
    this.autoReply = false,
    this.autoTag = true,
    this.autoSpam = false,
    this.autoCalendar = false,
    this.autoUrgent = false,
    this.writingStyle = 'Friendly, polite and concise.',
    this.enabled = true,
  });

  factory EmailAccount.create({
    required String name,
    required String email,
    required String imapHost,
    required int imapPort,
    required bool imapSecure,
    required String smtpHost,
    required int smtpPort,
    required bool smtpSecure,
  }) {
    return EmailAccount(
      id: const Uuid().v4(),
      name: name,
      email: email,
      imapHost: imapHost,
      imapPort: imapPort,
      imapSecure: imapSecure,
      smtpHost: smtpHost,
      smtpPort: smtpPort,
      smtpSecure: smtpSecure,
    );
  }

  factory EmailAccount.fromJson(Map<String, dynamic> json) {
    return EmailAccount(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      imapHost: json['imapHost'] as String? ?? '',
      imapPort: (json['imapPort'] as num?)?.toInt() ?? 993,
      imapSecure: json['imapSecure'] as bool? ?? true,
      smtpHost: json['smtpHost'] as String? ?? '',
      smtpPort: (json['smtpPort'] as num?)?.toInt() ?? 465,
      smtpSecure: json['smtpSecure'] as bool? ?? true,
      autoSummarize: json['autoSummarize'] as bool? ?? true,
      autoReply: json['autoReply'] as bool? ?? false,
      autoTag: json['autoTag'] as bool? ?? true,
      autoSpam: json['autoSpam'] as bool? ?? false,
      autoCalendar: json['autoCalendar'] as bool? ?? false,
      autoUrgent: json['autoUrgent'] as bool? ?? false,
      writingStyle: json['writingStyle'] as String? ?? 'Friendly, polite and concise.',
      enabled: json['enabled'] as bool? ?? true,
    );
  }
  final String id;
  final String name;
  final String email;
  final String imapHost;
  final int imapPort;
  final bool imapSecure;
  final String smtpHost;
  final int smtpPort;
  final bool smtpSecure;
  final bool autoSummarize;
  final bool autoReply;
  final bool autoTag;
  final bool autoSpam;
  final bool autoCalendar;
  final bool autoUrgent;
  final String writingStyle;
  final bool enabled;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'imapHost': imapHost,
        'imapPort': imapPort,
        'imapSecure': imapSecure,
        'smtpHost': smtpHost,
        'smtpPort': smtpPort,
        'smtpSecure': smtpSecure,
        'autoSummarize': autoSummarize,
        'autoReply': autoReply,
        'autoTag': autoTag,
        'autoSpam': autoSpam,
        'autoCalendar': autoCalendar,
        'autoUrgent': autoUrgent,
        'writingStyle': writingStyle,
        'enabled': enabled,
      };

  EmailAccount copyWith({
    String? name,
    String? email,
    String? imapHost,
    int? imapPort,
    bool? imapSecure,
    String? smtpHost,
    int? smtpPort,
    bool? smtpSecure,
    bool? autoSummarize,
    bool? autoReply,
    bool? autoTag,
    bool? autoSpam,
    bool? autoCalendar,
    bool? autoUrgent,
    String? writingStyle,
    bool? enabled,
  }) {
    return EmailAccount(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      imapHost: imapHost ?? this.imapHost,
      imapPort: imapPort ?? this.imapPort,
      imapSecure: imapSecure ?? this.imapSecure,
      smtpHost: smtpHost ?? this.smtpHost,
      smtpPort: smtpPort ?? this.smtpPort,
      smtpSecure: smtpSecure ?? this.smtpSecure,
      autoSummarize: autoSummarize ?? this.autoSummarize,
      autoReply: autoReply ?? this.autoReply,
      autoTag: autoTag ?? this.autoTag,
      autoSpam: autoSpam ?? this.autoSpam,
      autoCalendar: autoCalendar ?? this.autoCalendar,
      autoUrgent: autoUrgent ?? this.autoUrgent,
      writingStyle: writingStyle ?? this.writingStyle,
      enabled: enabled ?? this.enabled,
    );
  }
}

class CachedEmail {
  CachedEmail({
    required this.id,
    required this.accountId,
    required this.uid,
    required this.folder,
    required this.messageId,
    required this.subject,
    required this.sender,
    required this.to,
    required this.date,
    required this.bodyText,
    required this.bodyHtml,
    required this.isRead,
    required this.isFavorite,
    required this.hasAttachments,
    this.spamVerdict = false,
    this.spamReason = '',
    this.summary = '',
    this.aiReplyDraft = '',
    this.tags = const [],
    this.urgency = 'none',
    this.urgencyReason = '',
  });

  factory CachedEmail.fromJson(Map<String, dynamic> json) {
    return CachedEmail(
      id: json['id'] as String,
      accountId: json['accountId'] as String? ?? '',
      uid: (json['uid'] as num?)?.toInt() ?? 0,
      folder: json['folder'] as String? ?? 'INBOX',
      messageId: json['messageId'] as String? ?? '',
      subject: json['subject'] as String? ?? '',
      sender: json['sender'] as String? ?? '',
      to: json['to'] as String? ?? '',
      date: DateTime.parse(json['date'] as String? ?? DateTime.now().toIso8601String()),
      bodyText: json['bodyText'] as String? ?? '',
      bodyHtml: json['bodyHtml'] as String? ?? '',
      isRead: json['isRead'] as bool? ?? false,
      isFavorite: json['isFavorite'] as bool? ?? false,
      hasAttachments: json['hasAttachments'] as bool? ?? false,
      spamVerdict: json['spamVerdict'] as bool? ?? false,
      spamReason: json['spamReason'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      aiReplyDraft: json['aiReplyDraft'] as String? ?? '',
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
      urgency: json['urgency'] as String? ?? 'none',
      urgencyReason: json['urgencyReason'] as String? ?? '',
    );
  }
  final String id;
  final String accountId;
  final int uid;
  final String folder;
  final String messageId;
  final String subject;
  final String sender;
  final String to;
  final DateTime date;
  final String bodyText;
  final String bodyHtml;
  final bool isRead;
  final bool isFavorite;
  final bool hasAttachments;
  final bool spamVerdict;
  final String spamReason;
  final String summary;
  final String aiReplyDraft;
  final List<String> tags;
  final String urgency;
  final String urgencyReason;

  Map<String, dynamic> toJson() => {
        'id': id,
        'accountId': accountId,
        'uid': uid,
        'folder': folder,
        'messageId': messageId,
        'subject': subject,
        'sender': sender,
        'to': to,
        'date': date.toIso8601String(),
        'bodyText': bodyText,
        'bodyHtml': bodyHtml,
        'isRead': isRead,
        'isFavorite': isFavorite,
        'hasAttachments': hasAttachments,
        'spamVerdict': spamVerdict,
        'spamReason': spamReason,
        'summary': summary,
        'aiReplyDraft': aiReplyDraft,
        'tags': tags,
        'urgency': urgency,
        'urgencyReason': urgencyReason,
      };

  CachedEmail copyWith({
    String? folder,
    bool? isRead,
    bool? isFavorite,
    bool? spamVerdict,
    String? spamReason,
    String? summary,
    String? aiReplyDraft,
    List<String>? tags,
    String? urgency,
    String? urgencyReason,
    String? bodyText,
    String? bodyHtml,
  }) {
    return CachedEmail(
      id: id,
      accountId: accountId,
      uid: uid,
      folder: folder ?? this.folder,
      messageId: messageId,
      subject: subject,
      sender: sender,
      to: to,
      date: date,
      bodyText: bodyText ?? this.bodyText,
      bodyHtml: bodyHtml ?? this.bodyHtml,
      isRead: isRead ?? this.isRead,
      isFavorite: isFavorite ?? this.isFavorite,
      hasAttachments: hasAttachments,
      spamVerdict: spamVerdict ?? this.spamVerdict,
      spamReason: spamReason ?? this.spamReason,
      summary: summary ?? this.summary,
      aiReplyDraft: aiReplyDraft ?? this.aiReplyDraft,
      tags: tags ?? this.tags,
      urgency: urgency ?? this.urgency,
      urgencyReason: urgencyReason ?? this.urgencyReason,
    );
  }
}

class EmailFolder {
  EmailFolder({
    required this.name,
    this.unreadCount = 0,
    this.totalCount = 0,
  });

  factory EmailFolder.fromJson(Map<String, dynamic> json) {
    return EmailFolder(
      name: json['name'] as String,
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      totalCount: (json['totalCount'] as num?)?.toInt() ?? 0,
    );
  }
  final String name;
  final int unreadCount;
  final int totalCount;

  Map<String, dynamic> toJson() => {
        'name': name,
        'unreadCount': unreadCount,
        'totalCount': totalCount,
      };
}
