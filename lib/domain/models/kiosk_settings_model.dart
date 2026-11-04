import '../../core/utils/parse_utils.dart';

/// The kiosk exit PIN the admin app accepts: 4 to 8 digits. The database
/// allows 4 to 12 (db/kiosk_settings.sql), the kiosk's own limit.
final kExitPinFormat = RegExp(r'^[0-9]{4,8}$');

/// Why [pin] can't be saved as the exit PIN, or null when it can.
String? exitPinProblem(String pin, String confirm) {
  if (!kExitPinFormat.hasMatch(pin)) return 'Use 4 to 8 digits.';
  if (pin != confirm) return 'The two PINs do not match.';
  return null;
}

/// Maps to the single-row `kiosk_settings` table read by the kiosk tablet app.
class KioskSettingsModel {
  static const int minIdleTimeout = 30;
  static const int maxIdleTimeout = 300;
  static const int defaultIdleTimeout = 120;

  final int? id;
  final String welcomeMessage;
  final String disclaimerText;
  final String appDownloadUrl;
  final int idleTimeoutSeconds;
  final bool isSurveyEnabled;
  final String announcementText;
  final DateTime? updatedAt;

  /// Whether `exit_pin` holds a PIN. The PIN itself is never kept, shown or
  /// written back by [toJson]; only `KioskRepository.setExitPin` writes it.
  final bool hasExitPin;

  const KioskSettingsModel({
    this.id,
    this.welcomeMessage = '',
    this.disclaimerText = '',
    this.appDownloadUrl = '',
    this.idleTimeoutSeconds = defaultIdleTimeout,
    this.isSurveyEnabled = true,
    this.announcementText = '',
    this.updatedAt,
    this.hasExitPin = false,
  });

  factory KioskSettingsModel.fromJson(Map<String, dynamic> json) {
    return KioskSettingsModel(
      id: parseInt(json['id']),
      welcomeMessage: json['welcome_message']?.toString() ?? '',
      disclaimerText: json['disclaimer_text']?.toString() ?? '',
      appDownloadUrl: json['app_download_url']?.toString() ?? '',
      idleTimeoutSeconds: (parseInt(json['idle_timeout_seconds']) ??
              defaultIdleTimeout)
          .clamp(minIdleTimeout, maxIdleTimeout),
      isSurveyEnabled: parseBool(json['is_survey_enabled'], fallback: true),
      announcementText: json['announcement_text']?.toString() ?? '',
      updatedAt: parseDate(json['updated_at']),
      hasExitPin: (json['exit_pin']?.toString().trim() ?? '').isNotEmpty,
    );
  }

  /// Empty text fields are saved as null so the kiosk app can treat them as
  /// "not set". `updated_at` is stamped by the repository on save. Never
  /// holds `exit_pin`, so saving settings leaves the PIN as it is.
  Map<String, dynamic> toJson() {
    String? orNull(String s) => s.trim().isEmpty ? null : s.trim();
    return {
      if (id != null) 'id': id,
      'welcome_message': orNull(welcomeMessage),
      'disclaimer_text': orNull(disclaimerText),
      'app_download_url': orNull(appDownloadUrl),
      'idle_timeout_seconds': idleTimeoutSeconds,
      'is_survey_enabled': isSurveyEnabled,
      'announcement_text': orNull(announcementText),
      'updated_at': updatedAt?.toUtc().toIso8601String(),
    };
  }

  KioskSettingsModel copyWith({
    int? id,
    String? welcomeMessage,
    String? disclaimerText,
    String? appDownloadUrl,
    int? idleTimeoutSeconds,
    bool? isSurveyEnabled,
    String? announcementText,
    DateTime? updatedAt,
    bool? hasExitPin,
  }) {
    return KioskSettingsModel(
      id: id ?? this.id,
      welcomeMessage: welcomeMessage ?? this.welcomeMessage,
      disclaimerText: disclaimerText ?? this.disclaimerText,
      appDownloadUrl: appDownloadUrl ?? this.appDownloadUrl,
      idleTimeoutSeconds: idleTimeoutSeconds ?? this.idleTimeoutSeconds,
      isSurveyEnabled: isSurveyEnabled ?? this.isSurveyEnabled,
      announcementText: announcementText ?? this.announcementText,
      updatedAt: updatedAt ?? this.updatedAt,
      hasExitPin: hasExitPin ?? this.hasExitPin,
    );
  }
}
