import '../../core/utils/parse_utils.dart';

class AboutUmModel {
  final String? id;
  final String? mission;
  final String? vision;
  final List<String> coreValues;
  final int? founded;
  final String? campusSize;
  final String? location;
  final String? ranking;
  final String? phone;
  final String? email;
  final String? website;
  final String? facebook;
  final String? instagram;
  final String? twitter;
  final DateTime? updatedAt;

  const AboutUmModel({
    this.id,
    this.mission,
    this.vision,
    this.coreValues = const [],
    this.founded,
    this.campusSize,
    this.location,
    this.ranking,
    this.phone,
    this.email,
    this.website,
    this.facebook,
    this.instagram,
    this.twitter,
    this.updatedAt,
  });

  factory AboutUmModel.fromJson(Map<String, dynamic> json) {
    return AboutUmModel(
      id: json['id']?.toString(),
      mission: json['mission']?.toString(),
      vision: json['vision']?.toString(),
      coreValues: parseStringList(json['core_values']),
      founded: parseInt(json['founded']),
      campusSize: json['campus_size']?.toString(),
      location: json['location']?.toString(),
      ranking: json['ranking']?.toString(),
      phone: json['phone']?.toString(),
      email: json['email']?.toString(),
      website: json['website']?.toString(),
      facebook: json['facebook']?.toString(),
      instagram: json['instagram']?.toString(),
      twitter: json['twitter']?.toString(),
      updatedAt: parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'mission': mission,
      'vision': vision,
      'core_values': coreValues,
      'founded': founded,
      'campus_size': campusSize,
      'location': location,
      'ranking': ranking,
      'phone': phone,
      'email': email,
      'website': website,
      'facebook': facebook,
      'instagram': instagram,
      'twitter': twitter,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  AboutUmModel copyWith({
    String? mission,
    String? vision,
    List<String>? coreValues,
    int? founded,
    String? campusSize,
    String? location,
    String? ranking,
    String? phone,
    String? email,
    String? website,
    String? facebook,
    String? instagram,
    String? twitter,
  }) {
    return AboutUmModel(
      id: id,
      mission: mission ?? this.mission,
      vision: vision ?? this.vision,
      coreValues: coreValues ?? this.coreValues,
      founded: founded ?? this.founded,
      campusSize: campusSize ?? this.campusSize,
      location: location ?? this.location,
      ranking: ranking ?? this.ranking,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      website: website ?? this.website,
      facebook: facebook ?? this.facebook,
      instagram: instagram ?? this.instagram,
      twitter: twitter ?? this.twitter,
      updatedAt: updatedAt,
    );
  }
}
