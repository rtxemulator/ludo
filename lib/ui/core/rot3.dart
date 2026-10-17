/// Minimal 3D vector and rotation matrix for the dice cube. Pure Dart.
library;

import 'dart:math' as math;

class Vec3 {
  const Vec3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);

  Vec3 operator *(double k) => Vec3(x * k, y * k, z * k);

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;

  Vec3 cross(Vec3 o) => Vec3(
        y * o.z - z * o.y,
        z * o.x - x * o.z,
        x * o.y - y * o.x,
      );

  double get length => math.sqrt(dot(this));

  Vec3 normalized() {
    final l = length;
    return l == 0 ? this : Vec3(x / l, y / l, z / l);
  }

  @override
  String toString() => 'Vec3($x, $y, $z)';
}

/// 3 x 3 rotation matrix, row-major.
///
/// Screen convention used by the dice: x right, y down, z toward the
/// viewer (so the face on top has normal `+z`).
class Mat3 {
  const Mat3._(this._m);

  static const Mat3 identity = Mat3._([1, 0, 0, 0, 1, 0, 0, 0, 1]);

  final List<double> _m;

  /// Element at [row], [col].
  double at(int row, int col) => _m[row * 3 + col];

  static Mat3 rotationX(double a) {
    final c = math.cos(a);
    final s = math.sin(a);
    return Mat3._([1, 0, 0, 0, c, -s, 0, s, c]);
  }

  static Mat3 rotationY(double a) {
    final c = math.cos(a);
    final s = math.sin(a);
    return Mat3._([c, 0, s, 0, 1, 0, -s, 0, c]);
  }

  static Mat3 rotationZ(double a) {
    final c = math.cos(a);
    final s = math.sin(a);
    return Mat3._([c, -s, 0, s, c, 0, 0, 0, 1]);
  }

  /// Rotation by [angle] radians about [axis] (Rodrigues' formula).
  static Mat3 axisAngle(Vec3 axis, double angle) {
    final n = axis.normalized();
    final c = math.cos(angle);
    final s = math.sin(angle);
    final t = 1 - c;
    return Mat3._([
      t * n.x * n.x + c,
      t * n.x * n.y - s * n.z,
      t * n.x * n.z + s * n.y,
      t * n.x * n.y + s * n.z,
      t * n.y * n.y + c,
      t * n.y * n.z - s * n.x,
      t * n.x * n.z - s * n.y,
      t * n.y * n.z + s * n.x,
      t * n.z * n.z + c,
    ]);
  }

  Mat3 operator *(Mat3 o) {
    final r = List<double>.filled(9, 0);
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 3; j++) {
        var sum = 0.0;
        for (var k = 0; k < 3; k++) {
          sum += _m[i * 3 + k] * o._m[k * 3 + j];
        }
        r[i * 3 + j] = sum;
      }
    }
    return Mat3._(r);
  }

  Vec3 apply(Vec3 v) => Vec3(
        _m[0] * v.x + _m[1] * v.y + _m[2] * v.z,
        _m[3] * v.x + _m[4] * v.y + _m[5] * v.z,
        _m[6] * v.x + _m[7] * v.y + _m[8] * v.z,
      );

  /// Transpose (the inverse, for a rotation).
  Mat3 get transposed => Mat3._([
        _m[0], _m[3], _m[6], //
        _m[1], _m[4], _m[7], //
        _m[2], _m[5], _m[8],
      ]);

  /// Largest absolute difference to [other] (for tests).
  double maxDifference(Mat3 other) {
    var d = 0.0;
    for (var i = 0; i < 9; i++) {
      d = math.max(d, (_m[i] - other._m[i]).abs());
    }
    return d;
  }
}
