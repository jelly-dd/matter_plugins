/// 配网/控制过程中可能抛出的异常。
class MatterException implements Exception {
  final String code;
  final String message;

  const MatterException(this.code, this.message);

  @override
  String toString() => 'MatterException($code): $message';
}
