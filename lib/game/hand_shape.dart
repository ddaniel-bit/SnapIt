/// Kéztartás a pózban: mely ujjak legyenek kinyújtva.
enum HandShape {
  /// Nem számít (pl. a kéz a csípőn, telefont tart, nem látszik jól).
  any('', ''),
  open('Open hand', '✋'),
  fist('Fist', '✊'),
  point('Point', '☝️'),
  peace('Peace', '✌️');

  const HandShape(this.label, this.emoji);
  final String label;
  final String emoji;
}

/// Az ujjak nyújtottságából (lásd `HandSample.fingers`) mennyire egyezik a
/// kéz a kért tartással (0–1). A küszöbök tapasztalati értékek.
class HandShapeScorer {
  const HandShapeScorer();

  // Ujjhegy / alapízület távolság a csuklótól: nyújtva ~1,8–2, ökölben ~1–1,2.
  static const double curledBelow = 1.3;
  static const double extendedAbove = 1.65;

  // Hüvelykujj: a hegye és a mutatóujj töve távolsága a tenyérhez mérve.
  static const double thumbTuckedBelow = 0.45;
  static const double thumbOutAbove = 0.75;

  /// `null`, ha a szükséges ujjak nem látszanak (nem számít bele).
  double? score(HandShape shape, List<double> fingers) {
    if (shape == HandShape.any || fingers.length < 5) return null;
    final thumb = fingers[0];
    final index = fingers[1], middle = fingers[2];
    final ring = fingers[3], little = fingers[4];

    // Ujjanként: kinyújtott (true) vagy behajlított (false) legyen-e.
    final want = <(double, bool)>[
      switch (shape) {
        HandShape.open => (index, true),
        HandShape.fist => (index, false),
        HandShape.point => (index, true),
        HandShape.peace => (index, true),
        HandShape.any => (index, true),
      },
      (middle, shape == HandShape.open || shape == HandShape.peace),
      (ring, shape == HandShape.open),
      (little, shape == HandShape.open),
    ];

    var sum = 0.0;
    var n = 0;
    for (final (ratio, extended) in want) {
      if (ratio < 0) continue; // nem látszik
      final e = _ramp(ratio, curledBelow, extendedAbove);
      sum += extended ? e : 1 - e;
      n++;
    }
    // Nyitott kéznél a hüvelykujj is legyen kint.
    if (shape == HandShape.open && thumb >= 0) {
      sum += _ramp(thumb, thumbTuckedBelow, thumbOutAbove);
      n++;
    }
    // Legalább három ujjat látnunk kell, hogy ítéljünk.
    if (n < 3) return null;
    return sum / n;
  }

  static double _ramp(double v, double from, double to) =>
      ((v - from) / (to - from)).clamp(0.0, 1.0);
}
