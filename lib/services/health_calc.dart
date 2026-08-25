/// Ported 1:1 from `utils/health.js`.
class HealthCalc {
  HealthCalc._();

  /// BMI = weight(kg) / height(m)^2
  static double? calculateBMI(double? weightKg, double? heightCm) {
    if (weightKg == null || heightCm == null || weightKg == 0 || heightCm == 0) {
      return null;
    }
    final heightM = heightCm / 100;
    return ((weightKg / (heightM * heightM)) * 10).round() / 10;
  }

  /// WHO standard categories.
  static String? bmiCategory(double? bmi) {
    if (bmi == null) return null;
    if (bmi < 18.5) return 'underweight';
    if (bmi < 25) return 'normal';
    if (bmi < 30) return 'overweight';
    return 'obese';
  }

  /// Calories = weight(kg) x distance(km) x 1.036
  static int calculateCalories(double? distanceKm, double? weightKg) {
    final weight = weightKg ?? 70;
    return (weight * (distanceKm ?? 0) * 1.036).round();
  }
}
