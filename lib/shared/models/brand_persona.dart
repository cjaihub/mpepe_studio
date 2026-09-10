import 'package:flutter/foundation.dart';
import '../../upload/models/connected_destination.dart';

@immutable
class BrandPersona {
  final String id;
  final String name;
  final String niche;
  final String avatarUrl;
  final List<PlatformType> connectedPlatforms;

  const BrandPersona({
    required this.id,
    required this.name,
    required this.niche,
    required this.avatarUrl,
    required this.connectedPlatforms,
  });

  BrandPersona copyWith({
    String? id,
    String? name,
    String? niche,
    String? avatarUrl,
    List<PlatformType>? connectedPlatforms,
  }) {
    return BrandPersona(
      id: id ?? this.id,
      name: name ?? this.name,
      niche: niche ?? this.niche,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      connectedPlatforms: connectedPlatforms ?? this.connectedPlatforms,
    );
  }
}
