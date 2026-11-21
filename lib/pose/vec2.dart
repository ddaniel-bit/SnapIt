import 'dart:math' as math;

/// Egyszerű 2D vektor.
///
/// Szándékosan nem `Offset` (dart:ui), hogy a geometria réteg Flutter-mentes
/// és tisztán unit-tesztelhető maradjon.
class Vec2 {
  const Vec2(this.x, this.y);

  final double x;
  final double y;

  Vec2 operator +(Vec2 other) => Vec2(x + other.x, y + other.y);

  Vec2 operator -(Vec2 other) => Vec2(x - other.x, y - other.y);

  Vec2 operator *(double scalar) => Vec2(x * scalar, y * scalar);

  double get length => math.sqrt(x * x + y * y);

  double dot(Vec2 other) => x * other.x + y * other.y;

  /// A 2D keresztszorzat skalár része (z komponens).
  double cross(Vec2 other) => x * other.y - y * other.x;

  @override
  String toString() => 'Vec2(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})';

  @override
  bool operator ==(Object other) =>
      other is Vec2 && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}
